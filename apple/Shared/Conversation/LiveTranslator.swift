import SwiftUI
import Translation

/// 给同声传译和面对面对话用的专用翻译通道：系统本机翻译的会话一直开着，不像普通翻译那样每句都重建，
/// 一句通常不到 0.2 秒。本机翻译不可用时退回普通翻译（可能走在线翻译）。
/// 用法：在界面上挂 `.translationTask(translator.configuration) { await translator.run($0) }`。
@MainActor
final class LiveTranslator: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    /// 本机翻译可以用（已经装好或者正在用）；不可用时不做“边说边翻”
    @Published private(set) var onDevice = false

    private struct Job {
        let id = UUID()
        let text: String
        let continuation: CheckedContinuation<String?, Never>
    }

    private var pending: [Job] = []
    private var wake: AsyncStream<Void>.Continuation?
    private var sessionReady = false
    private var direction: Bool?
    private let fallback: (String, Bool) async -> String?

    init(fallback: @escaping (String, Bool) async -> String?) {
        self.fallback = fallback
    }

    /// 准备某个方向：检查本机翻译能不能用，能用就打开会话（没下载时系统会提示下载）
    func prepare(fromChinese: Bool) async {
        let (source, target) = SystemTranslator.languages(chinese: fromChinese)
        let status = await LanguageAvailability().status(from: source, to: target)
        onDevice = status != .unsupported
        guard onDevice, direction != fromChinese else { return }
        direction = fromChinese
        sessionReady = false
        configuration = TranslationSession.Configuration(source: source, target: target)
    }

    /// 翻译一句。live 为 true 表示还没说完的半句：只在本机翻译可用时才翻，不走在线
    func translate(_ text: String, fromChinese: Bool, live: Bool = false) async -> String? {
        if direction != fromChinese { await prepare(fromChinese: fromChinese) }
        guard onDevice else { return live ? nil : await fallback(text, fromChinese) }
        let result: String? = await withCheckedContinuation { continuation in
            let job = Job(text: text, continuation: continuation)
            pending.append(job)
            wake?.yield()
            // 翻译通道一直没开起来（比如系统还在等下载确认），过几秒就改走普通翻译
            Task {
                try? await Task.sleep(for: .seconds(live ? 2 : 6))
                if let i = self.pending.firstIndex(where: { $0.id == job.id }) {
                    self.pending.remove(at: i).continuation.resume(returning: nil)
                }
            }
        }
        if let result { return result }
        return live ? nil : await fallback(text, fromChinese)
    }

    /// 由界面的 translationTask 调用：会话一直开着，有新句子就翻
    func run(_ session: TranslationSession) async {
        do {
            try await session.prepareTranslation()
        } catch {
            // 用户没有下载模型，或者本机翻译出错：以后都走普通翻译
            onDevice = false
            failAll()
            return
        }
        sessionReady = true
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        defer {
            wake = nil
            sessionReady = false
        }
        var iterator = stream.makeAsyncIterator()
        while !Task.isCancelled {
            while !pending.isEmpty {
                let job = pending.removeFirst()
                let response = try? await session.translate(job.text)
                job.continuation.resume(returning: response?.targetText)
            }
            guard await iterator.next() != nil else { break }
        }
        failAll()
    }

    private func failAll() {
        let jobs = pending
        pending = []
        jobs.forEach { $0.continuation.resume(returning: nil) }
    }
}
