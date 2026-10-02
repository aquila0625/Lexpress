import AppKit
import OSLog
import SwiftUI
import Translation

/// 只记录字符数，不记录用户输入的内容
let log = Logger(subsystem: "com.yishulabs.lexpress", category: "app")

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var input = ""
    @Published var phase: Phase = .idle
    /// 变化时触发视图上的 translationTask，由系统提供离线翻译会话
    @Published var config: TranslationSession.Configuration?
    @Published var canDownloadOffline = false
    /// 当前文字的来源图片（粘贴或拖入），用于在结果上方显示缩略图
    @Published var sourceImage: NSImage?

    private var task: Task<Void, Never>?
    private var requestID = 0
    private var lastQuery = ""
    private var pendingText: String?
    private var pendingSuggestions: [Suggestion] = []
    private var wantsDownload = false

    // MARK: 输入

    func inputChanged() {
        // 中文输入法还在组字时不查询，避免把拼音当成英文去查
        if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return }
        schedule(delayMilliseconds: 450)
    }

    func submit() {
        lastQuery = ""
        schedule(delayMilliseconds: 0)
    }

    func lookup(_ word: String) {
        sourceImage = nil
        input = word
        submit()
    }

    /// 粘贴或拖入图片：先在本机识别文字，再按普通文本走翻译流程
    func translateImage(_ image: NSImage) {
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

    private func schedule(delayMilliseconds: Int) {
        let text = input.trimmed
        if !text.isEmpty, text == lastQuery { return }
        task?.cancel()
        lastQuery = ""
        requestID += 1
        guard !text.isEmpty else {
            phase = .idle
            sourceImage = nil
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
        let chinese = text.containsChinese
        var suggestions: [Suggestion] = []

        if isWordLike(text, chinese: chinese), let response = try? await Youdao.lookup(text) {
            guard id == requestID else { return }
            if let entry = response.entry {
                phase = .word(entry)
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
            phase = .sentence(SentenceResult(source: text, translation: result, sourceIsChinese: chinese,
                                             engine: OnlineTranslator.name, suggestions: suggestions))
        } catch {
            guard id == requestID, !Task.isCancelled else { return }
            phase = .failed("翻译失败，请检查网络后重试。")
        }
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
        let chinese = text.containsChinese

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
            phase = .sentence(SentenceResult(source: text, translation: lines.joined(separator: "\n"),
                                             sourceIsChinese: chinese, engine: "Apple 本地翻译",
                                             suggestions: suggestions))
        } catch {
            guard id == requestID else { return }
            await translateOnline(text, chinese: chinese, suggestions: suggestions, id: id)
        }
    }

    func downloadOfflineModel() {
        wantsDownload = true
        let (source, target) = languages(chinese: input.containsChinese)
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
}
