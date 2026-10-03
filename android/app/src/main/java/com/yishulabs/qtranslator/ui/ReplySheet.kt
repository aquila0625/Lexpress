package com.yishulabs.qtranslator.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.EditNote
import androidx.compose.material.icons.rounded.Email
import androidx.compose.material.icons.rounded.Sms
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yishulabs.qtranslator.ai.AISettings
import com.yishulabs.qtranslator.ai.AITasks
import com.yishulabs.qtranslator.core.Prefs
import com.yishulabs.qtranslator.core.Speech
import com.yishulabs.qtranslator.core.isMostlyChinese
import kotlinx.coroutines.launch

/** AI 写回复：针对刚翻译的那段话，按要点写一条回复，或优化用户自己的草稿。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReplySheet(received: String, receivedTranslation: String, onDismiss: () -> Unit) {
    val colors = Lx.colors
    val scope = rememberCoroutineScope()
    val clipboard = LocalClipboardManager.current
    var kind by remember { mutableStateOf(AITasks.ReplyKind.MESSAGE) }
    var mode by remember { mutableStateOf(AITasks.ReplyMode.POINTS) }
    var input by remember { mutableStateOf("") }
    var reply by remember { mutableStateOf<AITasks.Reply?>(null) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var change by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf(false) }
    var showFull by remember { mutableStateOf(false) }
    var usedModel by remember { mutableStateOf("") }

    fun generate(changeRequest: String?) {
        val config = AISettings.currentConfig
        usedModel = "${config.provider.title} · ${config.model}"
        val previous = if (changeRequest == null) null else reply?.text
        working = true
        error = null
        copied = false
        scope.launch {
            try {
                reply = AITasks.reply(received, kind, mode, input.trim(), previous, changeRequest, config)
            } catch (e: Exception) {
                error = e.message
            } finally {
                working = false
            }
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("写回复", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = colors.ink)

            // 对方的话：太长时只显示几行，可以展开
            Column(
                Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                SectionHeader("对方的话")
                Text(received, fontSize = 15.sp, color = colors.ink, maxLines = if (showFull) Int.MAX_VALUE else 4,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                Text(receivedTranslation, fontSize = 13.sp, color = colors.ink3, maxLines = if (showFull) Int.MAX_VALUE else 3,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                if (received.length > 120 || receivedTranslation.length > 90) {
                    Text(if (showFull) "收起" else "展开全文", color = colors.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.clickable { showFull = !showFull }.padding(vertical = 8.dp))
                }
            }

            ChoiceBar("回复方式", listOf(Triple(AITasks.ReplyKind.MESSAGE, AITasks.ReplyKind.MESSAGE.title, Icons.Rounded.Sms),
                Triple(AITasks.ReplyKind.EMAIL, AITasks.ReplyKind.EMAIL.title, Icons.Rounded.Email)), kind, colors.accent, colors.accentSoft) { kind = it }
            ChoiceBar("怎么写", listOf(Triple(AITasks.ReplyMode.POINTS, AITasks.ReplyMode.POINTS.title, Icons.AutoMirrored.Rounded.FormatListBulleted),
                Triple(AITasks.ReplyMode.DRAFT, AITasks.ReplyMode.DRAFT.title, Icons.Rounded.EditNote)), mode, colors.ai, colors.aiSoft) { mode = it }

            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SectionHeader(if (mode == AITasks.ReplyMode.POINTS) "想说什么" else "我的草稿")
                Box(Modifier.fillMaxWidth().heightIn(min = 90.dp).background(colors.surface, RoundedCornerShape(14.dp)).padding(12.dp)) {
                    if (input.isEmpty()) {
                        Text(if (mode == AITasks.ReplyMode.POINTS) "例如：告诉他没问题，下周二下午我都有空" else "把你写好的回复贴在这里",
                            color = colors.ink3, fontSize = 15.sp)
                    }
                    BasicTextField(input, { input = it }, textStyle = TextStyle(fontSize = 15.sp, color = colors.ink),
                        cursorBrush = SolidColor(colors.accent), modifier = Modifier.fillMaxWidth())
                }
                if (mode == AITasks.ReplyMode.POINTS) Text("用中文写就行，回复会用对方的语言。", fontSize = 13.sp, color = colors.ink3)
            }

            Button(
                onClick = { generate(null) }, enabled = !working && input.isNotBlank(),
                modifier = Modifier.fillMaxWidth().height(50.dp), shape = RoundedCornerShape(25.dp),
            ) {
                if (working) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = colors.onAccent)
                else Icon(Icons.Rounded.AutoAwesome, null)
                Spacer(Modifier.width(8.dp))
                Text(if (reply == null) "生成回复" else "重新生成", fontWeight = FontWeight.Bold)
            }

            error?.let {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Warning, null, tint = colors.ai, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(it, fontSize = 13.sp, color = colors.ai)
                }
            }

            reply?.let { result ->
                SelectionContainer {
                    Text(result.text, fontSize = 18.sp, fontWeight = FontWeight.Medium, color = colors.ink, lineHeight = 26.sp,
                        modifier = Modifier.fillMaxWidth().background(colors.aiSoft, RoundedCornerShape(18.dp)).padding(14.dp))
                }
                result.usage?.takeIf { Prefs.showAIUsage }?.let { Text("$usedModel · ${it.summary}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.ai) }
                if (result.chinese.isNotEmpty()) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        SectionHeader("中文对照")
                        Text(result.chinese, fontSize = 15.sp, color = colors.ink2)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Pill(if (copied) "已复制" else "复制回复", if (copied) Icons.Rounded.Check else Icons.Rounded.ContentCopy,
                        colors.accent, colors.accentSoft, height = 40.dp, onClick = {
                            clipboard.setText(AnnotatedString(result.text))
                            copied = true
                        })
                    SpeakButton(Speech.text(result.text, result.text.isMostlyChinese))
                }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SectionHeader("再改一下")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("更短", "更正式", "更随意").forEach { option ->
                            Pill(option, Icons.Rounded.AutoAwesome, colors.ink2, colors.surface2, height = 40.dp,
                                onClick = { if (!working) generate(option) })
                        }
                    }
                    Row(
                        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(22.dp)).padding(start = 14.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f)) {
                            if (change.isEmpty()) Text("或者直接说：再问一下他几点方便", color = colors.ink3, fontSize = 15.sp)
                            BasicTextField(change, { change = it }, singleLine = true, textStyle = TextStyle(fontSize = 15.sp, color = colors.ink),
                                cursorBrush = SolidColor(colors.accent), modifier = Modifier.fillMaxWidth())
                        }
                        Box(
                            Modifier.size(36.dp).clip(CircleShape).background(if (change.isBlank()) colors.ink3.copy(alpha = 0.35f) else colors.accent)
                                .clickable(enabled = change.isNotBlank() && !working) {
                                    val text = change.trim()
                                    change = ""
                                    generate(text)
                                },
                            contentAlignment = Alignment.Center,
                        ) { Icon(Icons.Rounded.ArrowUpward, "按要求重新生成", tint = colors.onAccent, modifier = Modifier.size(18.dp)) }
                    }
                }
            }
        }
    }
}

/** 大一点的分段选择：选中项用颜色高亮，两组用不同颜色，一眼能分开 */
@Composable
private fun <T> ChoiceBar(
    title: String, options: List<Triple<T, String, ImageVector>>, selection: T, tint: Color, soft: Color, onSelect: (T) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SectionHeader(title)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            options.forEach { (value, label, icon) ->
                val on = value == selection
                Row(
                    Modifier.weight(1f).height(50.dp).clip(RoundedCornerShape(14.dp))
                        .background(if (on) soft else Lx.colors.ink3.copy(alpha = 0.08f))
                        .border(1.5.dp, if (on) tint else Color.Transparent, RoundedCornerShape(14.dp))
                        .clickable { onSelect(value) },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(icon, null, tint = if (on) tint else Lx.colors.ink3, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(label, color = if (on) tint else Lx.colors.ink3, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            }
        }
    }
}
