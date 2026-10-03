import SwiftUI

/// 会话页的大脑：发送、翻译、编辑原文、AI 优化、图片处理。
@MainActor
final class ConversationController: ObservableObject {
    let store = ConversationStore()
    let translator = SystemTranslator()

    @Published var currentID: UUID
    @Published var draft = ""
    @Published var direction: Direction = .auto
    /// 系统离线翻译模型可以下载但还没下载
    @Published var offlineDownloadable = false

    init() {
        if let latest = store.sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
            currentID = latest.id
        } else {
            currentID = store.createSession(title: nil, sceneID: nil, aiEnabled: AISettings.shared.autoCalibrate).id
        }
    }

    var current: ChatSession? { store.session(currentID) }

    // MARK: 会话

    func select(_ id: UUID) {
        currentID = id
        direction = .auto
    }

    func newSession(title: String? = nil, sceneID: UUID? = nil, aiEnabled: Bool? = nil) {
        // 当前会话还是空的、也没起名，就直接复用它（移到要的场景里）
        if title == nil, let current, current.turns.isEmpty, current.autoTitled {
            store.moveSession(current.id, toScene: sceneID, before: nil)
            return
        }
        let session = store.createSession(title: title, sceneID: sceneID, aiEnabled: aiEnabled ?? AISettings.shared.autoCalibrate)
        select(session.id)
    }

    func deleteScene(_ id: UUID, deleteSessions: Bool) {
        let removesCurrent = deleteSessions && store.session(currentID)?.sceneID == id
        store.deleteScene(id, deleteSessions: deleteSessions)
        if removesCurrent {
            if let next = store.sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
                select(next.id)
            } else {
                currentID = store.createSession(title: nil, sceneID: nil, aiEnabled: AISettings.shared.autoCalibrate).id
            }
        }
    }

    func deleteSession(_ id: UUID) {
        store.deleteSession(id)
        if currentID == id {
            if let next = store.sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
                select(next.id)
            } else {
                currentID = store.createSession(title: nil, sceneID: nil, aiEnabled: AISettings.shared.autoCalibrate).id
            }
        }
    }

    func setAI(_ on: Bool) {
        store.updateSession(currentID) { $0.aiEnabled = on }
    }

    /// 方向按钮：自动 → 英译中 → 中译英 → 自动
    func cycleDirection() {
        switch direction {
        case .auto: direction = .englishToChinese
        case .englishToChinese: direction = .chineseToEnglish
        case .chineseToEnglish: direction = .auto
        }
    }

    private func sourceIsChinese(_ text: String) -> Bool {
        switch direction {
        case .auto: text.isMostlyChinese
        case .englishToChinese: false
        case .chineseToEnglish: true
        }
    }

    // MARK: 发送

    func send() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        draft = ""
        let turn = Turn(source: text, sourceIsChinese: sourceIsChinese(text), manualDirection: direction != .auto)
        let sessionID = currentID
        store.appendTurn(turn, to: sessionID)
        Task { await process(sessionID, turn.id) }
    }

    /// 一次发送多张图片，作为同一轮
    func sendImages(_ images: [PlatformImage]) {
        let files = images.compactMap { ConversationStore.saveImage($0) }
        guard !files.isEmpty else { return }
        let turn = Turn(source: "", images: files.map { TurnImage(fileName: $0) }, sourceIsChinese: direction == .chineseToEnglish,
                        manualDirection: direction != .auto)
        let sessionID = currentID
        store.appendTurn(turn, to: sessionID)
        Task { await process(sessionID, turn.id) }
    }

    /// 把译文放到原文的位置再反向翻译一次，作为新的一轮
    func swap(_ turn: Turn) {
        guard let translation = turn.sentence?.displayed else { return }
        let new = Turn(source: translation, sourceIsChinese: !turn.sourceIsChinese, manualDirection: true)
        let sessionID = currentID
        store.appendTurn(new, to: sessionID)
        Task { await process(sessionID, new.id) }
    }

    func retry(_ turnID: UUID) {
        let sessionID = currentID
        store.updateTurn(sessionID, turnID) {
            $0.state = .working
            $0.errorMessage = nil
        }
        Task { await process(sessionID, turnID) }
    }

    /// 改了原文：只重新翻译这一轮
    func editSource(_ turnID: UUID, to text: String) {
        let text = text.trimmed
        guard !text.isEmpty, let old = store.turn(currentID, turnID), old.source != text else { return }
        let sessionID = currentID
        store.updateTurn(sessionID, turnID) {
            $0.source = text
            $0.edited = true
            if !$0.manualDirection { $0.sourceIsChinese = text.isMostlyChinese }
            $0.state = .working
            $0.word = nil
            $0.sentence = nil
            $0.errorMessage = nil
            $0.aiError = nil
        }
        Task { await process(sessionID, turnID) }
    }

    func deleteTurn(_ turnID: UUID) {
        store.deleteTurn(currentID, turnID)
    }

    /// 删掉一张图片，它的译文一起去掉；最后一张也删了就删除整轮
    func deleteImage(_ turnID: UUID, _ imageID: UUID) {
        guard let turn = store.turn(currentID, turnID), let image = turn.images.first(where: { $0.id == imageID }) else { return }
        if turn.images.count == 1 {
            deleteTurn(turnID)
            return
        }
        store.deleteImageFile(image.fileName)
        store.updateTurn(currentID, turnID) {
            $0.images.removeAll { $0.id == imageID }
            $0.source = $0.images.map(\.recognized).joined(separator: "\n")
        }
    }

    /// 把图片顺时针转 90°，然后只重新识别和翻译这一张
    func rotateImage(_ turnID: UUID, _ imageID: UUID) {
        guard let turn = store.turn(currentID, turnID), let item = turn.images.first(where: { $0.id == imageID }),
              let image = store.image(named: item.fileName) else { return }
        store.replaceImageFile(item.fileName, with: image.rotatedClockwise())
        let sessionID = currentID
        store.updateTurn(sessionID, turnID) {
            if let i = $0.images.firstIndex(where: { $0.id == imageID }) {
                $0.images[i].recognized = ""
                $0.images[i].translation = ""
                $0.images[i].done = false
            }
            $0.state = .working
        }
        Task { await process(sessionID, turnID) }
    }

    // MARK: 翻译

    private func process(_ sessionID: UUID, _ turnID: UUID) async {
        guard let turn = store.turn(sessionID, turnID) else { return }
        if turn.isImage {
            await processImages(sessionID, turn)
        } else {
            await processText(sessionID, turn)
        }
    }

    private func processText(_ sessionID: UUID, _ turn: Turn) async {
        let text = turn.source
        var suggestions: [Suggestion] = []

        if Self.isWordLike(text), let response = try? await Youdao.lookup(text) {
            if let entry = response.entry {
                store.updateTurn(sessionID, turn.id) {
                    $0.word = entry
                    $0.state = .done
                }
                HistoryStore.shared.add(entry.word, summary: entry.summary)
                autoTitle(sessionID, from: text)
                if UserDefaults.standard.bool(forKey: SettingsKey.autoSpeak) {
                    Speaker.shared.play(.text(entry.word, isChinese: entry.isChinese))
                }
                return
            }
            suggestions = response.suggestions
        }

        do {
            let (translation, engine) = try await translateSentence(text, chinese: turn.sourceIsChinese)
            store.updateTurn(sessionID, turn.id) {
                $0.sentence = SentenceResult(source: text, translation: translation, sourceIsChinese: turn.sourceIsChinese,
                                             engine: engine, suggestions: suggestions)
                $0.state = .done
            }
            autoTitle(sessionID, from: text)
            // 单词和短语不自动用 AI：它们查词典就够了，AI 优化只针对整句话
            if store.session(sessionID)?.aiEnabled == true, AISettings.shared.isConfigured, !Self.isWordLike(text) {
                await optimize(sessionID, turn.id)
            }
        } catch {
            store.updateTurn(sessionID, turn.id) {
                $0.state = .failed
                $0.errorMessage = "翻译失败，请检查网络后重试。"
            }
        }
    }

    private func processImages(_ sessionID: UUID, _ turn: Turn) async {
        for item in turn.images where !item.done {
            guard let image = store.image(named: item.fileName) else { continue }
            let recognized = (try? await ImageText.recognize(image))?.trimmed ?? ""
            var translation = "（这张图片里没有识别到文字）"
            if !recognized.isEmpty {
                let chinese = turn.manualDirection ? turn.sourceIsChinese : recognized.isMostlyChinese
                translation = (try? await translateSentence(recognized, chinese: chinese))?.0 ?? "（翻译失败，可以点重试）"
            }
            store.updateTurn(sessionID, turn.id) {
                if let i = $0.images.firstIndex(where: { $0.id == item.id }) {
                    $0.images[i].recognized = recognized
                    $0.images[i].translation = translation
                    $0.images[i].done = true
                }
            }
        }
        store.updateTurn(sessionID, turn.id) {
            $0.source = $0.images.map(\.recognized).joined(separator: "\n")
            $0.state = .done
        }
        autoTitle(sessionID, from: "图片翻译")
    }

    /// 先用系统离线翻译，不行再用在线翻译
    private func translateSentence(_ text: String, chinese: Bool) async throws -> (String, String) {
        let status = await translator.status(chinese: chinese)
        if status == .installed, let result = try? await translator.translate(text, chinese: chinese) {
            return (result, "系统离线翻译")
        }
        offlineDownloadable = status == .supported
        return (try await OnlineTranslator.translate(text, fromChinese: chinese), OnlineTranslator.name)
    }

    func downloadOfflineModel() {
        translator.prepare(chinese: false)
        offlineDownloadable = false
    }

    // MARK: AI 优化

    /// 点“AI 优化”：打开时有之前的结果就直接用，没有才请求；再点一次关掉，显示机器翻译
    func toggleAI(_ turnID: UUID) {
        guard let sentence = store.turn(currentID, turnID)?.sentence else { return }
        if sentence.showsAI {
            store.updateTurn(currentID, turnID) { $0.sentence?.aiShown = false }
        } else if sentence.aiTranslation != nil {
            store.updateTurn(currentID, turnID) { $0.sentence?.aiShown = true }
        } else {
            let sessionID = currentID
            Task { await optimize(sessionID, turnID) }
        }
    }

    /// 换了服务商或模型后，重新用 AI 优化一次
    func reoptimize(_ turnID: UUID) {
        let sessionID = currentID
        Task { await optimize(sessionID, turnID, force: true) }
    }

    /// 完整词条里查不到的词组，用和会话相同的方式翻译
    func quickTranslate(_ text: String) async -> String? {
        try? await translateSentence(text, chinese: text.isMostlyChinese).0
    }

    private func optimize(_ sessionID: UUID, _ turnID: UUID, force: Bool = false) async {
        guard let turn = store.turn(sessionID, turnID), let sentence = turn.sentence, !turn.isOptimizing else { return }
        if sentence.aiTranslation != nil, !force {
            store.updateTurn(sessionID, turnID) { $0.sentence?.aiShown = true }
            return
        }
        store.updateTurn(sessionID, turnID) {
            $0.isOptimizing = true
            $0.aiError = nil
        }
        do {
            let config = AIClient.currentConfig
            let response = try await AITasks.calibrate(source: sentence.source, machine: sentence.translation,
                                                       sourceIsChinese: sentence.sourceIsChinese, config: config)
            store.updateTurn(sessionID, turnID) {
                guard var s = $0.sentence else { return }
                s.aiTranslation = response.text
                s.aiShown = true
                s.aiUsage = response.usage
                s.aiModel = "\(config.provider.title) · \(config.model)"
                $0.sentence = s
                $0.isOptimizing = false
            }
        } catch {
            store.updateTurn(sessionID, turnID) {
                $0.isOptimizing = false
                $0.aiError = error.localizedDescription
            }
        }
    }

    // MARK: 工具

    /// 没被用户命名的会话，用第一轮的原文开头当名称
    private func autoTitle(_ sessionID: UUID, from text: String) {
        guard let session = store.session(sessionID), session.autoTitled, session.title == ChatSession.defaultTitle else { return }
        let line = text.components(separatedBy: .newlines).first?.trimmed ?? text
        store.updateSession(sessionID) { $0.title = String(line.prefix(18)) }
    }

    /// 单词或短语（查词典）；不是的才算一句话，AI 优化只针对一句话
    static func isWordLike(_ text: String) -> Bool {
        if text.contains(where: { "\n,.!?;，。！？；".contains($0) }) { return false }
        if text.containsChinese { return text.count <= 8 }
        return text.count <= 40 && text.split(separator: " ").count <= 4
    }
}
