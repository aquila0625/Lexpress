package com.yishulabs.qtranslator.ai

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yishulabs.qtranslator.core.AIUsage
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.Locale

/** 一次 AI 请求的用量 */
@Serializable
data class UsageRecord(val date: Long, val provider: String, val model: String, val input: Int, val output: Int) {
    val total: Int get() = input + output
    val cost: Double? get() = Pricing.cost(model, input, output)
}

/** 记录每次 AI 请求消耗的 token，用于设置页的累计用量和用量报表。只保存在本机。 */
object UsageStore {
    var records by mutableStateOf(listOf<UsageRecord>())
        private set

    private lateinit var file: File
    private val json = Json { ignoreUnknownKeys = true }

    fun init(context: Context) {
        file = File(context.filesDir, "usage.json")
        records = runCatching { json.decodeFromString<List<UsageRecord>>(file.readText()) }.getOrDefault(emptyList())
    }

    fun add(provider: AIProvider, model: String, usage: AIUsage) {
        records = records + UsageRecord(System.currentTimeMillis(), provider.key, model, usage.input, usage.output)
        runCatching { file.writeText(json.encodeToString(records)) }
    }

    fun records(provider: AIProvider?): List<UsageRecord> =
        if (provider == null) records else records.filter { it.provider == provider.key }

    data class Summary(val input: Int = 0, val output: Int = 0, val cost: Double = 0.0, val hasUnpriced: Boolean = false) {
        val total: Int get() = input + output
    }

    fun summarize(records: List<UsageRecord>): Summary = records.fold(Summary()) { s, r ->
        val cost = r.cost
        Summary(s.input + r.input, s.output + r.output, s.cost + (cost ?: 0.0), s.hasUnpriced || cost == null)
    }
}

/**
 * 按服务商公开的标价估算费用（美元 / 每百万 token，输入和输出分开计价）。
 * 只用于估算，实际以服务商账单为准；价格变化后需要更新这张表。
 */
object Pricing {
    private val table = mapOf(
        // Claude
        "claude-opus-5-5" to (4.0 to 20.0), "claude-sonnet-5-5" to (2.0 to 10.0), "claude-haiku-4-5" to (1.0 to 5.0),
        // OpenAI
        "gpt-6-astra" to (10.0 to 50.0), "gpt-6.1-sol" to (2.0 to 10.0), "gpt-6-sol" to (2.0 to 10.0), "gpt-6-luna" to (0.1 to 0.5),
        "gpt-5.6-sol" to (4.0 to 20.0), "gpt-5.6-terra" to (2.0 to 12.0), "gpt-5.6-luna" to (0.2 to 1.2), "gpt-5.5" to (5.0 to 30.0),
        "gpt-5.4" to (2.5 to 15.0), "gpt-5.4-mini" to (0.75 to 4.5), "gpt-5.4-nano" to (0.2 to 1.25), "gpt-5.2" to (1.75 to 14.0),
        "gpt-5.1" to (1.25 to 10.0), "gpt-5" to (1.25 to 10.0), "gpt-5-mini" to (0.25 to 2.0), "gpt-5-nano" to (0.05 to 0.4),
        "gpt-4.1" to (2.0 to 8.0), "gpt-4.1-mini" to (0.4 to 1.6), "gpt-4.1-nano" to (0.1 to 0.4),
        "gpt-4o" to (2.5 to 10.0), "gpt-4o-mini" to (0.15 to 0.6),
    )

    fun cost(model: String, input: Int, output: Int): Double? {
        val (inPrice, outPrice) = table[model] ?: return null
        return (input * inPrice + output * outPrice) / 1_000_000
    }

    /** 例如 “$0.0123”；很小的金额显示到小数点后 4 位 */
    fun format(dollars: Double): String =
        if (dollars >= 1) String.format(Locale.US, "$%.2f", dollars) else String.format(Locale.US, "$%.4f", dollars)
}
