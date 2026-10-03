package com.yishulabs.qtranslator.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Reply
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.ContentCopy
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.MenuBook
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material.icons.rounded.SwapVert
import androidx.compose.material.icons.rounded.Warning
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yishulabs.qtranslator.ai.AISettings
import com.yishulabs.qtranslator.conversation.ConversationController
import com.yishulabs.qtranslator.conversation.HistoryStore
import com.yishulabs.qtranslator.conversation.Turn
import com.yishulabs.qtranslator.conversation.TurnImage
import com.yishulabs.qtranslator.conversation.TurnState
import com.yishulabs.qtranslator.core.OnlineTranslator
import com.yishulabs.qtranslator.core.SentenceResult
import com.yishulabs.qtranslator.core.Speaker
import com.yishulabs.qtranslator.core.Speech
import com.yishulabs.qtranslator.core.WordEntry
import com.yishulabs.qtranslator.core.isMostlyChinese

/** 会话里的一轮：右侧是原文（文字或图片），下面是结果。 */
@Composable
fun TurnItem(
    turn: Turn,
    controller: ConversationController,
    expanded: Boolean,
    onToggleExpand: () -> Unit,
    editing: Boolean,
    onEditingChange: (Boolean) -> Unit,
    onOpenWord: (WordEntry) -> Unit,
    onReply: (SentenceResult) -> Unit,
    onOpenImage: (String) -> Unit,
    onNeedAI: () -> Unit,
) {
    val colors = Lx.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        when {
            turn.isImage -> ImageSource(turn, controller, onOpenImage)
            editing -> SourceEditor(turn, controller, onDone = { onEditingChange(false) })
            else -> TextSource(turn, controller, expanded, onToggleExpand, onEdit = { onEditingChange(true) })
        }
        val direction = if (turn.sourceIsChinese) "中 → 英" else "英 → 中"
        val caption = listOfNotNull(
            if (turn.isImage) "图片" else direction,
            if (turn.manualDirection) "手动" else "自动",
            if (turn.edited) "已编辑" else null,
        ).joinToString(" · ")
        Text(caption, fontSize = 12.sp, color = colors.ink3, modifier = Modifier.align(Alignment.End))
        Box(Modifier.fillMaxWidth().let { if (editing) it.background(Color.Transparent) else it }) {
            Column(Modifier.fillMaxWidth()) {
                when {
                    turn.state == TurnState.WORKING && !turn.isImage -> Working("翻译中…")
                    turn.state == TurnState.FAILED -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.Warning, null, tint = colors.ink3, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(turn.errorMessage ?: "翻译失败", fontSize = 13.sp, color = colors.ink3)
                        TextButton(onClick = { controller.retry(turn.id) }) { Text("重试") }
                    }
                    turn.isImage -> ImageResults(turn, expanded, onToggleExpand)
                    turn.word != null -> WordCard(turn.word) { onOpenWord(turn.word) }
                    turn.sentence != null -> SentenceBlock(turn, turn.sentence, controller, expanded, onToggleExpand, onReply, onNeedAI)
                }
            }
        }
    }
}

@Composable
private fun Working(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(8.dp))
        Text(text, fontSize = 13.sp, color = Lx.colors.ink3)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TextSource(
    turn: Turn, controller: ConversationController, expanded: Boolean, onToggleExpand: () -> Unit, onEdit: () -> Unit,
) {
    val colors = Lx.colors
    val clipboard = LocalClipboardManager.current
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().padding(start = 40.dp), contentAlignment = Alignment.CenterEnd) {
        Box {
            Box(
                Modifier
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp, bottomStart = 20.dp, bottomEnd = 6.dp))
                    .background(colors.accentSoft)
                    .combinedClickable(onClick = {}, onLongClick = { menu = true })
                    .padding(horizontal = 14.dp, vertical = 10.dp),
            ) {
                FoldableText(turn.source, TextStyle(fontSize = 16.sp), expanded, onToggleExpand, alignEnd = true)
            }
            // 长按原文：编辑、复制、朗读、删除这一轮
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("编辑原文") }, leadingIcon = { Icon(Icons.Rounded.Edit, null) }, onClick = { menu = false; onEdit() })
                DropdownMenuItem(text = { Text("复制原文") }, leadingIcon = { Icon(Icons.Rounded.ContentCopy, null) }, onClick = {
                    menu = false
                    clipboard.setText(AnnotatedString(turn.source))
                })
                DropdownMenuItem(text = { Text("朗读原文") }, leadingIcon = { Icon(Icons.AutoMirrored.Rounded.VolumeUp, null) }, onClick = {
                    menu = false
                    Speaker.toggle(Speech.text(turn.source, turn.sourceIsChinese))
                })
                DropdownMenuItem(text = { Text("删除这一轮", color = Color(0xFFE5372B)) }, leadingIcon = { Icon(Icons.Rounded.Delete, null, tint = Color(0xFFE5372B)) }, onClick = {
                    menu = false
                    controller.deleteTurn(turn.id)
                })
            }
        }
    }
}

