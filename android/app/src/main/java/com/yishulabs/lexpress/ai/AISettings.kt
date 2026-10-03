package com.yishulabs.lexpress.ai

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yishulabs.lexpress.core.SecretStore

/** AI 服务商。Lexpress 不内置任何 key，用户自己去服务商那里注册，把 key 填进来。 */
enum class AIProvider(
    val title: String,
    /** 去哪里注册并获取 API Key */
    val signupUrl: String?,
    val defaultModel: String,
    /** 下拉里直接可选的模型，按代分组，每组里从便宜到贵；其它模型可以手动填写 */
    val modelGroups: List<Pair<String, List<String>>>,
    /** OpenAI 兼容接口的地址（Claude 走自己的 Messages API，不用这个） */
    val defaultBaseUrl: String,
) {
    CLAUDE(
        "Claude", "https://platform.claude.com/", "claude-opus-5-5",
        listOf("Claude" to listOf("claude-haiku-4-5", "claude-sonnet-5-5", "claude-opus-5-5")), "",
    ),
    OPENAI(
        "ChatGPT", "https://platform.openai.com/api-keys", "gpt-6-luna",
        listOf(
            "GPT-6" to listOf("gpt-6-luna", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-astra"),
            "GPT-5" to listOf(
                "gpt-5-nano", "gpt-5-mini", "gpt-5", "gpt-5.1", "gpt-5.2", "gpt-5.4-nano", "gpt-5.4-mini",
                "gpt-5.4", "gpt-5.5", "gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol",
            ),
            "GPT-4" to listOf("gpt-4.1-nano", "gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini", "gpt-4o"),
        ),
        "https://api.openai.com/v1",
    ),
    DEEPSEEK(
        "DeepSeek", "https://platform.deepseek.com/", "deepseek-chat",
        listOf("DeepSeek" to listOf("deepseek-chat", "deepseek-reasoner")), "https://api.deepseek.com",
    ),
    CUSTOM("自定义", null, "", emptyList(), "");

    val key: String get() = name.lowercase()
    val suggestedModels: List<String> get() = modelGroups.flatMap { it.second }
}

object AISettings {
    private lateinit var prefs: SharedPreferences

    var provider by mutableStateOf(AIProvider.CLAUDE)
        private set
    var apiKey by mutableStateOf("")
        private set
    var model by mutableStateOf("")
        private set
    var baseUrl by mutableStateOf("")
        private set
    /** 新会话默认开启 AI 优化：每次翻译句子后自动优化 */
    var autoCalibrate by mutableStateOf(false)
        private set

    fun init(context: Context) {
        prefs = context.getSharedPreferences("ai", Context.MODE_PRIVATE)
        provider = AIProvider.entries.firstOrNull { it.key == prefs.getString("provider", null) } ?: AIProvider.CLAUDE
        autoCalibrate = prefs.getBoolean("autoCalibrate", false)
        load()
    }

    val isConfigured: Boolean
        get() = apiKey.isNotBlank() && model.isNotBlank() && (provider == AIProvider.CLAUDE || baseUrl.isNotBlank())

    fun updateProvider(value: AIProvider) {
        provider = value
        prefs.edit().putString("provider", value.key).apply()
        load()
    }

    fun updateApiKey(value: String) {
        apiKey = value
        SecretStore.set(provider.key, value.trim())
    }

    fun updateModel(value: String) {
        model = value
        prefs.edit().putString("model.${provider.key}", value).apply()
    }

    fun updateBaseUrl(value: String) {
        baseUrl = value
        prefs.edit().putString("baseUrl.${provider.key}", value).apply()
    }

    fun updateAutoCalibrate(value: Boolean) {
        autoCalibrate = value
        prefs.edit().putBoolean("autoCalibrate", value).apply()
    }

    /** 切换服务商后，读出这家服务商各自保存的 key、模型和地址 */
    private fun load() {
        apiKey = SecretStore.get(provider.key) ?: ""
        model = prefs.getString("model.${provider.key}", null) ?: provider.defaultModel
        baseUrl = prefs.getString("baseUrl.${provider.key}", null) ?: provider.defaultBaseUrl
    }

    val currentConfig: AIClient.Config
        get() = AIClient.Config(provider, apiKey.trim(), model.trim(), baseUrl.trim())
}
