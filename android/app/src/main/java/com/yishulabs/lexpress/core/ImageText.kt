package com.yishulabs.lexpress.core

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions

/** 本机识别图片里的文字（中英文都能认），图片不上传。 */
object ImageText {
    private val recognizer by lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }

    suspend fun recognize(bitmap: Bitmap): String {
        val result = recognizer.process(InputImage.fromBitmap(bitmap, 0)).await()
        // 每个文字块是一段；块里的行按语言拼起来：英文行之间加空格，中文直接连上
        return result.textBlocks.joinToString("\n") { block ->
            block.lines.map { it.text.trim() }.filter { it.isNotEmpty() }.fold("") { acc, line ->
                when {
                    acc.isEmpty() -> line
                    acc.endsWith("-") -> acc.dropLast(1) + line
                    acc.last().isCjk() || line.first().isCjk() -> acc + line
                    else -> "$acc $line"
                }
            }
        }.trim()
    }

    private fun Char.isCjk(): Boolean = this in '一'..'鿿' || this in '　'..'〿' || this in '＀'..'￯'
}
