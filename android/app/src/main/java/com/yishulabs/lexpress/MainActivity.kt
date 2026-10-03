package com.yishulabs.lexpress

import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.yishulabs.lexpress.ui.LexpressRoot
import com.yishulabs.lexpress.ui.loadBitmap

class MainActivity : ComponentActivity() {
    private val controller get() = (application as LexpressApp).controller

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { LexpressRoot(controller) }
        if (savedInstanceState == null) handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** 从别的 app 分享过来的文字、图片，或选中文字后点“快译”：放进当前会话翻译 */
    private fun handle(intent: Intent?) {
        intent ?: return
        when (intent.action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.let { controller.sendText(it.toString()) }
            Intent.ACTION_SEND -> {
                if (intent.type?.startsWith("image/") == true) {
                    val uri = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    } else {
                        @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
                    }
                    val bitmap: Bitmap? = uri?.let { loadBitmap(this, it) }
                    if (bitmap != null) controller.sendImages(listOf(bitmap))
                } else {
                    intent.getStringExtra(Intent.EXTRA_TEXT)?.let { controller.sendText(it) }
                }
            }
        }
    }
}