@Composable
private fun SourceEditor(turn: Turn, controller: ConversationController, onDone: () -> Unit) {
    var text by remember { mutableStateOf(turn.source) }
    Column(
        Modifier.fillMaxWidth().border(2.dp, Lx.colors.accent, RoundedCornerShape(18.dp)).padding(12.dp),
        horizontalAlignment = Alignment.End,
    ) {
        OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth(), maxLines = 12, label = { Text("原文") })
        Spacer(Modifier.height(8.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onDone) { Text("取消") }
            Button(onClick = {
                controller.editSource(turn.id, text)
                onDone()
            }, enabled = text.isNotBlank()) { Text("保存并重新翻译") }
        }
    }
}

@Composable
private fun ImageSource(turn: Turn, controller: ConversationController, onOpenImage: (String) -> Unit) {
    val colors = Lx.colors
    Column(
        Modifier.fillMaxWidth().padding(start = 24.dp).clip(RoundedCornerShape(20.dp)).background(colors.accentSoft).padding(10.dp),
        horizontalAlignment = Alignment.End,
    ) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(top = 8.dp, end = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            turn.images.forEachIndexed { index, item -> Thumbnail(turn, item, index, controller, onOpenImage) }
        }
        Spacer(Modifier.height(6.dp))
        Text(
            "${turn.images.size} 张图片" + if (turn.state == TurnState.WORKING) " · 识别中" else " · 已识别",
            fontSize = 13.sp, color = colors.ink2,
        )
    }
}

@Composable
private fun Thumbnail(turn: Turn, item: TurnImage, index: Int, controller: ConversationController, onOpenImage: (String) -> Unit) {
    val bitmap = remember(item.fileName, item.done) { controller.store.thumbnail(item.fileName) }
    Box {
        Box(Modifier.size(88.dp, 112.dp).clip(RoundedCornerShape(12.dp)).background(Color(0xFF2B2F33)).clickable { onOpenImage(item.id) }) {
            if (bitmap != null) {
                Image(bitmap.asImageBitmap(), "图 ${index + 1}，点按编辑", contentScale = ContentScale.Crop, modifier = Modifier.size(88.dp, 112.dp))
            }
            Text(
                "图 ${index + 1}", color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.BottomStart).padding(6.dp)
                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 1.dp),
            )
        }
        Icon(
            Icons.Rounded.Cancel, "删除图 ${index + 1} 和它的译文", tint = Color.Black.copy(alpha = 0.75f),
            modifier = Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-10).dp).size(26.dp)
                .clip(CircleShape).background(Color.White).clickable { controller.deleteImage(turn.id, item.id) },
        )
    }
}

@Composable
private fun ImageResults(turn: Turn, expanded: Boolean, onToggleExpand: () -> Unit) {
    val colors = Lx.colors
    val clipboard = LocalClipboardManager.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Pill("本机识别 · 翻译", Icons.Rounded.Check, colors.accent, colors.accentSoft)
        turn.images.forEachIndexed { index, item ->
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                HorizontalDivider(color = colors.line)
                Text("图 ${index + 1}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = colors.ink3)
                if (item.done) {
                    FoldableText(item.translation, TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Medium), expanded, onToggleExpand)
                } else {
                    Working("识别和翻译中…")
                }
            }
        }
        if (turn.state == TurnState.DONE) {
            val all = turn.images.joinToString("\n\n") { it.translation }
            Row(Modifier.offset(x = (-12).dp)) {
                SpeakButton(Speech.text(all, !(turn.images.firstOrNull()?.recognized?.isMostlyChinese ?: false)))
                IconButton(onClick = { clipboard.setText(AnnotatedString(all)) }) { Icon(Icons.Rounded.ContentCopy, "复制全部译文", tint = colors.ink2) }
            }
        }
    }
}

