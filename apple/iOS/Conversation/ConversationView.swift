import SwiftUI

/// 当前会话：顶栏、一轮轮的翻译、底部输入栏。
struct ConversationView: View {
    @ObservedObject var controller: ConversationController
    @ObservedObject var store: ConversationStore
    let screenHeight: CGFloat
    let onMenu: () -> Void
    let onNewSession: () -> Void
    let onSettings: () -> Void

    @FocusState private var composerFocused: Bool
    @State private var editingTurn: UUID?
    @State private var showOutline = false
    @State private var scrollTarget: UUID?
    /// 从输入记录跳过来的那一轮，短暂高亮
    @State private var highlighted: UUID?
    /// 这次打开后新翻译的轮次默认展开；重新打开会话时长内容都收起
    @State private var expandedTurns: Set<UUID> = []
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var wordToShow: WordEntry?
    @State private var replyTo: SentenceResult?
    @State private var editingImage: ImageRef?

    struct ImageRef: Identifiable {
        let turnID: UUID
        let imageID: UUID
        var id: UUID { imageID }
    }

    var body: some View {
        let session = store.session(controller.currentID)
        VStack(spacing: 0) {
            navBar(session)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(session?.turns ?? []) { turn in
                            TurnView(turn: turn, controller: controller, editingTurn: $editingTurn,
                                     onOpenWord: { wordToShow = $0 },
                                     onReply: { replyTo = $0 },
                                     onEditImage: { editingImage = ImageRef(turnID: turn.id, imageID: $0) },
                                     onNeedAI: onSettings,
                                expanded: expandedTurns.contains(turn.id),
                                onToggleExpand: {
                                    withAnimation(.snappy) {
                                        if expandedTurns.contains(turn.id) { expandedTurns.remove(turn.id) } else { expandedTurns.insert(turn.id) }
                                    }
                                })
                                .background {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.lxAccent.opacity(highlighted == turn.id ? 0.14 : 0))
                                        .stroke(Color.lxAccent.opacity(highlighted == turn.id ? 0.6 : 0), lineWidth: 2)
                                        .padding(-10)
                                }
                                .scaleEffect(highlighted == turn.id ? 1.02 : 1)
                                .id(turn.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .defaultScrollAnchor(.bottom)
                .overlay {
                    // 空会话的提示放在可见区域中间，不随滚动贴底
                    if let session, session.turns.isEmpty {
                        emptyState(session).padding(.horizontal, 16)
                    }
                }
                .onChange(of: session?.turns.count) { old, new in
                    guard let last = session?.turns.last?.id else { return }
                    if (new ?? 0) > (old ?? 0) { expandedTurns.insert(last) }
                    withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: scrollTarget) {
                    guard let target = scrollTarget else { return }
                    scrollTarget = nil
                    Task {
                        // 等弹窗收起再滚动，然后闪一下这一轮
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { highlighted = target }
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
                    }
                }
                .onChange(of: controller.currentID) {
                    editingTurn = nil
                    expandedTurns = []
                    if let last = store.session(controller.currentID)?.turns.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let session {
                ComposerView(controller: controller, session: session, focused: $composerFocused,
                             screenHeight: screenHeight, onNeedAI: onSettings)
            }
        }
        .sheet(isPresented: $showOutline) {
            OutlineView(turns: session?.turns ?? []) { scrollTarget = $0 }
        }
        .sheet(item: Binding(get: { wordToShow.map(IdentifiedWord.init) }, set: { wordToShow = $0?.entry })) { item in
            WordSheet(word: item.entry.word, entry: item.entry) { await controller.quickTranslate($0) }
        }
        .sheet(item: Binding(get: { replyTo.map(IdentifiedSentence.init) }, set: { replyTo = $0?.result })) { item in
            ReplyView(received: item.result.source, receivedTranslation: item.result.displayed)
        }
        .fullScreenCover(item: $editingImage) { ref in
            ImageEditView(controller: controller, store: store, turnID: ref.turnID, imageID: ref.imageID)
        }
        .alert("重命名会话", isPresented: $renaming) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { store.renameSession(controller.currentID, to: renameText) }
        }
        .confirmationDialog("删除这个会话？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { controller.deleteSession(controller.currentID) }
        } message: {
            Text("会话里的翻译和图片都会被删除。")
        }
        .onAppear { composerFocused = session?.turns.isEmpty ?? true }
    }

    private func navBar(_ session: ChatSession?) -> some View {
        HStack(spacing: 8) {
            GlassIconButton(systemName: "line.3.horizontal", label: "打开会话列表") {
                composerFocused = false
                onMenu()
            }
            Menu {
                Button("重命名", systemImage: "pencil") {
                    renameText = session?.title ?? ""
                    renaming = true
                }
                Menu("移到场景", systemImage: "folder") {
                    Button("不放进场景") { store.moveSession(controller.currentID, to: nil) }
                    ForEach(store.scenes) { scene in
                        Button(scene.name) { store.moveSession(controller.currentID, to: scene.id) }
                    }
                }
                Button("删除会话", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } label: {
                HStack(spacing: 6) {
                    if let scene = store.scene(session?.sceneID) {
                        SceneCoverView(cover: scene.cover, size: 24)
                    }
                    Text(session?.title ?? "").font(.callout.weight(.semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.capsule)
            }
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("当前会话：\(session?.title ?? "")，点按重命名或移动")
            GlassIconButton(systemName: "list.bullet", label: "输入记录") { showOutline = true }
            GlassIconButton(systemName: "square.and.pencil", label: "新建会话") { onNewSession() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func emptyState(_ session: ChatSession) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "character.bubble")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.lxAccent)
                .frame(width: 68, height: 68)
                .background(Color.lxAccentSoft, in: .rect(cornerRadius: 20))
            VStack(spacing: 4) {
                Text(session.title).font(.title3.weight(.bold))
                Text("在下面输入，开始翻译").font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                tip("text.cursor", "单词、句子或整段文字都可以")
                tip("plus.circle", "点左下角的 + 拍照或选图片")
                tip("tray.full", "每次翻译都会保存在这个会话里")
            }
            .padding(16)
            .background(Color.lxSurface, in: .rect(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity)
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Color.lxAccent)
                .frame(width: 22)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct IdentifiedWord: Identifiable {
    let entry: WordEntry
    var id: String { entry.word }
}

private struct IdentifiedSentence: Identifiable {
    let result: SentenceResult
    var id: String { result.source + result.translation }
}

/// 输入记录：列出这个会话里输入过的每一条，可以搜索，点一条跳过去并高亮
struct OutlineView: View {
    let turns: [Turn]
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let q = query.trimmed.lowercased()
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    if q.isEmpty || turn.searchableText.lowercased().contains(q) {
                        Button {
                            onSelect(turn.id)
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.footnote.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(turn.outlineText).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(meta(turn)).font(.caption).foregroundStyle(.secondary)
                                        if turn.edited {
                                            Text("已编辑").font(.caption2.weight(.bold))
                                                .padding(.horizontal, 5)
                                                .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 5))
                                        }
                                    }
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .overlay {
                if turns.isEmpty { ContentUnavailableView("还没有内容", systemImage: "text.bubble") }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索输入过的内容和译文")
            .navigationTitle("输入记录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(.lxAccent)
    }

    private func meta(_ turn: Turn) -> String {
        let kind = turn.isImage ? "图片" : (turn.word != nil ? "单词" : (turn.sourceIsChinese ? "中文" : "英文"))
        return kind + " · " + turn.createdAt.formatted(date: .omitted, time: .shortened)
    }
}
