import Foundation

struct Phonetic: Identifiable {
    let id = UUID()
    let label: String      // 英 / 美
    let ipa: String
    let accent: Int        // 有道发音参数：1 英音，2 美音
}

struct Definition: Identifiable {
    let id = UUID()
    let text: String
    let note: String?
}

struct ExamplePair: Identifiable {
    let id = UUID()
    let source: String        // 可能带 <b> 高亮
    let translation: String
    let english: String       // 用于朗读的英文原句
}

struct CollinsSense: Identifiable {
    let id = UUID()
    let pos: String?
    let explanation: String   // 英文解释 + 中文释义，可能带 <b>
    let examples: [ExamplePair]
}

struct Phrase: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

struct RelatedWord: Identifiable {
    let id = UUID()
    let pos: String
    let word: String
    let meaning: String
}

struct Suggestion: Identifiable {
    let id = UUID()
    let word: String
    let meaning: String
}

struct WordEntry {
    var word: String
    var isChinese: Bool
    var phonetics: [Phonetic] = []
    var pinyin: String?
    var tags: [String] = []
    var definitions: [Definition] = []
    var forms: [String] = []
    var collins: [CollinsSense] = []
    var examples: [ExamplePair] = []
    var webMeanings: [String] = []
    var phrases: [Phrase] = []
    var related: [RelatedWord] = []

    var hasContent: Bool {
        !definitions.isEmpty || !collins.isEmpty || !webMeanings.isEmpty
    }
}

struct SentenceResult {
    let source: String
    let translation: String
    let sourceIsChinese: Bool
    let engine: String
    var suggestions: [Suggestion] = []
}

enum Phase {
    case idle
    case loading
    case word(WordEntry)
    case sentence(SentenceResult)
    case failed(String)
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var containsChinese: Bool {
        unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    var strippingTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
