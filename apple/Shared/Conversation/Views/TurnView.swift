import SwiftUI

/// 会话里的一轮：右侧是原文（文字或图片），下面是结果。
struct TurnView: View {
    let turn: Turn
    @ObservedObject var controller: ConversationController
    @Binding var editingTurn: UUID?
    let onOpenWord: (WordEntry) -> Void
    let onReply: (SentenceResult) -> Void
    let onEditImage: (UUID) -> Void
    let onNeedAI: () -> Void
    /// 长内容是否展开：刚翻译出来的展开，重新打开会话时收起
    let expanded: Bool
    let onToggleExpand: () -> Void

    @State private var editText = ""
    @State private var copied = false
    @State private var showBefore = false
    @AppStorage(SettingsKey.showAIUsage) private var showUsage = false

    private var editing: Bool { editingTurn == turn.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if turn.isImage {
                imageSource
            } else if editing {
                editor
            } else {
                textSource
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            result
                .opacity(editing ? 0.4 : 1)
        }
    }

    private var caption: String {
        let direction = turn.sourceIsChinese ? "中 → 英" : "英 → 中"
        var parts = [turn.isImage ? "图片" : direction, turn.manualDirection ? "手动" : "自动"]
        if turn.edited { parts.append("已编辑") }
        return parts.joined(separator: " · ")
    }

    // MARK: 原文

