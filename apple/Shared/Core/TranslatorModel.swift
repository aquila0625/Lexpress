import OSLog
import SwiftUI
import Translation

/// 只记录字符数，不记录用户输入的内容
let log = Logger(subsystem: "com.yishulabs.qtranslator", category: "app")

/// 翻译方向：默认按输入内容自动识别，点方向按钮后变成手动指定
enum Direction {
    case auto, englishToChinese, chineseToEnglish
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var input = ""
    @Published var direction: Direction = .auto
    /// “对调”之后，最初输入的那段原文保留在这里，可以随时恢复
    @Published var preservedOriginal: String?
    @Published var phase: Phase = .idle
    /// 变化时触发视图上的 translationTask，由系统提供离线翻译会话
    @Published var config: TranslationSession.Configuration?
    @Published var canDownloadOffline = false
    /// 当前文字的来源图片（拍照、相册、粘贴或拖入），用于在结果上方显示缩略图
    @Published var sourceImage: PlatformImage?
    @Published var isCalibrating = false
    @Published var aiError: String?
    /// 每次从历史、词组等处点选查询时加一，界面据此收起键盘
    @Published private(set) var lookupCount = 0

    let history = HistoryStore.shared

    private var task: Task<Void, Never>?
    private var requestID = 0
    private var lastQuery = ""
    private var pendingText: String?
    private var pendingSuggestions: [Suggestion] = []
    private var pendingChinese = false
    private var wantsDownload = false

    // MARK: 输入

    func inputChanged() {
        // 中文输入法还在组字时不查询，避免把拼音当成英文去查
        if isComposingText { return }
        schedule(delayMilliseconds: 450)
    }

    func submit() {
        lastQuery = ""
        schedule(delayMilliseconds: 0)
    }

    // MARK: 方向

    /// 这段文字按当前方向算不算中文原文
    func sourceIsChinese(_ text: String) -> Bool {
        switch direction {
        case .auto: text.isMostlyChinese
        case .englishToChinese: false
        case .chineseToEnglish: true
        }
    }

    /// 点方向按钮：英译中、中译英来回切换，并按新方向重新翻译
    func toggleDirection() {
        direction = sourceIsChinese(input) ? .englishToChinese : .chineseToEnglish
        if !input.trimmed.isEmpty { submit() }
    }

    /// 把译文放到上面当原文，再反向翻译一次；最初的原文保留着
    func swapWithTranslation() {
        guard case .sentence(let result) = phase else { return }
        if preservedOriginal == nil { preservedOriginal = result.source }
        direction = .auto
        input = result.translation
        submit()
    }

    func restoreOriginal() {
        guard let original = preservedOriginal else { return }
        preservedOriginal = nil
        direction = .auto
        input = original
        submit()
    }

    func lookup(_ word: String) {
        lookupCount += 1
        sourceImage = nil
        preservedOriginal = nil
        direction = .auto
        input = word
        submit()
    }

    /// 图片翻译：先在本机识别文字，再按普通文本走翻译流程
    func translateImage(_ image: PlatformImage) {
        task?.cancel()
        requestID += 1
        let id = requestID
        sourceImage = image
        phase = .loading
        task = Task {
            let text = (try? await ImageText.recognize(image))?.trimmed ?? ""
            guard id == requestID else { return }
            log.info("image: recognized \(text.count, privacy: .public) characters")
            guard !text.isEmpty else {
                phase = .failed("这张图片里没有识别到文字。")
                return
            }
            input = text
            submit()
        }
    }

    private var isComposingText: Bool {
        #if os(macOS)
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
        #else
        // iOS 的拼音输入在组字时用 U+2006 分隔音节
        input.contains("\u{2006}")
        #endif
    }

