import SwiftUI
import Translation

/// 系统离线翻译的排队器。Apple 的翻译会话只能在视图的 translationTask 里拿到，
/// 所以这里把每个请求挂起，等 translationTask 回调时一起处理。
@MainActor
final class SystemTranslator: ObservableObject {
    /// 绑定到根视图的 translationTask
    @Published var configuration: TranslationSession.Configuration?

    private struct Job {
        let id: UUID
        let text: String
        let source: Locale.Language
        let target: Locale.Language
        let continuation: CheckedContinuation<String, Error>
    }

    private var jobs: [Job] = []
    private var wantsPrepare = false

    static func languages(chinese: Bool) -> (Locale.Language, Locale.Language) {
        let zh = Locale.Language(identifier: "zh-Hans"), en = Locale.Language(identifier: "en")
        return chinese ? (zh, en) : (en, zh)
    }

    func status(chinese: Bool) async -> LanguageAvailability.Status {
        let (source, target) = Self.languages(chinese: chinese)
        return await LanguageAvailability().status(from: source, to: target)
    }

    /// 翻译一段文字，按行翻译以保留段落。语言模型没装好时直接报错，由调用方改用在线翻译。
    func translate(_ text: String, chinese: Bool) async throws -> String {
        guard await status(chinese: chinese) == .installed else { throw URLError(.resourceUnavailable) }
        let (source, target) = Self.languages(chinese: chinese)
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            jobs.append(Job(id: id, text: text, source: source, target: target, continuation: continuation))
            trigger(source: source, target: target)
            // 万一系统一直没有回调，20 秒后放弃，避免这一轮一直转圈
            Task {
                try? await Task.sleep(for: .seconds(20))
                self.fail(id)
            }
        }
    }

    /// 下载离线语言模型（系统会弹出确认）
    func prepare(chinese: Bool) {
        wantsPrepare = true
        let (source, target) = Self.languages(chinese: chinese)
        trigger(source: source, target: target)
    }

    /// 由根视图的 translationTask 调用
    func run(_ session: TranslationSession) async {
        if wantsPrepare {
            wantsPrepare = false
            try? await session.prepareTranslation()
        }
        guard let config = configuration else { return }
        let mine = jobs.filter { $0.source == config.source && $0.target == config.target }
        jobs.removeAll { job in mine.contains { $0.id == job.id } }
        for job in mine {
            do {
                var lines = job.text.components(separatedBy: "\n")
                let requests = lines.enumerated()
                    .filter { !$0.element.trimmed.isEmpty }
                    .map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
                for response in try await session.translations(from: requests) {
                    if let i = response.clientIdentifier.flatMap(Int.init) { lines[i] = response.targetText }
                }
                job.continuation.resume(returning: lines.joined(separator: "\n"))
            } catch {
                job.continuation.resume(throwing: error)
            }
        }
        // 还有别的语言方向在排队
        if let next = jobs.first { trigger(source: next.source, target: next.target) }
    }

    private func fail(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs.remove(at: index).continuation.resume(throwing: URLError(.timedOut))
    }

    private func trigger(source: Locale.Language, target: Locale.Language) {
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}
