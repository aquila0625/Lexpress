package com.yishulabs.qtranslator.conversation

import com.yishulabs.qtranslator.core.SentenceResult
import com.yishulabs.qtranslator.core.WordEntry
import kotlinx.serialization.Serializable
import java.util.UUID

private fun newId() = UUID.randomUUID().toString()

/** 场景的封面：一个图标加一组配色。图标用和苹果版相同的名字，界面里再对应到 Material 图标 */
@Serializable
data class SceneCover(val symbol: String, val palette: Int) {
    companion object {
        val symbols = listOf(
            "book.closed.fill", "graduationcap.fill", "sun.max.fill", "leaf.fill",
            "house.fill", "airplane", "fork.knife", "cart.fill",
            "briefcase.fill", "cross.case.fill", "bubble.left.and.bubble.right.fill", "star.fill",
        )
    }
}

/** 场景：会话的第一层分组，例如“教室”“户外交流” */
@Serializable
data class SceneGroup(val id: String = newId(), val name: String, val cover: SceneCover)

/** 一张图片：本机文件名、识别出的文字和它的译文 */
@Serializable
data class TurnImage(
    val id: String = newId(),
    val fileName: String,
    val recognized: String = "",
    val translation: String = "",
    val done: Boolean = false,
)

@Serializable
enum class TurnState { WORKING, DONE, FAILED }

/** 会话里的一轮：一次输入（文字或几张图片）和它的翻译结果 */
@Serializable
data class Turn(
    val id: String = newId(),
    val source: String,
    val images: List<TurnImage> = emptyList(),
    val sourceIsChinese: Boolean,
    /** 用户手动指定了方向；否则按内容自动识别 */
    val manualDirection: Boolean = false,
    val edited: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val state: TurnState = TurnState.WORKING,
    val word: WordEntry? = null,
    val sentence: SentenceResult? = null,
    val errorMessage: String? = null,
    val aiError: String? = null,
    val isOptimizing: Boolean = false,
) {
    val isImage: Boolean get() = images.isNotEmpty()

    /** 输入记录里显示的那一行 */
    val outlineText: String
        get() {
            if (!isImage) return source
            val parts = images.map { it.recognized.take(24) }.filter { it.isNotEmpty() }
            return "${images.size} 张图片" + if (parts.isEmpty()) "" else "：" + parts.joinToString(" / ")
        }

    /** 搜索时匹配的全部文字 */
    val searchableText: String
        get() = listOf(source, sentence?.translation ?: "", word?.summary ?: "").joinToString("\n") +
            images.joinToString("\n") { it.recognized + "\n" + it.translation }
}

/** 一个翻译会话 */
@Serializable
data class ChatSession(
    val id: String = newId(),
    val title: String,
    /** 还没有被用户命名过：第一轮翻译后用原文开头当名称 */
    val autoTitled: Boolean = true,
    val sceneId: String? = null,
    val aiEnabled: Boolean,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val turns: List<Turn> = emptyList(),
) {
    val lastSnippet: String
        get() {
            val last = turns.lastOrNull() ?: return "还没有内容"
            return if (last.isImage) "${last.images.size} 张图片" else last.source
        }

    companion object {
        const val DEFAULT_TITLE = "新会话"
    }
}
