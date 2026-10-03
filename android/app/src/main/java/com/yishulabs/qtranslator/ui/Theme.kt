package com.yishulabs.qtranslator.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** 和苹果版一致的轻快明亮配色：蓝色是主色，橙色专门给 AI */
@Immutable
data class LxColors(
    val background: Color,
    val wash: Color,
    val surface: Color,
    val surface2: Color,
    val accent: Color,
    val accentSoft: Color,
    val onAccent: Color,
    val ai: Color,
    val aiSoft: Color,
    val ink: Color,
    val ink2: Color,
    val ink3: Color,
    val line: Color,
)

private val Light = LxColors(
    background = Color(0xFFFFFFFF), wash = Color(0xFFE4F0FF), surface = Color(0xFFF1F7FF), surface2 = Color(0xFFE1ECFB),
    accent = Color(0xFF0B6BF0), accentSoft = Color(0xFFDCEBFF), onAccent = Color.White,
    ai = Color(0xFFB8430A), aiSoft = Color(0xFFFFEEDD),
    ink = Color(0xFF0F1720), ink2 = Color(0xFF4A5565), ink3 = Color(0xFF5F6B7A), line = Color(0x170F1720),
)

private val Dark = LxColors(
    background = Color(0xFF0B0E13), wash = Color(0xFF0F1B2E), surface = Color(0xFF161B23), surface2 = Color(0xFF232A35),
    accent = Color(0xFF62A8FF), accentSoft = Color(0xFF12305A), onAccent = Color(0xFF04142B),
    ai = Color(0xFFFFAE78), aiSoft = Color(0xFF3A2210),
    ink = Color(0xFFF1F4F8), ink2 = Color(0xFFAEB8C4), ink3 = Color(0xFF97A2AF), line = Color(0x1FFFFFFF),
)

val LocalLx = staticCompositionLocalOf { Light }

object Lx {
    val colors: LxColors @Composable get() = LocalLx.current
}

/** 场景封面配色：浅色底 + 深色图标 */
object ScenePalette {
    private val light = listOf(
        Color(0xFFDCEBFF) to Color(0xFF0A58C9), Color(0xFFE3F5EA) to Color(0xFF1E7A45), Color(0xFFFFEEDD) to Color(0xFFB8430A),
        Color(0xFFDDF3F2) to Color(0xFF0B6B66), Color(0xFFFFF4D6) to Color(0xFF8A5A00), Color(0xFFECEEF2) to Color(0xFF4A5565),
    )
    private val dark = listOf(
        Color(0xFF12305A) to Color(0xFF8CC0FF), Color(0xFF123322) to Color(0xFF7FD6A3), Color(0xFF3A2210) to Color(0xFFFFAE78),
        Color(0xFF0F3331) to Color(0xFF6FD3CC), Color(0xFF3A2E0C) to Color(0xFFF2C14E), Color(0xFF262A30) to Color(0xFFAEB8C4),
    )
    val count = light.size

    @Composable
    fun color(index: Int): Pair<Color, Color> {
        val list = if (isSystemInDarkTheme()) dark else light
        return list[((index % count) + count) % count]
    }
}

@Composable
fun QTranslatorTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val lx = if (dark) Dark else Light
    val scheme = if (dark) {
        darkColorScheme(
            primary = lx.accent, onPrimary = lx.onAccent, primaryContainer = lx.accentSoft, background = lx.background,
            surface = lx.background, surfaceContainerLow = lx.surface, surfaceContainer = lx.surface,
            surfaceContainerHigh = lx.surface2, onSurface = lx.ink, onSurfaceVariant = lx.ink2, error = Color(0xFFFF6B5E),
        )
    } else {
        lightColorScheme(
            primary = lx.accent, onPrimary = lx.onAccent, primaryContainer = lx.accentSoft, background = lx.background,
            surface = lx.background, surfaceContainerLow = lx.surface, surfaceContainer = lx.surface,
            surfaceContainerHigh = lx.surface2, onSurface = lx.ink, onSurfaceVariant = lx.ink2, error = Color(0xFFD92D20),
        )
    }
    CompositionLocalProvider(LocalLx provides lx) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
