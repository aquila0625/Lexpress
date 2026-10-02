import Foundation

/// MyMemory 免费接口：无需 key，匿名每天约 5000 字符，单次请求不超过 500 字节。
/// 只在系统离线翻译模型未安装时作为兜底。
enum OnlineTranslator {
    static let name = "MyMemory 在线"
    private static let chunkLimit = 450

    static func translate(_ text: String, fromChinese: Bool) async throws -> String {
        let pair = fromChinese ? "zh-CN|en" : "en|zh-CN"
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            guard !line.trimmed.isEmpty else { lines.append(""); continue }
            var parts: [String] = []
            for chunk in chunks(of: line) {
                parts.append(try await request(chunk, pair: pair))
            }
            lines.append(parts.joined(separator: fromChinese ? " " : ""))
        }
        return lines.joined(separator: "\n")
    }

    private static func request(_ text: String, pair: String) async throws -> String {
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comps.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "langpair", value: pair)]
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: comps.url!, timeoutInterval: 10))
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root["responseData"] as? [String: Any],
              let result = body["translatedText"] as? String,
              !result.uppercased().contains("MYMEMORY WARNING") else {
            throw URLError(.badServerResponse)
        }
        // 接口偶尔会把回车、引号等以 HTML 实体形式返回
        return result
            .replacingOccurrences(of: "&#x0D;", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmed
    }

    /// 按句子边界切块，保证每块不超过字节上限。
    private static func chunks(of line: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for ch in line {
            current.append(ch)
            if ".!?;。！？；".contains(ch) || current.utf8.count >= chunkLimit - 4 {
                sentences.append(current)
                current = ""
            }
        }
        if !current.isEmpty { sentences.append(current) }

        var result: [String] = []
        var block = ""
        for s in sentences {
            if !block.isEmpty, block.utf8.count + s.utf8.count > chunkLimit {
                result.append(block)
                block = ""
            }
            block += s
        }
        if !block.trimmed.isEmpty { result.append(block) }
        return result
    }
}
