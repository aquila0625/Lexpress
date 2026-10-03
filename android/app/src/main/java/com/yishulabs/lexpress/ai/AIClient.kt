package com.yishulabs.lexpress.ai

import com.yishulabs.lexpress.core.AIUsage
import com.yishulabs.lexpress.core.Http
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException

class AIException(message: String) : Exception(message)

class AIResponse(val text: String, val usage: AIUsage?)

/** 用用户自己的 key 直接请求 AI 服务商，中间不经过任何 Lexpress 的服务器。 */
object AIClient {
    data class Config(val provider: AIProvider, val apiKey: String, val model: String, val baseUrl: String)

    suspend fun complete(system: String, user: String, config: Config): AIResponse {
        if (config.apiKey.isEmpty()) throw AIException("还没有填写 API Key。")
        val response = when (config.provider) {
            AIProvider.CLAUDE -> claude(system, user, config)
            else -> openAICompatible(system, user, config)
        }
        response.usage?.let { usage ->
            withContext(Dispatchers.Main) { UsageStore.add(config.provider, config.model, usage) }
        }
        return response
    }

    // Claude（Anthropic Messages API）

    private suspend fun claude(system: String, user: String, config: Config): AIResponse {
        val headers = mutableMapOf("x-api-key" to config.apiKey, "anthropic-version" to "2023-06-01")
        val body = JSONObject()
            .put("model", config.model)
            .put("max_tokens", 16000)
            .put("system", system)
            .put("messages", JSONArray().put(JSONObject().put("role", "user").put("content", user)))
        // 新模型的安全分类器偶尔会误拒正常请求，让服务端自动换到推荐的后备模型重试
        if (supportsDefaultFallback(config.model)) {
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
            body.put("fallbacks", "default")
        }
        val json = send("https://api.anthropic.com/v1/messages", body, headers)
        if (json.optString("stop_reason") == "refusal") throw AIException("AI 拒绝了这次请求，可以改一下内容再试。")
        val content = json.optJSONArray("content") ?: JSONArray()
        val text = (0 until content.length()).map { content.getJSONObject(it) }
            .filter { it.optString("type") == "text" }
            .joinToString("") { it.optString("text") }
        if (text.isBlank()) throw AIException("AI 没有返回内容。")
        val usage = json.optJSONObject("usage")
        return AIResponse(text.trim(), usage(usage, "input_tokens", "output_tokens"))
    }

    private fun supportsDefaultFallback(model: String) =
        model.startsWith("claude-opus-5") || model.startsWith("claude-fable-5") || model == "claude-sonnet-5-5"

    // OpenAI 兼容接口（ChatGPT、DeepSeek 和自定义服务商）

    private suspend fun openAICompatible(system: String, user: String, config: Config): AIResponse {
        val base = config.baseUrl.trimEnd('/')
        if (!base.startsWith("http")) throw AIException("接口地址不正确。")
        val body = JSONObject()
            .put("model", config.model)
            .put(
                "messages", JSONArray()
                    .put(JSONObject().put("role", "system").put("content", system))
                    .put(JSONObject().put("role", "user").put("content", user))
            )
        val json = send("$base/chat/completions", body, mapOf("Authorization" to "Bearer ${config.apiKey}"))
        val text = json.optJSONArray("choices")?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
        if (text.isNullOrBlank()) throw AIException("AI 没有返回内容。")
        return AIResponse(text.trim(), usage(json.optJSONObject("usage"), "prompt_tokens", "completion_tokens"))
    }

    // 公共

    private fun usage(json: JSONObject?, input: String, output: String): AIUsage? {
        if (json == null || !json.has(input) || !json.has(output)) return null
        return AIUsage(json.optInt(input), json.optInt(output))
    }

    private suspend fun send(url: String, body: JSONObject, headers: Map<String, String>): JSONObject {
        val response = try {
            Http.post(url, body.toString(), headers = headers)
        } catch (e: IOException) {
            throw AIException("连不上 AI 服务，请检查网络。")
        }
        val json = runCatching { JSONObject(response.body) }.getOrDefault(JSONObject())
        if (response.status != 200) {
            throw when (response.status) {
                401, 403 -> AIException("API Key 无效或没有权限。")
                429 -> AIException("请求太频繁或额度用完了，稍后再试。")
                else -> AIException(json.optJSONObject("error")?.optString("message")?.ifBlank { null }
                    ?: "AI 服务出错（${response.status}）。")
            }
        }
        return json
    }
}
