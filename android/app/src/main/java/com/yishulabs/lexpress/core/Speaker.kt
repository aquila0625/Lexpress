package com.yishulabs.lexpress.core

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/** 要朗读的一段话。同一段话再点一次就是停止。 */
data class Speech(val text: String, val isChinese: Boolean, val accent: Int) {
    companion object {
        fun english(text: String, accent: Int? = null) = Speech(text, false, accent ?: Prefs.accent)
        fun chinese(text: String) = Speech(text, true, 0)
        fun text(text: String, isChinese: Boolean) = if (isChinese) chinese(text) else english(text)
    }
}

/** 发音：英文优先用有道真人发音（区分英/美音），拿不到或中文时用系统语音合成。 */
object Speaker {
    /** 正在朗读的内容；界面据此把“朗读”按钮换成“停止” */
    var playing by mutableStateOf<Speech?>(null)
        private set

    private var tts: TextToSpeech? = null
    private var player: MediaPlayer? = null
    private val main = Handler(Looper.getMainLooper())

    fun init(context: Context) {
        tts = TextToSpeech(context.applicationContext) {}.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = finished(utteranceId)
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) = finished(utteranceId)
            })
        }
    }

    private fun finished(utteranceId: String?) {
        main.post { if (playing?.hashCode()?.toString() == utteranceId) playing = null }
    }

    /** 没在读这段就开始读；正在读这段就停下 */
    fun toggle(speech: Speech) {
        if (playing == speech) stop() else play(speech)
    }

    fun play(speech: Speech) {
        stop()
        playing = speech
        // 短的英文用真人发音，长段落和中文用系统语音
        if (!speech.isChinese && speech.text.length <= 300) playOnline(speech) else synthesize(speech)
    }

    fun stop() {
        player?.release()
        player = null
        tts?.stop()
        playing = null
    }

    private fun playOnline(speech: Speech) {
        val url = "https://dict.youdao.com/dictvoice?" + Http.query("audio" to speech.text, "type" to speech.accent.toString())
        val media = MediaPlayer()
        player = media
        media.setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        )
        media.setOnPreparedListener { if (player === it) it.start() }
        media.setOnCompletionListener { if (player === it && playing == speech) stop() }
        // 在线发音拿不到时退回系统语音
        media.setOnErrorListener { mp, _, _ ->
            if (player === mp && playing == speech) {
                mp.release()
                player = null
                synthesize(speech)
            }
            true
        }
        try {
            media.setDataSource(url)
            media.prepareAsync()
        } catch (e: Exception) {
            player = null
            media.release()
            synthesize(speech)
        }
    }

    private fun synthesize(speech: Speech) {
        val engine = tts ?: return run { playing = null }
        engine.language = when {
            speech.isChinese -> Locale.SIMPLIFIED_CHINESE
            speech.accent == 1 -> Locale.UK
            else -> Locale.US
        }
        engine.speak(speech.text, TextToSpeech.QUEUE_FLUSH, null, speech.hashCode().toString())
    }
}
