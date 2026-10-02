import SwiftUI
import Translation
import UniformTypeIdentifiers

extension Notification.Name {
    static let focusInput = Notification.Name("Lexpress.focusInput")
}

struct ContentView: View {
    @ObservedObject var model: TranslatorModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = model.sourceImage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("文字来自这张图片，在本机识别")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    result
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first, provider.canLoadObject(ofClass: NSImage.self) else { return false }
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in model.translateImage(image) }
            }
            return true
        }
        .translationTask(model.config) { session in
            await model.runSession(session)
        }
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            focused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            TextField("输入英文或中文：单词、句子或一段话", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .lineLimit(1...8)
                .focused($focused)
                .onSubmit { model.submit() }
                .onChange(of: model.input) { model.inputChanged() }
            if !model.input.isEmpty {
                Button {
                    model.input = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.top, 5)
                .help("清空")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var result: some View {
        switch model.phase {
        case .idle:
            Text("⌥D 随时呼出 · 回车立即翻译 · ⌘V 可粘贴图片 · Esc 隐藏")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 60)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
        case .word(let entry):
            WordView(entry: entry, model: model)
        case .sentence(let sentence):
            SentenceView(result: sentence, model: model)
        }
    }
}

// MARK: - 单词

private struct WordView: View {
    let entry: WordEntry
    let model: TranslatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if !entry.definitions.isEmpty {
                Block("释义") {
                    ForEach(entry.definitions) { d in
                        if entry.isChinese {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                SpeakButton { Speaker.shared.english(d.text) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Button(d.text) { model.lookup(d.text) }
                                        .buttonStyle(.link)
                                        .font(.body.weight(.medium))
                                    if let note = d.note {
                                        Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                        } else {
                            Text(d.text).textSelection(.enabled)
                        }
                    }
                    if !entry.forms.isEmpty {
                        Text(entry.forms.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if !entry.webMeanings.isEmpty {
                Block("网络释义") {
                    Text(entry.webMeanings.joined(separator: "；")).textSelection(.enabled)
                }
            }

            if !entry.collins.isEmpty {
                Block("详细解释（柯林斯）") {
                    ForEach(Array(entry.collins.enumerated()), id: \.element.id) { index, sense in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                                VStack(alignment: .leading, spacing: 3) {
                                    if let pos = sense.pos {
                                        Text(pos).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(rich(sense.explanation)).textSelection(.enabled)
                                }
                            }
                            ForEach(sense.examples) { ExampleRow(example: $0).padding(.leading, 20) }
                        }
                    }
                }
            }

            if !entry.examples.isEmpty {
                Block("例句") {
                    ForEach(entry.examples) { ExampleRow(example: $0) }
                }
            }

            if !entry.phrases.isEmpty {
                Block("词组短语") {
                    ForEach(entry.phrases) { p in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button(p.key) { model.lookup(p.key) }.buttonStyle(.link)
                            Text(p.value).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }

            if !entry.related.isEmpty {
                Block("同根词") {
                    ForEach(entry.related) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(r.pos).font(.caption).foregroundStyle(.secondary)
                            Button(r.word) { model.lookup(r.word) }.buttonStyle(.link)
                            Text(r.meaning).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("词典数据：有道词典").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.word)
                .font(.system(size: 28, weight: .semibold))
                .textSelection(.enabled)
            HStack(spacing: 16) {
                if entry.isChinese {
                    HStack(spacing: 5) {
                        if let pinyin = entry.pinyin { Text(pinyin).foregroundStyle(.secondary) }
                        SpeakButton { Speaker.shared.chinese(entry.word) }
                    }
                } else if entry.phonetics.isEmpty {
                    SpeakButton { Speaker.shared.english(entry.word) }
                } else {
                    ForEach(entry.phonetics) { p in
                        HStack(spacing: 5) {
                            Text(p.label).font(.caption).foregroundStyle(.secondary)
                            Text("/\(p.ipa)/").foregroundStyle(.secondary).textSelection(.enabled)
                            SpeakButton { Speaker.shared.english(entry.word, accent: p.accent) }
                        }
                    }
                }
                ForEach(entry.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }
}

// MARK: - 句子 / 段落

private struct SentenceView: View {
    let result: SentenceResult
    let model: TranslatorModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(result.translation)
                .font(.system(size: 17))
                .lineSpacing(4)
                .textSelection(.enabled)

            HStack(spacing: 14) {
                Button {
                    Speaker.shared.speak(result.translation, isChinese: !result.sourceIsChinese)
                } label: { Label("读译文", systemImage: "speaker.wave.2") }
                Button {
                    Speaker.shared.speak(result.source, isChinese: result.sourceIsChinese)
                } label: { Label("读原文", systemImage: "speaker.wave.1") }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.translation, forType: .string)
                    copied = true
                } label: { Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") }
                Spacer()
                Text(result.engine).font(.caption2).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)

            if model.canDownloadOffline {
                Button("下载系统离线翻译模型（更快、不限量、无需联网）") { model.downloadOfflineModel() }
                    .buttonStyle(.link)
                    .font(.callout)
            }

            if !result.suggestions.isEmpty {
                Block("你是不是要找") {
                    ForEach(result.suggestions) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button(s.word) { model.lookup(s.word) }.buttonStyle(.link)
                            Text(s.meaning).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 小组件

private struct Block<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct ExampleRow: View {
    let example: ExamplePair

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            SpeakButton { Speaker.shared.english(example.english) }
            VStack(alignment: .leading, spacing: 2) {
                Text(rich(example.source)).textSelection(.enabled)
                if !example.translation.isEmpty {
                    Text(example.translation).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}

private struct SpeakButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speaker.wave.2.fill").font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .help("朗读")
    }
}

/// 把接口返回的 <b>…</b> 高亮转成富文本，其余标签去掉。
private func rich(_ html: String) -> AttributedString {
    var output = AttributedString()
    var rest = Substring(html)
    var bold = false

    func piece(_ text: Substring) -> AttributedString {
        var part = AttributedString(String(text).strippingTags)
        if bold {
            part.inlinePresentationIntent = .stronglyEmphasized
            part.foregroundColor = .accentColor
        }
        return part
    }

    while let range = rest.range(of: bold ? "</b>" : "<b>") {
        output += piece(rest[..<range.lowerBound])
        rest = rest[range.upperBound...]
        bold.toggle()
    }
    output += piece(rest)
    return output
}
