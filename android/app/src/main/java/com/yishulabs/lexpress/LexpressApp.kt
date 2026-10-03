package com.yishulabs.lexpress

import android.app.Application
import com.yishulabs.lexpress.ai.AISettings
import com.yishulabs.lexpress.ai.UsageStore
import com.yishulabs.lexpress.conversation.ConversationController
import com.yishulabs.lexpress.conversation.HistoryStore
import com.yishulabs.lexpress.core.Prefs
import com.yishulabs.lexpress.core.SecretStore
import com.yishulabs.lexpress.core.Speaker

class LexpressApp : Application() {
    /** 整个 app 只有一个会话控制器，旋转屏幕、切换窗口大小时不重建 */
    val controller: ConversationController by lazy { ConversationController(this) }

    override fun onCreate() {
        super.onCreate()
        Prefs.init(this)
        SecretStore.init(this)
        AISettings.init(this)
        UsageStore.init(this)
        HistoryStore.init(this)
        Speaker.init(this)
    }
}
