package com.yishulabs.lexpress.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** 很小的 HTTP 工具：在 IO 线程上发请求，返回状态码和文本 */
object Http {
    class Response(val status: Int, val body: String)

    fun query(vararg pairs: Pair<String, String>): String =
        pairs.joinToString("&") { (k, v) -> k + "=" + URLEncoder.encode(v, "UTF-8") }

    suspend fun get(url: String, timeoutMs: Int = 10_000, headers: Map<String, String> = emptyMap()): Response =
        request("GET", url, null, timeoutMs, headers)

    suspend fun post(url: String, body: String, timeoutMs: Int = 120_000, headers: Map<String, String> = emptyMap()): Response =
        request("POST", url, body, timeoutMs, headers)

    private suspend fun request(
        method: String, url: String, body: String?, timeoutMs: Int, headers: Map<String, String>,
    ): Response = withContext(Dispatchers.IO) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            headers.forEach { (k, v) -> connection.setRequestProperty(k, v) }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            Response(status, text)
        } finally {
            connection.disconnect()
        }
    }
}
