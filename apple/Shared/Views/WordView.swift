import SwiftUI

/// 单词 / 短语的词典结果。窄屏单栏，宽屏分左右两栏。
struct WordView: View {
    let entry: WordEntry
    @ObservedObject var model: TranslatorModel
    let wide: Bool

    @ObservedObject private var history = HistoryStore.shared
    @State private var showAllSenses = false

    private let senseLimit = 8

    var body: some View {
        if wide {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 20) { primary }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 20) { secondary }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                primary
                secondary
            }
        }
    }

    // MARK: 词头和释义

    @ViewBuilder
    private var primary: some View {
        header

        if !entry.definitions.isEmpty {
            if entry.isChinese {
                Block("英文说法") {
                    ForEach(entry.definitions) { d in
                        HStack(alignment: .top, spacing: 4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Button(d.text) { model.lookup(d.text) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 21, weight: .medium, design: .serif))
                                    .foregroundStyle(Color.lxAccent)
                                if let note = d.note {
                                    Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            SpeakButton { Speaker.shared.english(d.text) }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
            } else {
                // 按词性汇总，一眼看完全部意思
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.definitions) { d in
                        Text(d.text).font(.callout).textSelection(.enabled)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.lxSurface, in: .rect(cornerRadius: 18))
            }
        }

        if !entry.senses.isEmpty {
            Block("逐条释义", trailing: "常用的在前") {
                let shown = showAllSenses ? entry.senses : Array(entry.senses.prefix(senseLimit))
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, sense in
                    SenseRow(index: index + 1, sense: sense)
                }
                if entry.senses.count > senseLimit {
                    Button(showAllSenses ? "收起" : "显示全部 \(entry.senses.count) 条释义") {
                        showAllSenses.toggle()
                    }
                    .font(.callout.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
        }

        if !entry.webMeanings.isEmpty, entry.senses.isEmpty {
            Block("网络释义") {
                Text(entry.webMeanings.joined(separator: "；")).textSelection(.enabled)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(entry.word)
                    .font(entry.isChinese ? .system(size: 38, weight: .semibold)
                                          : .system(size: 42, weight: .medium, design: .serif))
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                let starred = history.isStarred(entry.word)
                GlassIconButton(systemName: starred ? "star.fill" : "star",
                                label: starred ? "从生词本移除" : "加入生词本",
                                tint: starred ? .orange : .primary) {
                    history.toggleStar(entry.word)
                }
            }

            // 放不下一行时自动换成上下排列，音标不截断
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pronunciations }
                VStack(alignment: .leading, spacing: 8) { pronunciations }
            }

            if !entry.forms.isEmpty {
                Text(entry.forms.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if !entry.tags.isEmpty {
                Text(entry.tags.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var pronunciations: some View {
        if entry.isChinese {
            PronunciationPill(label: "中", text: entry.pinyin ?? "朗读") { Speaker.shared.chinese(entry.word) }
        } else if entry.phonetics.isEmpty {
            PronunciationPill(label: "美", text: "朗读") { Speaker.shared.english(entry.word, accent: 2) }
        } else {
            ForEach(entry.phonetics) { p in
                PronunciationPill(label: p.label, text: "/\(p.ipa)/") {
                    Speaker.shared.english(entry.word, accent: p.accent)
                }
            }
        }
    }

    // MARK: 搭配、例句和更多

    @ViewBuilder
    private var secondary: some View {
        if !entry.phrases.isEmpty {
            Block("常用搭配") {
                VStack(spacing: 0) {
                    ForEach(entry.phrases) { p in
                        PhraseRow(key: p.key, value: p.value) { model.lookup(p.key) }
                    }
                }
            }
        }

        if !entry.examples.isEmpty {
            Block("例句") {
                ForEach(entry.examples) { ExampleRow(example: $0) }
            }
        }

        if !entry.related.isEmpty {
            Block("同根词") {
                VStack(spacing: 0) {
                    ForEach(entry.related) { r in
                        PhraseRow(key: r.word, value: "\(r.pos) \(r.meaning)", serif: true) { model.lookup(r.word) }
                    }
                }
            }
        }

        if !entry.distinctions.isEmpty {
            DisclosureGroup("近义词辨析") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(entry.distinctions) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title).font(.callout.weight(.semibold))
                            ForEach(group.usages) { usage in
                                (Text(usage.key).font(.system(.callout, design: .serif).weight(.semibold))
                                    + Text("　\(usage.value)").font(.callout).foregroundStyle(.secondary))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout.weight(.semibold))
        }

        if !entry.collins.isEmpty {
            DisclosureGroup("英文解释（柯林斯）") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(entry.collins.enumerated()), id: \.element.id) { index, sense in
                        VStack(alignment: .leading, spacing: 4) {
                            if let pos = sense.pos {
                                Text("\(index + 1). \(pos)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(rich(sense.explanation)).font(.callout).textSelection(.enabled)
                            ForEach(sense.examples.prefix(1)) { ExampleRow(example: $0) }
                        }
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout.weight(.semibold))
        }

        if let etymology = entry.etymology {
            DisclosureGroup("词源") {
                Text(etymology)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout.weight(.semibold))
        }

        Text("词典数据：有道词典").font(.caption2).foregroundStyle(.tertiary)
    }
}

/// “英 /tʃɑːdʒ/ 🔊” 这样的发音按钮
private struct PronunciationPill: View {
    let label: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.lxOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.lxAccent, in: .rect(cornerRadius: 7))
                Text(text).font(.callout).fixedSize()
                Image(systemName: "speaker.wave.2.fill").font(.footnote).foregroundStyle(Color.lxAccent)
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("\(label)式发音 \(text)")
    }
}

private struct SenseRow: View {
    let index: Int
    let sense: Sense

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(sense.isCommon ? Color.lxAccent : Color.secondary)
                .frame(width: 20, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pos = sense.pos {
                        Text(pos)
                            .font(.system(.footnote, design: .serif).weight(.semibold).italic())
                            .foregroundStyle(Color.lxAccent)
                    }
                    Text(sense.meaning).font(.body.weight(.medium)).textSelection(.enabled)
                    if sense.isCommon {
                        Text("常用")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.lxAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.lxAccentSoft, in: .rect(cornerRadius: 5))
                    }
                }
                if let example = sense.examples.first {
                    Text(rich(example.source)).font(.callout).foregroundStyle(.secondary)
                    if !example.translation.isEmpty {
                        Text(example.translation).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }
}
