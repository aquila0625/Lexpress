import SwiftUI

/// 内容的种类，用来筛选，也决定每一轮长什么样
enum TurnKind: CaseIterable {
    case word, sentence, image

    var title: String {
        switch self {
        case .word: "单词"
        case .sentence: "句子"
        case .image: "图片"
        }
    }
}

extension Turn {
    var kind: TurnKind {
        if isImage { return .image }
        if word != nil { return .word }
        return .sentence
    }
}

/// 会话里的一轮。每种内容有固定的样子，看一眼就分得清：
/// 单词是一张小词卡；句子的原文缩成灰色小气泡，译文是主角；图片是缩略图加译文。
/// 操作按钮只在最新一轮和被点选的那一轮出现。
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
    /// 显示操作按钮（最新一轮，或者被点选的那一轮）
    var showsActions = false
    /// 点一下这一轮：选中它，显示操作按钮
    var onSelect: () -> Void = {}

    @State private var editText = ""
    @State private var copied = false
    @State private var showBefore = false
    @AppStorage(SettingsKey.showAIUsage) private var showUsage = false

    private var editing: Bool { editingTurn == turn.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if turn.isImage {
                imageSource
            } else if editing {
                editor
            } else if turn.word == nil {
                // 单词直接显示成词卡，不再重复一个原文气泡
                textSource
            }
            if let tags {
                Text(tags)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            result
                .opacity(editing ? 0.4 : 1)
        }
    }

    /// 只在手动指定方向或改过原文时才标出来，平时不显示
    private var tags: String? {
        var parts: [String] = []
        if turn.manualDirection { parts.append(turn.sourceIsChinese ? "中 → 英 · 手动" : "英 → 中 · 手动") }
        if turn.edited { parts.append("已编辑") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: 原文

    private var textSource: some View {
        FoldableText(text: turn.source, font: .system(size: 14), expanded: expanded, alignment: .trailing,
                     foldedLines: 2, onToggle: onToggleExpand)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.lxSurface, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                                                     bottomTrailingRadius: 4, topTrailingRadius: 14))
            .contextMenu { sourceMenu }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 56)
    }

    @ViewBuilder
    private var sourceMenu: some View {
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
        VStack(alignment: .trailing, spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(turn.images.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, index: index)
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            Text("\(turn.images.count) 张图片" + (turn.state == .working ? " · 识别中" : ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 56)
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
            .frame(width: 64, height: 82)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                Text("图 \(index + 1)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: .rect(cornerRadius: 5))
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("图 \(index + 1)，点按编辑")
        .overlay(alignment: .topTrailing) {
            Button { controller.deleteImage(turn.id, item.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
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
            working("翻译中…")
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
                CompactWordCard(entry: entry) { onOpenWord(entry) }
                    .contextMenu { sourceMenu }
            } else if let sentence = turn.sentence {
                sentenceResult(sentence)
            }
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(minHeight: 28)
    }

    /// 几张图的译文合在一起显示，长了折叠
    private var imageResults: some View {
        let allDone = turn.images.allSatisfy(\.done)
        let all = turn.images.count == 1 ? (turn.images.first?.translation ?? "")
            : turn.images.enumerated().filter { $0.element.done }
                .map { "图 \($0.offset + 1)：\($0.element.translation)" }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 6) {
            if !all.isEmpty {
                FoldableText(text: all, font: .system(size: 17, weight: .medium), lineSpacing: 3,
                             expanded: expanded, onToggle: onToggleExpand)
                    .contentShape(.rect)
                    .onTapGesture(perform: onSelect)
            }
            if !allDone { working("识别和翻译中…") }
            if showsActions, turn.state == .done {
                actionBar {
                    SpeakButton(speech: .text(all, isChinese: !(turn.images.first?.recognized.isMostlyChinese ?? false)))
                        .frame(width: 44, height: 44)
                    iconButton(copied ? "checkmark" : "doc.on.doc", "复制全部译文") {
                        Clipboard.copy(all)
                        copied = true
                    }
                }
            }
        }
    }

    private func sentenceResult(_ sentence: SentenceResult) -> some View {
        // 单词和短语查不到词典时也走机器翻译，但不提供 AI 优化：AI 只针对一句话
        let isSentence = !ConversationController.isWordLike(sentence.source)
        let waitingForAI = turn.isOptimizing && !sentence.showsAI
        // 用了 AI 只在句尾标一个小小的“AI”，不再单独一行标签
        let badge = sentence.showsAI ? Text("\(Image(systemName: "sparkles"))AI").font(.caption2.weight(.bold)).foregroundStyle(Color.lxAI) : nil
        return VStack(alignment: .leading, spacing: 8) {
            if waitingForAI {
                // 开着 AI 优化时不先显示机器翻译，等优化好了直接显示结果
                working("AI 优化中…")
            } else {
                FoldableText(text: sentence.displayed, font: .system(size: 18, weight: .medium), lineSpacing: 4,
                             expanded: expanded, badge: badge, onToggle: onToggleExpand)
                    .contentShape(.rect)
                    .onTapGesture(perform: onSelect)
            }
            if let error = turn.aiError {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.lxAI)
            }
            if showsActions {
                if sentence.showsAI {
                    if sentence.aiTranslation != sentence.translation {
                        // 优化前的译文默认折叠
                        Button {
                            withAnimation(.snappy) { showBefore.toggle() }
                        } label: {
                            Label(showBefore ? "收起优化前" : "查看优化前的译文", systemImage: showBefore ? "chevron.up" : "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minHeight: 32)
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
                    }
                    if showUsage {
                        Text([sentence.aiModel, sentence.aiUsage?.summary].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.lxAI)
                    }
                }
                actionBar {
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
                    if isSentence || sentence.showsAI {
                        Divider().frame(height: 20).padding(.horizontal, 4)
                        aiChip(on: sentence.showsAI)
                        if sentence.showsAI, !turn.isOptimizing {
                            iconButton("arrow.clockwise", "重新用 AI 优化", tint: .lxAI) {
                                AISettings.shared.isConfigured ? controller.reoptimize(turn.id) : onNeedAI()
                            }
                        }
                    }
                }
                if !sentence.showsAI {
                    Text("译文来自" + sentence.engine).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            if controller.offlineDownloadable, sentence.engine == OnlineTranslator.name, showsActions {
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

    private func actionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.leading, -12)
            .transition(.opacity)
    }

    /// “AI 优化”开关：点一下用 AI 优化，再点一下回到机器翻译；之前优化过的结果会保留，打开时不用重新请求
    private func aiChip(on: Bool) -> some View {
        Button {
            let sentence = turn.sentence
            AISettings.shared.isConfigured || sentence?.aiTranslation != nil ? controller.toggleAI(turn.id) : onNeedAI()
        } label: {
            Label("AI", systemImage: on ? "sparkles" : "sparkle")
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

/// 会话里的小词卡：蓝色书本图标、白底蓝边，单词加粗，下面一行第一个释义；点开看完整词条
struct CompactWordCard: View {
    let entry: WordEntry
    let onOpen: () -> Void

    private var phonetic: String? {
        if entry.isChinese { return entry.pinyin }
        let preferred = entry.phonetics.first { $0.accent == Speaker.defaultAccent } ?? entry.phonetics.first
        return preferred.map { "/\($0.ipa)/" }
    }

    private var meaning: String {
        if let sense = entry.senses.first { return [sense.pos, sense.meaning].compactMap { $0 }.joined(separator: " ") }
        return entry.definitions.first?.text ?? entry.webMeanings.first ?? ""
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.lxAccent, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.word)
                        .font(entry.isChinese ? .system(size: 19, weight: .bold) : .system(size: 20, weight: .bold, design: .serif))
                        .lineLimit(1)
                    if let phonetic {
                        Text(phonetic).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Text(meaning).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            SpeakButton(speech: entry.isChinese ? .chinese(entry.word) : .english(entry.word))
                .frame(width: 40, height: 44)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(Color.lxBackground, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.lxAccent.opacity(0.3), lineWidth: 1.5) }
        .shadow(color: Color.lxAccent.opacity(0.1), radius: 5, y: 3)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("打开完整词条")
    }
}

/// 超过几行时折叠；只有真的放不下时才出现“展开全文 / 收起”
struct FoldableText: View {
    let text: String
    let font: Font
    var lineSpacing: CGFloat = 0
    let expanded: Bool
    var alignment: HorizontalAlignment = .leading
    var foldedLines = 4
    /// 接在文字末尾的小标记，例如“AI”
    var badge: Text?
    let onToggle: () -> Void

    @State private var fullHeight: CGFloat = 0
    @State private var foldedHeight: CGFloat = 0

    private var content: Text {
        if let badge { return Text("\(Text(text))  \(badge)") }
        return Text(text)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            styled(content)
                .lineLimit(expanded ? nil : foldedLines)
                .textSelection(.enabled)
                .background(alignment: .topLeading) {
                    // 量一下完整高度和折叠后的高度，判断是不是真的被截断
                    ZStack(alignment: .topLeading) {
                        measured(styled(content)) { fullHeight = $0 }
                        measured(styled(content).lineLimit(foldedLines)) { foldedHeight = $0 }
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }
            if fullHeight > foldedHeight + 1 {
                Button(action: onToggle) {
                    Label(expanded ? "收起" : "展开全文", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 32)
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
