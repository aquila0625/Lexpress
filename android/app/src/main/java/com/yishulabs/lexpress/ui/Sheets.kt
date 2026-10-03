package com.yishulabs.lexpress.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Rotate90DegreesCw
import androidx.compose.material.icons.rounded.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.yishulabs.lexpress.ai.AISettings
import com.yishulabs.lexpress.conversation.ConversationController
import com.yishulabs.lexpress.conversation.HistoryStore
import com.yishulabs.lexpress.conversation.SceneCover

private val Danger = Color(0xFFE5372B)

/** 新建会话：名称、所在场景、是否开启 AI 优化 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewSessionSheet(controller: ConversationController, onDismiss: () -> Unit, onNewScene: () -> Unit) {
    val colors = Lx.colors
    val store = controller.store
    var name by remember { mutableStateOf("") }
    var sceneId by remember { mutableStateOf<String?>(null) }
    var aiEnabled by remember { mutableStateOf(AISettings.autoCalibrate) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp)) {
            Text("新建会话", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.ink, modifier = Modifier.align(Alignment.CenterHorizontally))
            Spacer(Modifier.height(12.dp))
            OutlinedTextField(name, { name = it }, label = { Text("名称") }, placeholder = { Text("例如：和老师约时间") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Footnote("不填也可以，会用第一句话当名称，之后随时能改。")
            Group("场景") {
                SceneChoice(null, "不放进场景", sceneId == null) { sceneId = null }
                store.scenes.forEach { scene ->
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.line)
                    SceneChoice(scene.cover, scene.name, sceneId == scene.id) { sceneId = scene.id }
                }
                HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.line)
                SettingRow("新建场景…", onClick = onNewScene)
            }
            Group(null) {
                SettingRow("这个会话开启 AI 优化") { Switch(aiEnabled, { aiEnabled = it }) }
            }
            Footnote("开启后每次翻译句子都会用 AI 优化译文，需要先在设置里填写 API Key。")
            Spacer(Modifier.height(12.dp))
            Button(onClick = {
                controller.select(store.createSession(name, sceneId, aiEnabled).id)
                onDismiss()
            }, modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(26.dp)) {
                Text("创建", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
        }
    }
}

@Composable
private fun SceneChoice(cover: SceneCover?, name: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        SceneCoverView(cover, 32.dp)
        Spacer(Modifier.width(12.dp))
        Text(name, modifier = Modifier.weight(1f), color = Lx.colors.ink, fontSize = 16.sp)
        RadioButton(selected, onClick)
    }
}

/** 新建或编辑场景：名称和封面（图标 + 配色）；编辑时可以删除 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SceneEditorSheet(controller: ConversationController, sceneId: String?, onDismiss: () -> Unit) {
    val colors = Lx.colors
    val store = controller.store
    val existing = store.scene(sceneId)
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var symbol by remember { mutableStateOf(existing?.cover?.symbol ?: SceneCover.symbols.first()) }
    var palette by remember { mutableStateOf(existing?.cover?.palette ?: 0) }
    var deleting by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(if (existing == null) "新建场景" else "编辑场景", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.ink, modifier = Modifier.align(Alignment.CenterHorizontally))
            OutlinedTextField(name, { name = it }, label = { Text("场景名称") }, placeholder = { Text("例如：教室、户外交流、租房") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            SectionHeader("封面")
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { SceneCoverView(SceneCover(symbol, palette), 72.dp) }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SceneCover.symbols.forEach { item ->
                    Box(
                        Modifier.size(48.dp).clip(RoundedCornerShape(12.dp)).background(if (item == symbol) colors.accentSoft else colors.surface)
                            .clickable { symbol = item },
                        contentAlignment = Alignment.Center,
                    ) { Icon(sceneIcon(item), item, tint = colors.ink2) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                repeat(ScenePalette.count) { i ->
                    val (_, foreground) = ScenePalette.color(i)
                    Box(
                        Modifier.size(40.dp).clip(CircleShape)
                            .border(2.dp, if (i == palette) colors.ink else Color.Transparent, CircleShape)
                            .padding(5.dp).clip(CircleShape).background(foreground).clickable { palette = i },
                    )
                }
            }
            Button(onClick = {
                val cover = SceneCover(symbol, palette)
                if (existing != null) store.updateScene(existing.copy(name = name.trim(), cover = cover)) else store.createScene(name, cover)
                onDismiss()
            }, enabled = name.isNotBlank(), modifier = Modifier.fillMaxWidth().height(52.dp), shape = RoundedCornerShape(26.dp)) {
                Text(if (existing == null) "创建" else "保存", fontWeight = FontWeight.Bold, fontSize = 17.sp)
            }
            if (existing != null) {
                TextButton(onClick = { deleting = true }, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    Text("删除场景…", color = Danger)
                }
            }
        }
    }
    if (deleting && existing != null) {
        DeleteSceneDialog(controller, existing, onDismiss = {
            deleting = false
            if (store.scene(existing.id) == null) onDismiss()
        })
    }
}

/** 生词本：加了星标的词，点开在弹窗里看词条 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StarredSheet(controller: ConversationController, onDismiss: () -> Unit) {
    val colors = Lx.colors
    var open by remember { mutableStateOf<String?>(null) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = colors.background) {
        Column(Modifier.fillMaxHeight(0.85f).padding(horizontal = 16.dp)) {
            Text("生词本", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = colors.ink, modifier = Modifier.align(Alignment.CenterHorizontally))
            val starred = HistoryStore.starred
            if (starred.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Rounded.Star, null, tint = colors.ink3, modifier = Modifier.size(40.dp))
                    Text("生词本是空的", fontWeight = FontWeight.SemiBold, color = colors.ink)
                    Text("在词典卡片上点星标，就能把词加进来。", color = colors.ink3, fontSize = 14.sp)
                }
            }
            LazyColumn {
                items(starred, key = { it.text }) { item ->
                    Row(Modifier.fillMaxWidth().clickable { open = item.text }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(item.text, fontWeight = FontWeight.SemiBold, color = colors.ink, fontSize = 16.sp)
                            Text(item.summary, color = colors.ink3, fontSize = 13.sp, maxLines = 1)
                        }
                        IconButton(onClick = { HistoryStore.toggleStar(item.text) }) { Icon(Icons.Rounded.Close, "移除", tint = colors.ink3) }
                    }
                    HorizontalDivider(color = colors.line)
                }
            }
        }
    }
    open?.let { word -> WordSheet(word, null, translate = { controller.quickTranslate(it) }, onDismiss = { open = null }) }
}

/** 查看一张图片：旋转后重新识别这一张，或删除它和它的译文 */
@Composable
fun ImageViewer(controller: ConversationController, turnId: String, imageId: String, onDismiss: () -> Unit) {
    val store = controller.store
    val turn = store.turn(controller.currentId, turnId)
    val index = turn?.images?.indexOfFirst { it.id == imageId } ?: -1
    val item = turn?.images?.getOrNull(index)
    if (item == null) {
        onDismiss()
        return
    }
    val bitmap = remember(item.fileName, item.done) { store.image(item.fileName) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        BackHandler(onBack = onDismiss)
        Column(Modifier.fillMaxSize().background(Color.Black).statusBarsPadding().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onDismiss) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "返回", tint = Color.White) }
                Text("图 ${index + 1} / ${turn.images.size}", color = Color.White, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) { Icon(Icons.Rounded.Check, "完成", tint = Color(0xFF8CC0FF)) }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (bitmap != null) Image(bitmap.asImageBitmap(), "图 ${index + 1}", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
            }
            Text(
                if (!item.done) "重新识别中…" else item.recognized.ifEmpty { "没有识别到文字" },
                color = Color.White.copy(alpha = 0.75f), fontSize = 13.sp, maxLines = 4, modifier = Modifier.padding(16.dp),
            )
            Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally)) {
                OutlinedButton(onClick = { controller.rotateImage(turnId, imageId) }) {
                    Icon(Icons.Rounded.Rotate90DegreesCw, null, tint = Color.White)
                    Spacer(Modifier.width(6.dp))
                    Text("旋转", color = Color.White)
                }
                OutlinedButton(onClick = {
                    controller.deleteImage(turnId, imageId)
                    onDismiss()
                }) {
                    Icon(Icons.Rounded.Delete, null, tint = Color(0xFFFF9A82))
                    Spacer(Modifier.width(6.dp))
                    Text("删除这张", color = Color(0xFFFF9A82))
                }
            }
        }
    }
}
