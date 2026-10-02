import Foundation

/// 场景的封面：一个 SF Symbol 图标加一组配色
struct SceneCover: Codable, Hashable {
    var symbol: String
    var palette: Int

    static let symbols = ["book.closed.fill", "graduationcap.fill", "sun.max.fill", "leaf.fill",
                          "house.fill", "airplane", "fork.knife", "cart.fill",
                          "briefcase.fill", "cross.case.fill", "bubble.left.and.bubble.right.fill", "star.fill"]
}

/// 场景：会话的第一层分组，例如“教室”“户外交流”
struct SceneGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var cover: SceneCover
}

/// 一张图片：本机文件名、识别出的文字和它的译文
struct TurnImage: Codable, Identifiable, Equatable {
    var id = UUID()
    var fileName: String
    var recognized = ""
    var translation = ""
    var done = false
}

enum TurnState: String, Codable {
    case working, done, failed
}

/// 会话里的一轮：一次输入（文字或几张图片）和它的翻译结果
struct Turn: Codable, Identifiable {
    var id = UUID()
    var source: String
    var images: [TurnImage] = []
    var sourceIsChinese: Bool
    /// 用户手动指定了方向；否则按内容自动识别
    var manualDirection = false
    var edited = false
    var createdAt = Date()
    var state: TurnState = .working
    var word: WordEntry?
    var sentence: SentenceResult?
    var errorMessage: String?
    var aiError: String?
    var isOptimizing = false

    var isImage: Bool { !images.isEmpty }

    /// 原文目录里显示的那一行
    var outlineText: String {
        if isImage {
            let parts = images.map { String($0.recognized.prefix(24)) }.filter { !$0.isEmpty }
            return "\(images.count) 张图片" + (parts.isEmpty ? "" : "：" + parts.joined(separator: " / "))
        }
        return source
    }

    /// 搜索时匹配的全部文字
    var searchableText: String {
        [source, sentence?.translation ?? "", word?.summary ?? ""].joined(separator: "\n")
            + images.map { $0.recognized + "\n" + $0.translation }.joined(separator: "\n")
    }
}

/// 一个翻译会话
struct ChatSession: Codable, Identifiable {
    var id = UUID()
    var title: String
    /// 还没有被用户命名过：第一轮翻译后用原文开头当名称
    var autoTitled = true
    var sceneID: UUID?
    var aiEnabled: Bool
    var createdAt = Date()
    var updatedAt = Date()
    var turns: [Turn] = []

    static let defaultTitle = "新会话"

    var lastSnippet: String {
        guard let last = turns.last else { return "还没有内容" }
        return last.isImage ? "\(last.images.count) 张图片" : last.source
    }
}
