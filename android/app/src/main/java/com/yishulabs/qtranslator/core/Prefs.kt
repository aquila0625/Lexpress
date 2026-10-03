package com.yishulabs.qtranslator.core

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** 普通设置：朗读口音、自动朗读 */
object Prefs {
    lateinit var store: SharedPreferences
        private set

    fun init(context: Context) {
        store = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        accent = store.getInt("accent", 2)
        autoSpeak = store.getBoolean("autoSpeak", false)
    }

    /** 默认英文口音：1 英音，2 美音 */
    var accent by mutableIntStateOf(2)
        private set

    var autoSpeak by mutableStateOf(false)
        private set

    fun updateAccent(value: Int) {
        accent = value
        store.edit().putInt("accent", value).apply()
    }

    fun updateAutoSpeak(value: Boolean) {
        autoSpeak = value
        store.edit().putBoolean("autoSpeak", value).apply()
    }
}

/** API Key 只保存在本机：用 Android 密钥库里的密钥加密后再存 */
object SecretStore {
    private const val ALIAS = "qtranslator.ai"
    private lateinit var store: SharedPreferences

    fun init(context: Context) {
        store = context.getSharedPreferences("secrets", Context.MODE_PRIVATE)
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    fun get(account: String): String? {
        val saved = store.getString(account, null) ?: return null
        return runCatching {
            val bytes = Base64.decode(saved, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
            String(cipher.doFinal(bytes, 12, bytes.size - 12))
        }.getOrNull()
    }

    fun set(account: String, value: String) {
        if (value.isEmpty()) {
            store.edit().remove(account).apply()
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(value.toByteArray())
        store.edit().putString(account, Base64.encodeToString(encrypted, Base64.NO_WRAP)).apply()
    }
}
