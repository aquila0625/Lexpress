package com.yishulabs.lexpress.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ExpandLess
import androidx.compose.material.icons.rounded.ExpandMore
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material.icons.rounded.StarBorder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yishulabs.lexpress.conversation.HistoryStore
import com.yishulabs.lexpress.core.ExamplePair
import com.yishulabs.lexpress.core.Speech
import com.yishulabs.lexpress.core.WordEntry
import com.yishulabs.lexpress.core.Youdao
import com.yishulabs.lexpress.core.isMostlyChinese

/** 完整词条弹窗：往下拉就关掉。点词组、同根词时在弹窗里继续往下查，不发到会话里。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WordSheet(word: String, entry: WordEntry?, translate: suspend (String) -> String?, onDismiss: () -> Unit) {
    val path = remember { mutableStateListOf<String>() }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Lx.colors.background,
    ) {
        BackHandler(enabled = path.isNotEmpty()) { path.removeAt(path.lastIndex) }
        val current = path.lastOrNull()
        Column(Modifier.fillMaxHeight(0.92f)) {
            if (current != null) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { path.removeAt(path.lastIndex) }) {
                        Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回", tint = Lx.colors.accent)
                    }
                    Text(current, fontWeight = FontWeight.SemiBold, color = Lx.colors.ink, maxLines = 1)
                }
            }
            key(current) {
                WordPage(current ?: word, if (current == null) entry else null, translate) { path.add(it) }
            }
        }
    }
}

/** 一页词条。词典里没有时显示整句翻译。 */
@Composable
private fun WordPage(word: String, entry: WordEntry?, translate: suspend (String) -> String?, onLookup: (String) -> Unit) {
    var loaded by remember { mutableStateOf(entry) }
    var translation by remember { mutableStateOf<String?>(null) }
    var finished by remember { mutableStateOf(entry != null) }
    LaunchedEffect(word) {
        if (loaded != null) return@LaunchedEffect
        loaded = runCatching { Youdao.lookup(word).entry }.getOrNull()
        if (loaded == null) translation = translate(word)
        finished = true
    }
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 32.dp)) {
        val current = loaded
        when {
            current != null -> WordDetail(current, onLookup)
            translation != null -> {
                Text(word, fontSize = 28.sp, fontFamily = FontFamily.Serif, color = Lx.colors.ink)
                Spacer(Modifier.height(12.dp))
                SelectionContainer { Text(translation!!, fontSize = 20.sp, fontWeight = FontWeight.Medium, color = Lx.colors.ink) }
                Row { SpeakButton(Speech.text(word, word.isMostlyChinese)) }
            }
            finished -> Text("查不到“$word”，请检查网络后重试", color = Lx.colors.ink3, modifier = Modifier.padding(top = 60.dp))
            else -> Box(Modifier.fillMaxWidth().padding(top = 80.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WordDetail(entry: WordEntry, onLookup: (String) -> Unit) {
    val colors = Lx.colors
    var showAllSenses by remember { mutableStateOf(false) }
    val starred = HistoryStore.isStarred(entry.word)
    Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
        // 词头
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.Top) {
                SelectionContainer(Modifier.weight(1f)) {
                    Text(
                        entry.word, color = colors.ink, modifier = Modifier.fillMaxWidth(),
                        fontSize = if (entry.isChinese) 36.sp else 40.sp,
                        fontWeight = if (entry.isChinese) FontWeight.SemiBold else FontWeight.Medium,
                        fontFamily = if (entry.isChinese) FontFamily.Default else FontFamily.Serif,
                    )
                }
                IconButton(onClick = { HistoryStore.toggleStar(entry.word, entry.summary) }) {
                    Icon(if (starred) Icons.Rounded.Star else Icons.Rounded.StarBorder, if (starred) "从生词本移除" else "加入生词本",
                        tint = if (starred) Color(0xFFF5A623) else colors.ink3)
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { Pronunciations(entry) }
            if (entry.forms.isNotEmpty()) Text(entry.forms.joinToString(" · "), fontSize = 13.sp, color = colors.ink3)
            if (entry.tags.isNotEmpty()) Text(entry.tags.joinToString(" · "), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.ink3)
        }

        if (entry.definitions.isNotEmpty()) {
            if (entry.isChinese) {
                Block("英文说法") {
                    entry.definitions.forEach { d ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(d.text, fontSize = 21.sp, fontFamily = FontFamily.Serif, color = colors.accent, modifier = Modifier.clickable { onLookup(d.text) })
                                d.note?.let { Text(it, fontSize = 14.sp, color = colors.ink3, maxLines = 2) }
                            }
                            SpeakButton(Speech.english(d.text))
                        }
                        HorizontalDivider(color = colors.line)
                    }
                }
            } else {
                // 按词性汇总，一眼看完全部意思
                SelectionContainer {
                    Column(
                        Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) { entry.definitions.forEach { Text(it.text, fontSize = 15.sp, color = colors.ink) } }
                }
            }
        }

        if (entry.senses.isNotEmpty()) {
            Block("逐条释义", trailing = "常用的在前") {
                val shown = if (showAllSenses) entry.senses else entry.senses.take(8)
                shown.forEachIndexed { index, sense ->
                    Row(Modifier.padding(vertical = 6.dp)) {
                        Text("${index + 1}", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = colors.ink3, modifier = Modifier.width(22.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                sense.pos?.let {
                                    Text(it, fontSize = 13.sp, fontStyle = FontStyle.Italic, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = colors.accent)
                                    Spacer(Modifier.width(6.dp))
                                }
                                if (sense.isCommon) {
                                    Text("常用", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = colors.ai,
                                        modifier = Modifier.background(colors.aiSoft, RoundedCornerShape(5.dp)).padding(horizontal = 5.dp))
                                    Spacer(Modifier.width(6.dp))
                                }
                            }
                            Text(sense.meaning, fontSize = 16.sp, color = colors.ink)
                            sense.examples.forEach { ExampleRow(it) }
                        }
                    }
                }
                if (entry.senses.size > 8) {
                    TextButton(onClick = { showAllSenses = !showAllSenses }) {
                        Text(if (showAllSenses) "收起" else "显示全部 ${entry.senses.size} 条释义")
                    }
                }
            }
        }

        if (entry.webMeanings.isNotEmpty() && entry.senses.isEmpty()) {
            Block("网络释义") { Text(entry.webMeanings.joinToString("；"), color = colors.ink) }
        }

        if (entry.phrases.isNotEmpty()) {
            Block("常用搭配") { entry.phrases.forEach { PhraseRow(it.key, it.value) { onLookup(it.key) } } }
        }
        if (entry.examples.isNotEmpty()) {
            Block("例句") { entry.examples.forEach { ExampleRow(it) } }
        }
        if (entry.related.isNotEmpty()) {
            Block("同根词") { entry.related.forEach { PhraseRow(it.word, "${it.pos} ${it.meaning}") { onLookup(it.word) } } }
        }
        if (entry.distinctions.isNotEmpty()) {
            Disclosure("近义词辨析") {
                entry.distinctions.forEach { group ->
                    Text(group.title, fontWeight = FontWeight.SemiBold, color = colors.ink)
                    group.usages.forEach { usage ->
                        Text(buildAnnotatedString {
                            withStyle(SpanStyle(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, color = colors.ink)) { append(usage.key) }
                            withStyle(SpanStyle(color = colors.ink2)) { append("　" + usage.value) }
                        }, fontSize = 15.sp)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
        if (entry.collins.isNotEmpty()) {
            Disclosure("英文解释（柯林斯）") {
                entry.collins.forEachIndexed { index, sense ->
                    sense.pos?.let { Text("${index + 1}. $it", fontSize = 12.sp, color = colors.ink3) }
                    Text(rich(sense.explanation, colors.ink), fontSize = 15.sp)
                    sense.examples.take(1).forEach { ExampleRow(it) }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
        entry.etymology?.let { etymology ->
            Disclosure("词源") { Text(etymology, fontSize = 15.sp, color = colors.ink2) }
        }
        Text("词典数据：有道词典", fontSize = 11.sp, color = colors.ink3)
    }
}

@Composable
private fun Block(title: String, trailing: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row {
            SectionHeader(title, Modifier.weight(1f))
            trailing?.let { Text(it, fontSize = 12.sp, color = Lx.colors.ink3) }
        }
        content()
    }
}

@Composable
private fun Disclosure(title: String, content: @Composable () -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).clickable { open = !open }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(title, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = Lx.colors.ink, modifier = Modifier.weight(1f))
            Icon(if (open) Icons.Rounded.ExpandLess else Icons.Rounded.ExpandMore, null, tint = Lx.colors.ink3)
        }
        if (open) Column(verticalArrangement = Arrangement.spacedBy(4.dp)) { content() }
    }
}

/** 蓝色可点的搭配：点了在弹窗里查它 */
@Composable
private fun PhraseRow(key: String, value: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp)) {
        Text(key, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Lx.colors.accent)
        Text(value, fontSize = 14.sp, color = Lx.colors.ink2)
    }
    HorizontalDivider(color = Lx.colors.line)
}

@Composable
private fun ExampleRow(example: ExamplePair) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(rich(example.source, Lx.colors.ink), fontSize = 15.sp)
            if (example.translation.isNotEmpty()) Text(example.translation, fontSize = 13.sp, color = Lx.colors.ink3)
        }
        Box(Modifier.size(40.dp)) { SpeakButton(Speech.english(example.english)) }
    }
}

/** 把词典里的 <b> 高亮转成粗体 */
private fun rich(text: String, color: Color) = buildAnnotatedString {
    val parts = text.split(Regex("(?=<b>)|(?<=</b>)"))
    for (part in parts) {
        if (part.startsWith("<b>")) {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = color)) { append(part.removePrefix("<b>").removeSuffix("</b>").replace(Regex("<[^>]+>"), "")) }
        } else {
            withStyle(SpanStyle(color = color)) { append(part.replace(Regex("<[^>]+>"), "")) }
        }
    }
}