    private var textSource: some View {
        FoldableText(text: turn.source, font: .system(size: 16), expanded: expanded, alignment: .trailing,
                     onToggle: onToggleExpand)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.lxAccentSoft, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                                       bottomTrailingRadius: 6, topTrailingRadius: 20))
            .contextMenu {
                Button("编辑原文", systemImage: "pencil") {
                    editText = turn.source
                    editingTurn = turn.id
                }
                Button("复制原文", systemImage: "doc.on.doc") { Clipboard.copy(turn.source) }
                Button("朗读原文", systemImage: "speaker.wave.2") {
                    Speaker.shared.toggle(.text(turn.source, isChinese: turn.sourceIsChinese))
                }
                Button("删除这一轮", systemImage: "trash", role: .destructive) { controller.deleteTurn(turn.id) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("原文", text: $editText, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(2...12)
            HStack(spacing: 8) {
                Button("取消") { editingTurn = nil }
                    .buttonStyle(.glass)
                Button("保存并重新翻译") {
                    controller.editSource(turn.id, to: editText)
                    editingTurn = nil
                }
                .buttonStyle(.glassProminent)
                .disabled(editText.trimmed.isEmpty)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).stroke(Color.lxAccent, lineWidth: 2))
        .onAppear { if editText.isEmpty { editText = turn.source } }
    }

    private var imageSource: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(turn.images.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, index: index)
                    }
                }
                .padding(.top, 10)
                .padding(.trailing, 10)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            Text("\(turn.images.count) 张图片" + (turn.state == .working ? " · 识别中" : " · 已识别"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.lxAccentSoft, in: .rect(cornerRadius: 20))
        .padding(.leading, 24)
        .contextMenu {
            Button("删除这一轮", systemImage: "trash", role: .destructive) { controller.deleteTurn(turn.id) }
        }
    }

    private func thumbnail(_ item: TurnImage, index: Int) -> some View {
        Button { onEditImage(item.id) } label: {
            Group {
                if let image = controller.store.image(named: item.fileName) {
                    Image(platformImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 88, height: 112)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text("图 \(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 6))
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("图 \(index + 1)，点按编辑")
        .overlay(alignment: .topTrailing) {
            Button { controller.deleteImage(turn.id, item.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .offset(x: 16, y: -16)
            .accessibilityLabel("删除图 \(index + 1) 和它的译文")
        }
    }

    // MARK: 结果

    @ViewBuilder
    private var result: some View {
        switch turn.state {
        case .working where !turn.isImage:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("翻译中…").font(.footnote).foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 12) {
                Label(turn.errorMessage ?? "翻译失败", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("重试") { controller.retry(turn.id) }
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
        default:
            if turn.isImage {
                imageResults
            } else if let entry = turn.word {
                WordCard(entry: entry) { onOpenWord(entry) }
            } else if let sentence = turn.sentence {
                sentenceResult(sentence)
            }
        }
    }

    private var imageResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chip(text: "本机识别 · 翻译", systemName: "checkmark")
            ForEach(Array(turn.images.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("图 \(index + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    if item.done {
                        FoldableText(text: item.translation, font: .system(size: 17, weight: .medium), expanded: expanded,
                                     onToggle: onToggleExpand)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("识别和翻译中…").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if turn.state == .done {
                HStack(spacing: 0) {
                    let all = turn.images.map(\.translation).joined(separator: "\n\n")
                    SpeakButton(speech: .text(all, isChinese: !(turn.images.first?.recognized.isMostlyChinese ?? false)))
                        .frame(width: 44, height: 44)
                    iconButton(copied ? "checkmark" : "doc.on.doc", "复制全部译文") {
                        Clipboard.copy(all)
                        copied = true
                    }
                }
                .padding(.leading, -12)
            }
        }
    }

    private func sentenceResult(_ sentence: SentenceResult) -> some View {
        // 单词和短语查不到词典时也走机器翻译，但不提供 AI 优化：AI 只针对一句话
        let isSentence = !ConversationController.isWordLike(sentence.source)
        let waitingForAI = turn.isOptimizing && !sentence.showsAI
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if sentence.showsAI {
                    // 用了 AI 就只标 AI，不再同时显示机器翻译的来源
                    aiChip(on: true)
                    if !turn.isOptimizing {
                        Button {
                            AISettings.shared.isConfigured ? controller.reoptimize(turn.id) : onNeedAI()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.lxAI)
                                .frame(width: 36, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重新用 AI 优化")
                    }
                } else {
                    if !waitingForAI { Chip(text: sentence.engine, systemName: "checkmark") }
                    if isSentence { aiChip(on: false) }
                }
            }
            if waitingForAI {
                // 开着 AI 优化时不先显示机器翻译，等优化好了直接显示结果
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("AI 优化中…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(minHeight: 28)
            } else {
                FoldableText(text: sentence.displayed, font: .system(size: 19, weight: .medium), lineSpacing: 4,
                             expanded: expanded, onToggle: onToggleExpand)
            }
            if sentence.showsAI {
                if sentence.aiTranslation != sentence.translation {
                    // 优化前的译文默认折叠
                    Button {
                        withAnimation(.snappy) { showBefore.toggle() }
                    } label: {
                        Label(showBefore ? "收起优化前" : "查看优化前的译文", systemImage: showBefore ? "chevron.up" : "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minHeight: 36)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if showBefore {
                        Text(sentence.translation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.lxSurface, in: .rect(cornerRadius: 12))
                    }
                } else {
                    Text("AI 认为原译文无需修改").font(.footnote).foregroundStyle(.secondary)
                }
                if showUsage {
                    Text([sentence.aiModel, sentence.aiUsage?.summary].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.lxAI)
                }
            }
            if let error = turn.aiError {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.lxAI)
            }
            HStack(spacing: 0) {
                SpeakButton(speech: .text(sentence.displayed, isChinese: !sentence.sourceIsChinese))
                    .frame(width: 44, height: 44)
                iconButton(copied ? "checkmark" : "doc.on.doc", "复制译文") {
                    Clipboard.copy(sentence.displayed)
                    copied = true
                }
                iconButton("arrow.up.arrow.down", "对调：把译文反向再翻译一次") { controller.swap(turn) }
                iconButton("arrowshape.turn.up.left", "AI 写回复", tint: .lxAI) {
                    AISettings.shared.isConfigured ? onReply(sentence) : onNeedAI()
                }
            }
            .padding(.leading, -12)
            if controller.offlineDownloadable, sentence.engine == OnlineTranslator.name {
                Button("下载系统离线翻译模型（更快、不限量、无需联网）") { controller.downloadOfflineModel() }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .frame(minHeight: 44)
            }
            if !sentence.suggestions.isEmpty {
                Text("你是不是要找：" + sentence.suggestions.prefix(3).map(\.word).joined(separator: "、"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// “AI 优化”开关：点一下用 AI 优化，再点一下回到机器翻译；之前优化过的结果会保留，打开时不用重新请求
    private func aiChip(on: Bool) -> some View {
        Button {
            let sentence = turn.sentence
            AISettings.shared.isConfigured || sentence?.aiTranslation != nil ? controller.toggleAI(turn.id) : onNeedAI()
        } label: {
            Label("AI 优化", systemImage: on ? "sparkles" : "sparkle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.lxAI : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(on ? Color.lxAISoft : Color.secondary.opacity(0.12), in: .capsule)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(turn.isOptimizing)
        .accessibilityLabel("AI 优化")
        .accessibilityValue(on ? "开" : "关")
    }

    private func iconButton(_ systemName: String, _ label: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 会话里的词典卡片：词头、发音、前几条释义，点按看完整词条
struct WordCard: View {
    let entry: WordEntry
    let onOpen: () -> Void

    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(entry.word)
                    .font(entry.isChinese ? .system(size: 26, weight: .semibold) : .system(size: 28, weight: .medium, design: .serif))
                    .textSelection(.enabled)
                Spacer()
                let starred = history.isStarred(entry.word)
                Button { history.toggleStar(entry.word) } label: {
                    Image(systemName: starred ? "star.fill" : "star")
                        .foregroundStyle(starred ? .orange : .secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(starred ? "从生词本移除" : "加入生词本")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pronunciations }
                VStack(alignment: .leading, spacing: 8) { pronunciations }
            }
            VStack(alignment: .leading, spacing: 6) {
                if entry.senses.isEmpty {
                    ForEach(entry.definitions.prefix(3)) { d in
                        Text(d.text + (d.note.map { "  " + $0 } ?? "")).font(.callout).lineLimit(3)
                    }
                } else {
                    ForEach(entry.senses.prefix(4)) { sense in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let pos = sense.pos {
                                Text(pos).font(.system(.footnote, design: .serif).weight(.semibold).italic()).foregroundStyle(Color.lxAccent)
                            }
                            Text(sense.meaning).font(.callout)
                        }
                    }
                }
            }
            Button(action: onOpen) {
                Label("完整词条：例句、搭配、辨析", systemImage: "book")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.lxSurface, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var pronunciations: some View {
        if entry.isChinese {
            PronunciationPill(label: "中", text: entry.pinyin ?? "朗读", speech: .chinese(entry.word))
        } else if entry.phonetics.isEmpty {
            PronunciationPill(label: "美", text: "朗读", speech: .english(entry.word, accent: 2))
        } else {
            ForEach(entry.phonetics) { p in
                PronunciationPill(label: p.label, text: "/\(p.ipa)/", speech: .english(entry.word, accent: p.accent))
            }
        }
    }
}

/// 超过 4 行时折叠；只有真的放不下时才出现“展开全文 / 收起”
struct FoldableText: View {
    let text: String
    let font: Font
    var lineSpacing: CGFloat = 0
    let expanded: Bool
    var alignment: HorizontalAlignment = .leading
    let onToggle: () -> Void

    private static let foldedLines = 4
    @State private var fullHeight: CGFloat = 0
    @State private var foldedHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            styled(Text(text))
                .lineLimit(expanded ? nil : Self.foldedLines)
                .textSelection(.enabled)
                .background(alignment: .topLeading) {
                    // 量一下完整高度和折叠后的高度，判断是不是真的被截断
                    ZStack(alignment: .topLeading) {
                        measured(styled(Text(text))) { fullHeight = $0 }
                        measured(styled(Text(text)).lineLimit(Self.foldedLines)) { foldedHeight = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
            if fullHeight > foldedHeight + 1 {
                Button(action: onToggle) {
                    Label(expanded ? "收起" : "展开全文", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.lxAccent)
            }
        }
    }

    private func styled(_ text: Text) -> some View {
        text.font(font).lineSpacing(lineSpacing)
    }

    private func measured(_ view: some View, _ update: @escaping (CGFloat) -> Void) -> some View {
        view.fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { update($0) }
    }
}
