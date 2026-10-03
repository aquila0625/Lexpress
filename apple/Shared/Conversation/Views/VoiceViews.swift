import SwiftUI

/// 正在听：实时显示识别出的文字（还可能变的部分是浅色），左下角是识别语言（点一下中英切换）和声波，
/// 右边红色按钮结束，左上角的叉取消
struct VoiceListeningPanel: View {
    @ObservedObject var voice = VoiceInput.shared
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("正在听 · \(voice.language.title)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.lxAccent)
                Spacer()
                if let start = voice.startedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消语音输入")
            }
            Group {
                if voice.text.isEmpty {
                    Text("请说话…").foregroundStyle(.tertiary)
                } else {
                    Text("\(Text(voice.finalText))\(Text(voice.volatileText).foregroundStyle(.secondary))")
                }
            }
            .font(.system(size: 17))
            .lineLimit(1...6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: voice.text)
            HStack(spacing: 10) {
                Button { voice.switchLanguage() } label: {
                    Label(voice.language == .english ? "英语 ⇄ 中文" : "中文 ⇄ 英语", systemImage: "globe")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.lxAccent)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.lxAccentSoft, in: .capsule)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("识别语言：\(voice.language.title)，点按切换")
                VoiceWave(levels: voice.levels)
                Spacer(minLength: 0)
                Button(action: onFinish) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.red, in: .circle)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .accessibilityLabel("说完了")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

/// 声波：最近一段时间的音量
struct VoiceWave: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Color.lxAccent.opacity(0.85))
                    .frame(width: 3, height: 4 + level * 22)
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

/// 麦克风按钮：输入框没有内容时代替发送按钮
struct MicButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.lxAccent)
                .frame(width: size, height: size)
                .background(Color.lxAccentSoft, in: .circle)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("语音输入")
    }
}

/// 语音出错时的提示（例如没有权限），点一下关掉
struct VoiceErrorBanner: View {
    @ObservedObject var voice = VoiceInput.shared

    var body: some View {
        if case .failed(let message) = voice.state {
            Button { voice.clearError() } label: {
                Label(message, systemImage: "mic.slash")
                    .font(.footnote)
                    .foregroundStyle(Color.lxAI)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 一轮里的“回放原声”：语音输入时录下的声音
struct AudioReplayButton: View {
    let name: String
    let duration: Double?
    @ObservedObject private var playback = AudioPlayback.shared

    var body: some View {
        let playing = playback.playing == name
        Button { playback.toggle(name) } label: {
            Label(playing ? "停止" : "回放原声" + (duration.map { " " + Self.format($0) } ?? ""),
                  systemImage: playing ? "stop.fill" : "waveform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.lxAccent)
                .frame(minHeight: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    static func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
