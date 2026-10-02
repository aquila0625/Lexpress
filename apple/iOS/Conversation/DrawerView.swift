import SwiftUI

enum DrawerAction {
    case newSession, newScene, editScene(UUID), editList, starred, settings
}

/// 抽屉：搜索、新建会话、生词本、两层的场景和会话列表，最下面是用户和设置。
struct DrawerView: View {
    @ObservedObject var controller: ConversationController
    @ObservedObject var store: ConversationStore
    let onSelect: () -> Void
    let onAction: (DrawerAction) -> Void

    @AppStorage("profile.name") private var profileName = ""
    @AppStorage("drawer.collapsed") private var collapsedRaw = ""
    @State private var query = ""
    @State private var renaming: ChatSession?
    @State private var renameText = ""
    @State private var deleting: ChatSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索会话和翻译", text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color.lxSurface, in: .capsule)

            HStack(spacing: 4) {
                drawerButton("新建会话", "square.and.pencil", tint: .lxAccent) { onAction(.newSession) }
                drawerButton("生词本", "star") { onAction(.starred) }
                Spacer()
                Button("编辑") { onAction(.editList) }
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if query.trimmed.isEmpty {
                        ForEach(store.scenes) { scene in
                            sceneSection(scene)
                        }
                        let unsorted = store.sessions(in: nil)
                        if !unsorted.isEmpty || store.scenes.isEmpty {
                            sceneSection(nil)
                        }
                        drawerButton("新建场景", "plus", tint: .secondary) { onAction(.newScene) }
                            .padding(.top, 6)
                    } else {
                        searchResults
                    }
                }
            }
            .scrollIndicators(.hidden)

            Divider()
            HStack(spacing: 10) {
                Text(String(profileName.trimmed.first ?? "我"))
                    .font(.headline)
                    .foregroundStyle(Color.lxOnAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.lxAccent, in: .circle)
                    .accessibilityHidden(true)
                Text(profileName.trimmed.isEmpty ? "我的设置" : profileName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button { onAction(.settings) } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }
                .accessibilityLabel("设置")
            }
            .contentShape(.rect)
            .onTapGesture { onAction(.settings) }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.lxBackground)
        .foregroundStyle(.primary)
        .alert("重命名会话", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") { if let renaming { store.renameSession(renaming.id, to: renameText) } }
        }
        .confirmationDialog("删除这个会话？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let deleting { controller.deleteSession(deleting.id) } }
        } message: {
            Text("会话里的翻译和图片都会被删除。")
        }
    }

    // MARK: 场景分组

    private func key(_ scene: SceneGroup?) -> String { scene?.id.uuidString ?? "none" }

    private func isCollapsed(_ scene: SceneGroup?) -> Bool {
        collapsedRaw.split(separator: ",").contains(Substring(key(scene)))
    }

    private func toggle(_ scene: SceneGroup?) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        let k = key(scene)
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
        collapsedRaw = set.joined(separator: ",")
    }

    private func sceneSection(_ scene: SceneGroup?) -> some View {
        let sessions = store.sessions(in: scene?.id)
        let collapsed = isCollapsed(scene)
        return Section {
            if !collapsed {
                ForEach(sessions) { sessionRow($0) }
                if sessions.isEmpty {
                    Text("还没有会话").font(.footnote).foregroundStyle(.secondary).padding(.leading, 62).padding(.vertical, 6)
                }
            }
        } header: {
            // 往上滑时场景标题吸在顶部
            Button { withAnimation(.snappy) { toggle(scene) } } label: {
                HStack(spacing: 10) {
                    SceneCoverView(cover: scene?.cover)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene?.name ?? "未分类").font(.callout.weight(.bold))
                        Text("\(sessions.count) 个会话").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(Color.lxBackground)
            .accessibilityHint(collapsed ? "展开" : "收起")
            .contextMenu {
                if let scene {
                    Button("编辑场景", systemImage: "pencil") { onAction(.editScene(scene.id)) }
                    Button("删除场景", systemImage: "trash", role: .destructive) { store.deleteScene(scene.id) }
                }
            }
        }
    }

    private func sessionRow(_ session: ChatSession, snippet: String? = nil) -> some View {
        Button {
            controller.select(session.id)
            onSelect()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(snippet ?? session.lastSnippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(session.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(minHeight: 50)
            .background(session.id == controller.currentID ? Color.lxAccentSoft : Color.clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                renameText = session.title
                renaming = session
            }
            Menu("移到场景", systemImage: "folder") {
                Button("未分类") { store.moveSession(session.id, to: nil) }
                ForEach(store.scenes) { scene in
                    Button(scene.name) { store.moveSession(session.id, to: scene.id) }
                }
            }
            Button("删除", systemImage: "trash", role: .destructive) { deleting = session }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let q = query.trimmed.lowercased()
        let matches = store.sessions.compactMap { session -> (ChatSession, String)? in
            if session.title.lowercased().contains(q) { return (session, session.lastSnippet) }
            if let turn = session.turns.last(where: { $0.searchableText.lowercased().contains(q) }) {
                return (session, turn.outlineText)
            }
            return nil
        }
        if matches.isEmpty {
            Text("没有找到“\(query)”").font(.callout).foregroundStyle(.secondary).padding(.top, 20)
        } else {
            ForEach(matches, id: \.0.id) { session, snippet in sessionRow(session, snippet: snippet) }
        }
    }

    private func drawerButton(_ title: String, _ icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