    private func schedule(delayMilliseconds: Int) {
        let text = input.trimmed
        if !text.isEmpty, text == lastQuery { return }
        task?.cancel()
        lastQuery = ""
        requestID += 1
        aiError = nil
        guard !text.isEmpty else {
            phase = .idle
            sourceImage = nil
            preservedOriginal = nil
            direction = .auto
            return
        }
        if delayMilliseconds == 0 { lastQuery = text }
        task = Task {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                if Task.isCancelled { return }
                lastQuery = text
            }
            await run(text)
        }
    }

    // MARK: 查询

    private func run(_ text: String) async {
        requestID += 1
        let id = requestID
        phase = .loading
        let chinese = sourceIsChinese(text)
        var suggestions: [Suggestion] = []

        if isWordLike(text, chinese: text.containsChinese), let response = try? await Youdao.lookup(text) {
            guard id == requestID else { return }
            if let entry = response.entry {
                phase = .word(entry)
                history.add(entry.word, summary: entry.summary)
                if UserDefaults.standard.bool(forKey: SettingsKey.autoSpeak) {
                    Speaker.shared.play(.text(entry.word, isChinese: entry.isChinese))
                }
                return
            }
            suggestions = response.suggestions
        }
        guard id == requestID, !Task.isCancelled else { return }
        await translate(text, chinese: chinese, suggestions: suggestions, id: id)
    }

    private func translate(_ text: String, chinese: Bool, suggestions: [Suggestion], id: Int) async {
        let (source, target) = languages(chinese: chinese)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard id == requestID else { return }

        if status == .installed {
            pendingText = text
            pendingSuggestions = suggestions
            pendingChinese = chinese
            trigger(source: source, target: target)
            return
        }
        canDownloadOffline = status == .supported
        await translateOnline(text, chinese: chinese, suggestions: suggestions, id: id)
    }

    private func translateOnline(_ text: String, chinese: Bool, suggestions: [Suggestion], id: Int) async {
        do {
            let result = try await OnlineTranslator.translate(text, fromChinese: chinese)
            guard id == requestID else { return }
            finish(SentenceResult(source: text, translation: result, sourceIsChinese: chinese,
                                  engine: OnlineTranslator.name, suggestions: suggestions))
        } catch {
            guard id == requestID, !Task.isCancelled else { return }
            phase = .failed("翻译失败，请检查网络后重试。")
        }
    }

    private func finish(_ result: SentenceResult) {
        phase = .sentence(result)
        history.add(result.source, summary: result.translation)
        let ai = AISettings.shared
        if ai.autoCalibrate, ai.isConfigured { calibrate() }
    }

    // MARK: 系统离线翻译

    /// 由视图的 translationTask 回调
    func runSession(_ session: TranslationSession) async {
        if wantsDownload {
            wantsDownload = false
            if (try? await session.prepareTranslation()) != nil {
                canDownloadOffline = false
                submit()
            }
            return
        }
        guard let text = pendingText else { return }
        pendingText = nil
        let suggestions = pendingSuggestions
        let id = requestID
        let chinese = pendingChinese

        do {
            // 按行翻译以保留原文的段落结构
            var lines = text.components(separatedBy: "\n")
            let requests = lines.enumerated()
                .filter { !$0.element.trimmed.isEmpty }
                .map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
            for response in try await session.translations(from: requests) {
                if let index = response.clientIdentifier.flatMap(Int.init) { lines[index] = response.targetText }
            }
            guard id == requestID else { return }
            log.info("offline translation: \(text.count, privacy: .public) characters")
            finish(SentenceResult(source: text, translation: lines.joined(separator: "\n"),
                                  sourceIsChinese: chinese, engine: "系统离线翻译", suggestions: suggestions))
        } catch {
            guard id == requestID else { return }
            await translateOnline(text, chinese: chinese, suggestions: suggestions, id: id)
        }
    }

    func downloadOfflineModel() {
        wantsDownload = true
        let (source, target) = languages(chinese: sourceIsChinese(input))
        trigger(source: source, target: target)
    }

    private func trigger(source: Locale.Language, target: Locale.Language) {
        if config?.source == source, config?.target == target {
            config?.invalidate()
        } else {
            config = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func languages(chinese: Bool) -> (Locale.Language, Locale.Language) {
        let zh = Locale.Language(identifier: "zh-Hans"), en = Locale.Language(identifier: "en")
        return chinese ? (zh, en) : (en, zh)
    }

    /// 短输入先当“词/短语”查词典，查不到再走整句翻译
    private func isWordLike(_ text: String, chinese: Bool) -> Bool {
        if text.contains(where: { "\n,.!?;，。！？；".contains($0) }) { return false }
        if chinese { return text.count <= 8 }
        return text.count <= 40 && text.split(separator: " ").count <= 4
    }

    // MARK: AI 校准

    /// 用 AI 检查并修正当前这条机器翻译
    func calibrate() {
        guard case .sentence(let result) = phase, !result.calibrated, !isCalibrating else { return }
        let id = requestID
        let config = AIClient.currentConfig
        isCalibrating = true
        aiError = nil
        Task {
            defer { isCalibrating = false }
            do {
                let response = try await AITasks.calibrate(source: result.source, machine: result.translation,
                                                            sourceIsChinese: result.sourceIsChinese, config: config)
                let improved = response.text
                guard id == requestID, case .sentence(var current) = phase else { return }
                current.aiUsage = response.usage
                if improved != current.translation {
                    current.machineTranslation = current.translation
                    current.translation = improved
                }
                current.calibrated = true
                phase = .sentence(current)
                history.add(current.source, summary: current.translation)
                log.info("ai calibration: \(improved.count, privacy: .public) characters")
            } catch {
                guard id == requestID else { return }
                aiError = error.localizedDescription
            }
        }
    }
}
