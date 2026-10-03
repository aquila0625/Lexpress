import Charts
import SwiftUI

/// token 用量报表：按天统计，可以看最近一周或本月，可以按服务商筛选。
struct UsageReportView: View {
    @ObservedObject private var usage = UsageStore.shared
    @State private var monthView = false
    @State private var provider: AIProvider? = AISettings.shared.provider

    private struct DayTotal: Identifiable {
        let day: Date
        let tokens: Int
        var id: Date { day }
    }

    private var calendar: Calendar { .current }

    /// 周视图：今天和之前 6 天；月视图：本月每一天
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        if monthView {
            let start = calendar.dateInterval(of: .month, for: today)!.start
            let count = calendar.range(of: .day, in: .month, for: today)!.count
            return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        }
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private var rangeRecords: [UsageRecord] {
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        return usage.records(for: provider).filter { $0.date >= first && $0.date < end }
    }

    private var totals: [DayTotal] {
        let grouped = Dictionary(grouping: rangeRecords) { calendar.startOfDay(for: $0.date) }
        return days.map { DayTotal(day: $0, tokens: grouped[$0]?.reduce(0) { $0 + $1.total } ?? 0) }
    }

    var body: some View {
        let summary = UsageStore.summarize(rangeRecords)
        Form {
            Section {
                Picker("范围", selection: $monthView) {
                    Text("周").tag(false)
                    Text("月").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("服务商", selection: $provider) {
                    Text("全部").tag(AIProvider?.none)
                    ForEach(AIProvider.allCases) { Text($0.title).tag(Optional($0)) }
                }
            }

            Section(monthView ? "本月" : "最近 7 天") {
                LabeledContent("token 合计", value: summary.total.formatted())
                LabeledContent("输入 / 输出", value: "\(summary.input.formatted()) / \(summary.output.formatted())")
                LabeledContent("估算费用", value: costText(summary))
                Chart(totals) { item in
                    BarMark(x: .value("日期", item.day, unit: .day), y: .value("token", item.tokens))
                        .foregroundStyle(Color.lxAccent.gradient)
                        .cornerRadius(4)
                }
                .chartXAxis {
                    if monthView {
                        AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                            AxisValueLabel(format: .dateTime.day())
                        }
                    } else {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
                    }
                }
                .frame(height: 200)
                .padding(.vertical, 8)
            }

            let byModel = Dictionary(grouping: rangeRecords, by: \.model)
                .map { (model: $0.key, summary: UsageStore.summarize($0.value)) }
                .sorted { $0.summary.total > $1.summary.total }
            if !byModel.isEmpty {
                Section("按模型") {
                    ForEach(byModel, id: \.model) { item in
                        LabeledContent(item.model) {
                            VStack(alignment: .trailing) {
                                Text("\(item.summary.total.formatted()) tokens")
                                Text(costText(item.summary)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text("费用按服务商公开的标价估算，实际以服务商账单为准。DeepSeek 和自定义接口没有价格数据，只统计 token。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("用量报表")
    }

    private func costText(_ summary: UsageStore.Summary) -> String {
        if summary.total == 0 { return "—" }
        if summary.cost == 0, summary.hasUnpriced { return "无价格数据" }
        return "约 " + Pricing.format(summary.cost) + (summary.hasUnpriced ? "（部分无价格）" : "")
    }
}