@Composable
private fun SentenceBlock(
    turn: Turn,
    sentence: SentenceResult,
    controller: ConversationController,
    expanded: Boolean,
    onToggleExpand: () -> Unit,
    onReply: (SentenceResult) -> Unit,
    onNeedAI: () -> Unit,
) {
    val colors = Lx.colors
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    var showBefore by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill(sentence.engine, Icons.Rounded.Check, colors.accent, colors.accentSoft)
            // 点一下用 AI 优化，再点一下关掉；之前优化过的结果会保留，打开时不用重新请求
            Pill(
                "AI 优化", Icons.Rounded.AutoAwesome,
                if (sentence.showsAI) colors.ai else colors.ink3,
                if (sentence.showsAI) colors.aiSoft else colors.ink3.copy(alpha = 0.12f),
                onClick = {
                    if (turn.isOptimizing) return@Pill
                    if (AISettings.isConfigured || sentence.aiTranslation != null) controller.toggleAI(turn.id) else onNeedAI()
                },
            )
            if (sentence.showsAI && !turn.isOptimizing) {
                IconButton(onClick = { if (AISettings.isConfigured) controller.reoptimize(turn.id) else onNeedAI() }, modifier = Modifier.size(36.dp)) {
                    Icon(Icons.Rounded.Refresh, "重新用 AI 优化", tint = colors.ai, modifier = Modifier.size(18.dp))
                }
            }
            if (turn.isOptimizing) Working("AI 优化中…")
        }
        FoldableText(sentence.displayed, TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Medium, lineHeight = 28.sp), expanded, onToggleExpand)
        if (sentence.showsAI) {
            if (sentence.aiTranslation != sentence.translation) {
                // 优化前的译文默认折叠
                Row(
                    Modifier.clip(RoundedCornerShape(8.dp)).clickable { showBefore = !showBefore }.defaultMinSize(minHeight = 36.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(if (showBefore) Icons.Rounded.ExpandLess else Icons.Rounded.ChevronRight, null, tint = colors.ink3, modifier = Modifier.size(18.dp))
                    Text(if (showBefore) "收起优化前" else "查看优化前的译文", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.ink3)
                }
                if (showBefore) {
                    Text(
                        sentence.translation, fontSize = 13.sp, color = colors.ink2,
                        modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(12.dp)).padding(10.dp),
                    )
                }
            } else {
                Text("AI 认为原译文无需修改", fontSize = 13.sp, color = colors.ink3)
            }
            Text(
                listOfNotNull(sentence.aiModel, sentence.aiUsage?.summary).joinToString(" · "),
                fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.ai,
            )
        }
        turn.aiError?.let { error ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.Warning, null, tint = colors.ai, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(error, fontSize = 13.sp, color = colors.ai)
            }
        }
        Row(Modifier.offset(x = (-12).dp)) {
            SpeakButton(Speech.text(sentence.displayed, !sentence.sourceIsChinese))
            IconButton(onClick = {
                clipboard.setText(AnnotatedString(sentence.displayed))
                copied = true
            }) { Icon(if (copied) Icons.Rounded.Check else Icons.Rounded.ContentCopy, "复制译文", tint = colors.ink2) }
            IconButton(onClick = { controller.swap(turn) }) { Icon(Icons.Rounded.SwapVert, "对调：把译文反向再翻译一次", tint = colors.ink2) }
            IconButton(onClick = { if (AISettings.isConfigured) onReply(sentence) else onNeedAI() }) {
                Icon(Icons.AutoMirrored.Rounded.Reply, "AI 写回复", tint = colors.ai)
            }
        }
        if (controller.offlineDownloadable && sentence.engine == OnlineTranslator.NAME) {
            TextButton(onClick = { controller.downloadOfflineModel() }) {
                Text("下载本机离线翻译模型（约 30 MB，之后更快、不限量、无需联网）", fontSize = 13.sp)
            }
        }
        if (sentence.suggestions.isNotEmpty()) {
            Text("你是不是要找：" + sentence.suggestions.take(3).joinToString("、") { it.word }, fontSize = 13.sp, color = colors.ink3)
        }
    }
}

/** 会话里的词典卡片：词头、发音、前几条释义，点按看完整词条 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun WordCard(entry: WordEntry, onOpen: () -> Unit) {
    val colors = Lx.colors
    val starred = HistoryStore.isStarred(entry.word)
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(colors.surface).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Text(
                entry.word, modifier = Modifier.weight(1f), color = colors.ink,
                style = if (entry.isChinese) TextStyle(fontSize = 26.sp, fontWeight = FontWeight.SemiBold)
                else TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Serif),
            )
            IconButton(onClick = { HistoryStore.toggleStar(entry.word, entry.summary) }) {
                Icon(
                    if (starred) Icons.Rounded.Star else Icons.Rounded.StarBorder, if (starred) "从生词本移除" else "加入生词本",
                    tint = if (starred) Color(0xFFF5A623) else colors.ink3,
                )
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Pronunciations(entry)
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (entry.senses.isEmpty()) {
                entry.definitions.take(3).forEach { d ->
                    Text(d.text + (d.note?.let { "  $it" } ?: ""), fontSize = 15.sp, color = colors.ink, maxLines = 3)
                }
            } else {
                entry.senses.take(4).forEach { sense ->
                    Row {
                        sense.pos?.let {
                            Text(it, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, fontStyle = FontStyle.Italic, fontFamily = FontFamily.Serif, color = colors.accent)
                            Spacer(Modifier.width(6.dp))
                        }
                        Text(sense.meaning, fontSize = 15.sp, color = colors.ink)
                    }
                }
            }
        }
        Row(
            Modifier.clip(RoundedCornerShape(10.dp)).clickable(onClick = onOpen).defaultMinSize(minHeight = 44.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Rounded.MenuBook, null, tint = colors.accent, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("完整词条：例句、搭配、辨析", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
        }
    }
}

@Composable
fun Pronunciations(entry: WordEntry) {
    when {
        entry.isChinese -> PronunciationPill("中", entry.pinyin ?: "朗读", Speech.chinese(entry.word))
        entry.phonetics.isEmpty() -> PronunciationPill("美", "朗读", Speech.english(entry.word, 2))
        else -> entry.phonetics.forEach { p -> PronunciationPill(p.label, "/${p.ipa}/", Speech.english(entry.word, p.accent)) }
    }
}
