package com.yishulabs.lexpress.conversation

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

@Serializable
data class HistoryItem(val text: String, val summary: String, val date: Long, val starred: Boolean = false)

/** 查过的词和生词本（星标），保存在本机。 */
object HistoryStore {
    var items by mutableStateOf(listOf<HistoryItem>())
        private set

    private const val LIMIT = 200
    private lateinit var file: File
    private val json = Json { ignoreUnknownKeys = true }

    fun init(context: Context) {
        file = File(context.filesDir, "history.json")
        items = runCatching { json.decodeFromString<List<HistoryItem>>(file.readText()) }.getOrDefault(emptyList())
    }

    val starred: List<HistoryItem> get() = items.filter { it.starred }

    fun add(text: String, summary: String) {
        val starred = items.firstOrNull { it.text == text }?.starred ?: false
        val list = (listOf(HistoryItem(text, summary, System.currentTimeMillis(), starred)) + items.filter { it.text != text })
            .toMutableList()
        // 超出上限时丢掉最旧的记录，生词本里的保留
        while (list.size > LIMIT) {
            val index = list.indexOfLast { !it.starred }
            if (index < 0) break
            list.removeAt(index)
        }
        items = list
        save()
    }

    fun isStarred(text: String): Boolean = items.firstOrNull { it.text == text }?.starred ?: false

    fun toggleStar(text: String, summary: String = "") {
        items = if (items.any { it.text == text }) {
            items.map { if (it.text == text) it.copy(starred = !it.starred) else it }
        } else {
            listOf(HistoryItem(text, summary, System.currentTimeMillis(), true)) + items
        }
        save()
    }

    private fun save() {
        runCatching { file.writeText(json.encodeToString(items)) }
    }
}
