package com.yishulabs.qtranslator.ui

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.AutoAwesome
import androidx.compose.material.icons.rounded.CameraAlt
import androidx.compose.material.icons.rounded.ContentPaste
import androidx.compose.material.icons.rounded.PhotoLibrary
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.yishulabs.qtranslator.ai.AISettings
import com.yishulabs.qtranslator.conversation.ChatSession
import com.yishulabs.qtranslator.conversation.ConversationController
import com.yishulabs.qtranslator.conversation.Direction
import java.io.File

/**
 * 底部输入栏：加号（拍照、相册多选、粘贴）、方向、AI 优化开关、发送。
 * 平时最多占屏幕 30%，粘贴长文时放宽到约一半，超出部分在框里滚动。
 */
@Composable
fun Composer(controller: ConversationController, session: ChatSession, maxHeightDp: Int, onNeedAI: () -> Unit) {
    val colors = Lx.colors
    val context = LocalContext.current
    var menu by remember { mutableStateOf(false) }
    var cameraUri by remember { mutableStateOf<Uri?>(null) }
    val isLong = controller.draft.length > 200

    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = cameraUri
        if (ok && uri != null) loadBitmap(context, uri)?.let { controller.sendImages(listOf(it)) }
    }
    val photos = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris ->
        controller.sendImages(uris.mapNotNull { loadBitmap(context, it) })
    }

    Surface(
        modifier = Modifier.navigationBarsPadding().padding(horizontal = 10.dp, vertical = 4.dp).fillMaxWidth(),
        shape = RoundedCornerShape(26.dp),
        color = colors.background,
        shadowElevation = 8.dp,
    ) {
        Column(Modifier.padding(horizontal = 4.dp, vertical = 4.dp)) {
            if (isLong) {
                Text(
                    "已输入 ${controller.draft.length} 个字符", fontSize = 12.sp, color = colors.ink3,
                    modifier = Modifier.padding(start = 12.dp, top = 6.dp),
                )
            }
            val maxHeight = (maxHeightDp * if (isLong) 0.5f else 0.3f).coerceAtLeast(80f).dp
            Box(
                Modifier.fillMaxWidth().heightIn(max = maxHeight).verticalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            ) {
                if (controller.draft.isEmpty()) Text("输入单词、句子或一段话", color = colors.ink3, fontSize = 17.sp)
                BasicTextField(
                    value = controller.draft,
                    onValueChange = { controller.draft = it },
                    textStyle = TextStyle(fontSize = 17.sp, color = colors.ink, lineHeight = 24.sp),
                    cursorBrush = SolidColor(colors.accent),
                    // 查单词时不要被自动改成首字母大写
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = { menu = true }) { Icon(Icons.Rounded.Add, "添加图片或粘贴", tint = colors.accent) }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("拍照") }, leadingIcon = { Icon(Icons.Rounded.CameraAlt, null) }, onClick = {
                            menu = false
                            val dir = File(context.cacheDir, "camera").apply { mkdirs() }
                            val file = File(dir, "photo-${System.currentTimeMillis()}.jpg")
                            val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
                            cameraUri = uri
                            camera.launch(uri)
                        })
                        DropdownMenuItem(text = { Text("从相册选图片（可多选）") }, leadingIcon = { Icon(Icons.Rounded.PhotoLibrary, null) }, onClick = {
                            menu = false
                            photos.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        })
                        DropdownMenuItem(text = { Text("粘贴剪贴板") }, leadingIcon = { Icon(Icons.Rounded.ContentPaste, null) }, onClick = {
                            menu = false
                            paste(context, controller)
                        })
                    }
                }
                Pill(
                    controller.direction.label, Icons.Rounded.SwapHoriz,
                    if (controller.direction != Direction.AUTO) colors.accent else colors.ink3,
                    if (controller.direction != Direction.AUTO) colors.accentSoft else colors.ink3.copy(alpha = 0.12f),
                    height = 34.dp, onClick = { controller.cycleDirection() },
                )
                Spacer(Modifier.width(6.dp))
                Pill(
                    "AI 优化", Icons.Rounded.AutoAwesome,
                    if (session.aiEnabled) colors.ai else colors.ink3,
                    if (session.aiEnabled) colors.aiSoft else colors.ink3.copy(alpha = 0.12f),
                    height = 34.dp,
                    onClick = {
                        if (!session.aiEnabled && !AISettings.isConfigured) onNeedAI()
                        controller.setAI(!session.aiEnabled)
                    },
                )
                Spacer(Modifier.weight(1f))
                val empty = controller.draft.isBlank()
                Box(
                    Modifier.padding(end = 4.dp).size(40.dp).clip(CircleShape)
                        .background(if (empty) colors.ink3.copy(alpha = 0.35f) else colors.accent)
                        .clickable(enabled = !empty) { controller.send() },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.ArrowUpward, "翻译", tint = colors.onAccent)
                }
            }
        }
    }
}

/** 剪贴板里是图片就作为一轮发送，是文字就放进输入框 */
private fun paste(context: Context, controller: ConversationController) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = clipboard.primaryClip ?: return
    val item = clip.getItemAt(0) ?: return
    val uri = item.uri
    if (uri != null && clip.description.hasMimeType("image/*")) {
        loadBitmap(context, uri)?.let { controller.sendImages(listOf(it)) }
        return
    }
    item.coerceToText(context)?.toString()?.let { controller.draft += it }
}
