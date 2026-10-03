package com.yishulabs.lexpress.core

import com.google.android.gms.tasks.Task
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

suspend fun <T> Task<T>.await(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { continuation.resume(it) }
    addOnFailureListener { continuation.resumeWithException(it) }
}

/** 本机离线翻译（Google ML Kit）：中文模型下载一次（约 30 MB）后不用联网、不限量。 */
object OfflineTranslator {
    const val NAME = "本机离线翻译"

    private val translators = mutableMapOf<Boolean, Translator>()

    private fun translator(fromChinese: Boolean): Translator = translators.getOrPut(fromChinese) {
        val options = TranslatorOptions.Builder()
            .setSourceLanguage(if (fromChinese) TranslateLanguage.CHINESE else TranslateLanguage.ENGLISH)
            .setTargetLanguage(if (fromChinese) TranslateLanguage.ENGLISH else TranslateLanguage.CHINESE)
            .build()
        Translation.getClient(options)
    }

    /** 英文模型手机里自带，只需要看中文模型下载了没有 */
    suspend fun isReady(): Boolean = runCatching {
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java).await()
            .any { it.language == TranslateLanguage.CHINESE }
    }.getOrDefault(false)

    suspend fun download() {
        translator(false).downloadModelIfNeeded(DownloadConditions.Builder().build()).await()
    }

    /** 逐段翻译，保留原文的换行 */
    suspend fun translate(text: String, fromChinese: Boolean): String {
        val client = translator(fromChinese)
        return text.split("\n").map { line -> if (line.isBlank()) "" else client.translate(line).await() }.joinToString("\n")
    }
}

/**
 * MyMemory 免费接口：无需 key，匿名每天约 5000 字符，单次请求不超过 500 字节。
 * 只在离线翻译模型还没下载时作为兜底。
 */
object OnlineTranslator {
    const val NAME = "MyMemory 在线"
    private const val CHUNK_LIMIT = 450

    suspend fun translate(text: String, fromChinese: Boolean): String {
        val pair = if (fromChinese) "zh-CN|en" else "en|zh-CN"
        return text.split("\n").map { line ->
            if (line.isBlank()) "" else chunks(line).map { request(it, pair) }.joinToString(if (fromChinese) " " else "")
        }.joinToString("\n")
    }

    private suspend fun request(text: String, pair: String): String {
        val response = Http.get("https://api.mymemory.translated.net/get?" + Http.query("q" to text, "langpair" to pair))
        val result = JSONObject(response.body).optJSONObject("responseData")?.optString("translatedText")
        if (result.isNullOrBlank() || result.uppercase().contains("MYMEMORY WARNING")) error("翻译失败")
        // 接口偶尔会把回车、引号等以 HTML 实体形式返回
        return result.replace("&#x0D;", "", ignoreCase = true).replace("&#39;", "'")
            .replace("&quot;", "\"").replace("&amp;", "&").trim()
    }

    /** 按句子边界切块，保证每块不超过字节上限。 */
    private fun chunks(line: String): List<String> {
        val sentences = mutableListOf<String>()
        val current = StringBuilder()
        for (ch in line) {
            current.append(ch)
            if (ch in ".!?;。！？；" || current.toString().toByteArray().size >= CHUNK_LIMIT - 4) {
                sentences += current.toString()
                current.clear()
            }
        }
        if (current.isNotEmpty()) sentences += current.toString()

        val result = mutableListOf<String>()
        var block = ""
        for (s in sentences) {
            if (block.isNotEmpty() && block.toByteArray().size + s.toByteArray().size > CHUNK_LIMIT) {
                result += block
                block = ""
            }
            block += s
        }
        if (block.isNotBlank()) result += block
        return result
    }
}
