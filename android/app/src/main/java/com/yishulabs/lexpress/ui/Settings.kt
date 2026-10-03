package com.yishulabs.lexpress.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yishulabs.lexpress.ai.AIClient
import com.yishulabs.lexpress.ai.AIProvider
import com.yishulabs.lexpress.ai.AISettings
import com.yishulabs.lexpress.ai.Pricing
import com.yishulabs.lexpress.ai.UsageStore
import com.yishulabs.lexpress.core.OfflineTranslator
import com.yishulabs.lexpress.core.Prefs
import kotlinx.coroutines.launch
import java.util.Calendar

/** 设置：AI 服务商和 key、累计用量和报表、朗读、翻译来源。往下拉关闭。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(onDismiss: () -> Unit) {
    var showReport by remember { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Lx.colors.background,
    ) {
        BackHandler(enabled = showReport) { showReport = false }
        Column(Modifier.fillMaxHeight(0.92f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            if (showReport) UsageReport(onBack = { showReport = false }) else SettingsMain(onReport = { showReport = true })
        }
    }
}

@Composable
private fun SettingsMain(onReport: () -> Unit) {
    val colors = Lx.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var providerMenu by remember { mutableStateOf(false) }
    var modelMenu by remember { mutableStateOf(false) }
    var testing by remember { mutableStateOf(false) }
    var testResult by remember { mutableStateOf<String?>(null) }
    var offlineReady by remember { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(Unit) { offlineReady = OfflineTranslator.isReady() }

    Text("设置", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = colors.ink)
    Spacer(Modifier.height(16.dp))

    Group("AI 增强（可选）") {
        Box {
            SettingRow("服务商", value = AISettings.provider.title, onClick = { providerMenu = true })
            DropdownMenu(providerMenu, { providerMenu = false }) {
                AIProvider.entries.forEach { p ->
                    DropdownMenuItem(text = { Text(p.title) }, onClick = {
                        providerMenu = false
                        AISettings.updateProvider(p)
                        testResult = null
                    })
                }
            }
        }
        Divider()
        OutlinedTextField(
            AISettings.apiKey, { AISettings.updateApiKey(it) }, label = { Text("API Key") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth().padding(12.dp),
        )
        AISettings.provider.signupUrl?.let { url ->
            Text(
                "去 ${AISettings.provider.title} 注册并获取 API Key", color = colors.accent, fontSize = 15.sp,
                modifier = Modifier.fillMaxWidth().clickable { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }.padding(16.dp),
            )
            Divider()
        }
        if (AISettings.provider == AIProvider.CUSTOM) {
            OutlinedTextField(
                AISettings.baseUrl, { AISettings.updateBaseUrl(it) }, label = { Text("接口地址，例如 https://api.openai.com/v1") },
                singleLine = true, modifier = Modifier.fillMaxWidth().padding(12.dp),
            )
        }
        if (AISettings.provider.suggestedModels.isNotEmpty()) {
            Box {
                SettingRow("模型", value = AISettings.model.ifEmpty { "未选择" }, onClick = { modelMenu = true })
                DropdownMenu(modelMenu, { modelMenu = false }) {
                    AISettings.provider.modelGroups.forEach { (group, models) ->
                        Text(group, fontSize = 12.sp, color = colors.ink3, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                        models.forEach { m ->
                            DropdownMenuItem(text = { Text(m) }, onClick = {
                                modelMenu = false
                                AISettings.updateModel(m)
                            })
                        }
                    }
                }
            }
            Divider()
        }
        OutlinedTextField(
            AISettings.model, { AISettings.updateModel(it) }, label = { Text("或手动填写模型名称") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(12.dp),
        )
        SettingRow("AI 优化：新会话默认开启") { Switch(AISettings.autoCalibrate, { AISettings.updateAutoCalibrate(it) }) }
        Divider()
        SettingRow("测试连接", value = testResult, enabled = !testing && AISettings.isConfigured, onClick = {
            testing = true
            testResult = null
            scope.launch {
                testResult = try {
                    AIClient.complete("This is a connectivity check from an app's settings screen. Reply with the single word OK.", "ping", AISettings.currentConfig)
                    "连接正常"
                } catch (e: Exception) {
                    e.message
                }
                testing = false
            }
        }) { if (testing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp) }
        Divider()
        val summary = UsageStore.summarize(UsageStore.records(AISettings.provider))
        SettingRow(
            "${AISettings.provider.title} 累计用量",
            value = "${summary.total} tokens",
            subtitle = when {
                summary.total == 0 -> "还没有用过"
                summary.cost > 0 -> "约 ${Pricing.format(summary.cost)}（按标价估算）"
                else -> "无价格数据"
            },
        )
        Divider()
        SettingRow("用量报表", onClick = onReport) { Icon(Icons.Rounded.ChevronRight, null, tint = colors.ink3) }
    }
    Footnote(
        "Lexpress 不提供 AI 额度，也不经过任何中间服务器：你自己在服务商那里注册，把 API Key 填在这里，费用由服务商向你收取。" +
            "Key 只加密保存在本机。注意 ChatGPT 的会员订阅不包含 API 额度，API Key 要在 OpenAI 开发者平台单独申请。" +
            "不填也能使用词典、翻译、朗读和图片翻译。每次 AI 优化后会显示消耗的 token 数。"
    )

    Group("朗读") {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("默认英文口音", modifier = Modifier.weight(1f), color = colors.ink)
            SingleChoiceSegmentedButtonRow {
                listOf(1 to "英式", 2 to "美式").forEachIndexed { index, (value, label) ->
                    SegmentedButton(Prefs.accent == value, { Prefs.updateAccent(value) }, SegmentedButtonDefaults.itemShape(index, 2)) { Text(label) }
                }
            }
        }
        Divider()
        SettingRow("查词后自动朗读") { Switch(Prefs.autoSpeak, { Prefs.updateAutoSpeak(it) }) }
    }

    Group("翻译来源") {
        SettingRow("单词", value = "有道词典（在线）")
        Divider()
        SettingRow(
            "句子和段落", value = "本机离线翻译，其次 MyMemory",
            subtitle = when (offlineReady) {
                true -> "离线模型已下载"
                false -> "离线模型还没下载，翻译时会提示下载（约 30 MB）"
                null -> null
            },
        )
        Divider()
        SettingRow("图片文字", value = "本机识别，不上传")
    }
    Footnote("先用离线和免费的来源，AI 只在你填了 Key 之后作为补充。")

    Group("关于") {
        SettingRow("版本", value = "0.2.0")
        Divider()
        SettingRow("源代码（MIT 许可）", onClick = {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/aquila0625/Lexpress")))
        }) { Icon(Icons.Rounded.ChevronRight, null, tint = colors.ink3) }
    }
}

/** 用量报表：按天统计，可以看最近一周或本月，可以按服务商筛选 */
@Composable
private fun UsageReport(onBack: () -> Unit) {
    val colors = Lx.colors
    var month by remember { mutableStateOf(false) }
    var provider by remember { mutableStateOf<AIProvider?>(AISettings.provider) }
    var providerMenu by remember { mutableStateOf(false) }

    val days: List<Long> = remember(month) {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        if (month) {
            val count = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
            cal.set(Calendar.DAY_OF_MONTH, 1)
            List(count) { (cal.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, it) }.timeInMillis }
        } else {
            List(7) { (cal.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, it - 6) }.timeInMillis }
        }
    }
    val dayMs = 24 * 3600 * 1000L
    val records = UsageStore.records(provider).filter { it.date >= days.first() && it.date < days.last() + dayMs }
    val totals = days.map { start -> records.filter { it.date >= start && it.date < start + dayMs }.sumOf { it.total } }
    val summary = UsageStore.summarize(records)

    Row(verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回设置", tint = colors.accent) }
        Text("用量报表", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = colors.ink)
    }
    Spacer(Modifier.height(12.dp))
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        SegmentedButton(!month, { month = false }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("周") }
        SegmentedButton(month, { month = true }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("月") }
    }
    Spacer(Modifier.height(12.dp))
    Group(if (month) "本月" else "最近 7 天") {
        Box {
            SettingRow("服务商", value = provider?.title ?: "全部", onClick = { providerMenu = true }) {
                Icon(Icons.Rounded.ExpandMore, null, tint = colors.ink3)
            }
            DropdownMenu(providerMenu, { providerMenu = false }) {
                DropdownMenuItem(text = { Text("全部") }, onClick = { provider = null; providerMenu = false })
                AIProvider.entries.forEach { p -> DropdownMenuItem(text = { Text(p.title) }, onClick = { provider = p; providerMenu = false }) }
            }
        }
        Divider()
        SettingRow("token 合计", value = summary.total.toString())
        Divider()
        SettingRow("输入 / 输出", value = "${summary.input} / ${summary.output}")
        Divider()
        SettingRow("估算费用", value = when {
            summary.total == 0 -> "—"
            summary.cost == 0.0 && summary.hasUnpriced -> "无价格数据"
            else -> "约 " + Pricing.format(summary.cost) + if (summary.hasUnpriced) "（部分无价格）" else ""
        })
        // 柱状图
        val top = (totals.maxOrNull() ?: 0).coerceAtLeast(1)
        Row(
            Modifier.fillMaxWidth().height(170.dp).padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(if (month) 2.dp else 8.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            totals.forEach { value ->
                Box(
                    Modifier.weight(1f).fillMaxHeight(maxOf(0.015f, value.toFloat() / top))
                        .background(colors.accent.copy(alpha = if (value > 0) 1f else 0.25f), RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp)),
                )
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(if (month) 2.dp else 8.dp)) {
            days.forEach { start ->
                val cal = Calendar.getInstance().apply { timeInMillis = start }
                val label = if (month) {
                    val d = cal.get(Calendar.DAY_OF_MONTH)
                    if (d == 1 || d % 5 == 0) d.toString() else ""
                } else {
                    "日一二三四五六"[cal.get(Calendar.DAY_OF_WEEK) - 1].toString()
                }
                Text(label, fontSize = 11.sp, color = colors.ink3, modifier = Modifier.weight(1f), maxLines = 1,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
    }
    val byModel = records.groupBy { it.model }.map { (model, list) -> model to UsageStore.summarize(list) }.sortedByDescending { it.second.total }
    if (byModel.isNotEmpty()) {
        Group("按模型") {
            byModel.forEachIndexed { index, (model, s) ->
                if (index > 0) Divider()
                SettingRow(model, value = "${s.total} tokens", subtitle = if (s.cost > 0) "约 " + Pricing.format(s.cost) else "无价格数据")
            }
        }
    }
    Footnote("费用按服务商公开的标价估算，实际以服务商账单为准。DeepSeek 和自定义接口没有价格数据，只统计 token。")
}

@Composable
fun Group(title: String?, content: @Composable () -> Unit) {
    Column(Modifier.padding(top = 10.dp)) {
        if (title != null) SectionHeader(title, Modifier.padding(start = 16.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Lx.colors.surface)) { content() }
    }
}

@Composable
fun SettingRow(
    title: String,
    value: String? = null,
    subtitle: String? = null,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val colors = Lx.colors
    Row(
        Modifier.fillMaxWidth()
            .let { if (onClick != null && enabled) it.clickable(onClick = onClick) else it }
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, color = if (enabled || onClick == null) colors.ink else colors.ink3, fontSize = 16.sp)
            subtitle?.let { Text(it, color = colors.ink3, fontSize = 12.sp) }
        }
        value?.let {
            Spacer(Modifier.width(8.dp))
            Text(it, color = if (onClick != null) colors.accent else colors.ink3, fontSize = 15.sp, maxLines = 2)
        }
        trailing?.let {
            Spacer(Modifier.width(8.dp))
            it()
        }
    }
}

@Composable
private fun Divider() = HorizontalDivider(Modifier.padding(start = 16.dp), color = Lx.colors.line)

@Composable
fun Footnote(text: String) {
    Text(text, fontSize = 13.sp, color = Lx.colors.ink3, modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp))
}
