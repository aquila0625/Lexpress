import Foundation

/// 一次 AI 请求的用量
struct UsageRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    /// AIProvider.rawValue
    let provider: String
    let model: String
    let input: Int
    let output: Int

    var total: Int { input + output }
    var cost: Double? { Pricing.cost(model: model, input: input, output: output) }
}

/// 记录每次 AI 请求消耗的 token，用于设置页的累计用量和用量报表。只保存在本机。
@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var records: [UsageRecord] = []

    private static var fileURL: URL { ConversationStore.directory.appendingPathComponent("usage.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([UsageRecord].self, from: data) {
            records = saved
        }
    }

    func add(provider: AIProvider, model: String, usage: AIUsage) {
        records.append(UsageRecord(date: Date(), provider: provider.rawValue, model: model,
                                   input: usage.input, output: usage.output))
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func records(for provider: AIProvider?) -> [UsageRecord] {
        guard let provider else { return records }
        return records.filter { $0.provider == provider.rawValue }
    }

    struct Summary {
        var input = 0
        var output = 0
        /// 能按官方标价算出的部分的费用（美元）
        var cost: Double = 0
        /// 有些模型没有价格数据，费用只算了一部分
        var hasUnpriced = false
        var total: Int { input + output }
    }

    static func summarize(_ records: [UsageRecord]) -> Summary {
        records.reduce(into: Summary()) { s, r in
            s.input += r.input
            s.output += r.output
            if let cost = r.cost { s.cost += cost } else { s.hasUnpriced = true }
        }
    }
}

/// 按服务商公开的标价估算费用（美元 / 每百万 token，输入和输出分开计价）。
/// 只用于估算，实际以服务商账单为准；价格变化后需要更新这张表。
enum Pricing {
    private static let table: [String: (input: Double, output: Double)] = [
        // Claude
        "claude-opus-5-5": (4, 20), "claude-sonnet-5-5": (2, 10), "claude-haiku-4-5": (1, 5),
        // OpenAI
        "gpt-6-astra": (10, 50), "gpt-6.1-sol": (2, 10), "gpt-6-sol": (2, 10), "gpt-6-luna": (0.1, 0.5),
        "gpt-5.6-sol": (4, 20), "gpt-5.6-terra": (2, 12), "gpt-5.6-luna": (0.2, 1.2), "gpt-5.5": (5, 30),
        "gpt-5.4": (2.5, 15), "gpt-5.4-mini": (0.75, 4.5), "gpt-5.4-nano": (0.2, 1.25), "gpt-5.2": (1.75, 14),
        "gpt-5.1": (1.25, 10), "gpt-5": (1.25, 10), "gpt-5-mini": (0.25, 2), "gpt-5-nano": (0.05, 0.4),
        "gpt-4.1": (2, 8), "gpt-4.1-mini": (0.4, 1.6), "gpt-4.1-nano": (0.1, 0.4),
        "gpt-4o": (2.5, 10), "gpt-4o-mini": (0.15, 0.6),
    ]

    static func cost(model: String, input: Int, output: Int) -> Double? {
        guard let price = table[model] else { return nil }
        return (Double(input) * price.input + Double(output) * price.output) / 1_000_000
    }

    /// 例如 “$0.0123”；很小的金额显示到小数点后 4 位
    static func format(_ dollars: Double) -> String {
        dollars >= 1 ? String(format: "$%.2f", dollars) : String(format: "$%.4f", dollars)
    }
}
