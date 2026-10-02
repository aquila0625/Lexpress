import AVFoundation

/// 发音：英文优先用有道真人发音（区分英/美音），拿不到或中文时用系统语音合成（离线可用）。
@MainActor
final class Speaker: NSObject {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?
    private var failureObserver: NSObjectProtocol?

    /// accent：1 英音，2 美音
    func english(_ text: String, accent: Int = 2) {
        stop()
        guard text.count <= 300 else { return synthesize(text, language: accent == 1 ? "en-GB" : "en-US") }
        var comps = URLComponents(string: "https://dict.youdao.com/dictvoice")!
        comps.queryItems = [URLQueryItem(name: "audio", value: text), URLQueryItem(name: "type", value: String(accent))]
        let item = AVPlayerItem(url: comps.url!)
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.synthesize(text, language: accent == 1 ? "en-GB" : "en-US") }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
    }

    func chinese(_ text: String) {
        stop()
        synthesize(text, language: "zh-CN")
    }

    func speak(_ text: String, isChinese: Bool) {
        isChinese ? chinese(text) : english(text)
    }

    private func synthesize(_ text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    private func stop() {
        player?.pause()
        player = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
        synthesizer.stopSpeaking(at: .immediate)
    }
}
