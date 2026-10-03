import SwiftUI

enum DrawerAction {
    case newSession, editScene(UUID), newScene, starred, settings
}

/// 抽屉：搜索、生词本和编辑，两层的场景和会话列表，底部是设置和新建。
/// 平时长按会话就能拖到别的位置或别的场景；点“编辑”出现拖动把手。
struct DrawerView: View {
    @ObservedObject var controller: ConversationController
    @ObservedObject var store: ConversationStore
    let onSelect: () -> Void
    let onAction: (DrawerAction) -> Void

    @AppStorage("drawer.collapsed") private var collapsedRaw = ""
    @State private var query = ""
    @State private var editing = false
    @State private var renaming: ChatSession?
    @State private var renameText = ""
    @State private var deleting: ChatSession?
    @State private var dropTarget: String?
    /// 拖着会话停在哪个场景上；停够 1 秒后 armedScene 就是它，标题高亮并自动展开
    @State private var hoverScene: String?
    @State private var armedScene: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !editing {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索会话和翻译", text: $query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.lxSurface, in: .capsule)
            }

            HStack(spacing: 4) {
                if !editing {
                    Button { onAction(.starred) } label: {
                        Label("生词本", systemImage: "star")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("拖动排序，或拖到别的场景下面").font(.footnote).foregroundStyle(.secondary).padding(.leading, 6)
                }
                Spacer()
                Button(editing ? "完成" : "编辑") {
                    withAnimation(.snappy) { editing.toggle() }
                }
                .font(.callout.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
            }

            if editing {
                DrawerEditList(store: store, onEditScene: { onAction(.editScene($0)) }, onNewScene: { onAction(.newScene) })
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        if query.trimmed.isEmpty {
                            ForEach(store.scenes) { sceneSection($0) }
                            unsortedSection
                        } else {
                            searchResults
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Divider()
            HStack {
                Button { onAction(.settings) } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { onAction(.newSession) } label: {
                    Label("新建", systemImage: "square.and.pencil")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.lxOnAccent)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Color.lxAccent, in: .capsule)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新建会话")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.lxBackground)
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

    private func setCollapsed(_ scene: SceneGroup?, _ collapsed: Bool) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if collapsed { set.insert(key(scene)) } else { set.remove(key(scene)) }
        collapsedRaw = set.joined(separator: ",")
    }

    private func sceneSection(_ scene: SceneGroup) -> some View {
        let sessions = store.sessions(in: scene.id)
        let collapsed = isCollapsed(scene)
        return Section {
            if !collapsed {
                ForEach(sessions) { sessionRow($0) }
                if sessions.isEmpty {
                    // 空场景也能把会话拖进来
                    Text(armedScene == key(scene) ? "松手放进“\(scene.name)”" : "还没有会话，点右边的 + 新建，或把会话拖到这里")
                        .font(.footnote)
                        .foregroundStyle(armedScene == key(scene) ? Color.lxAccent : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.leading, 18)
                        .background(armedScene == key(scene) ? Color.lxAccentSoft : Color.clear, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                        .dropDestination(for: String.self) { items, _ in
                            drop(items, into: scene, before: nil)
                        } isTargeted: { hover(scene, $0) }
                }
            }
        } header: {
            sceneHeader(scene, count: sessions.count, collapsed: collapsed)
        }
    }

    /// 不属于任何场景的会话：放在最下面，不显示“未分类”标题
    @ViewBuilder
    private var unsortedSection: some View {
        let sessions = store.sessions(in: nil)
        if !sessions.isEmpty {
            Section {
                ForEach(sessions) { sessionRow($0) }
            } header: {
                // 空白的吸顶标题：滑到这里时把上一个场景的标题顶走，免得看起来像属于那个场景
                Color.lxBackground.frame(height: store.scenes.isEmpty ? 0 : 14)
            }
        }
    }

    // MARK: 拖动

    private func drop(_ items: [String], into scene: SceneGroup?, before target: UUID?) -> Bool {
        guard let id = items.first.flatMap(UUID.init), id != target else { return false }
        withAnimation(.snappy) { store.moveSession(id, toScene: scene?.id, before: target) }
        if let scene { setCollapsed(scene, false) }
        hoverScene = nil
        armedScene = nil
        return true
    }

    /// 拖着会话停在某个场景上 1 秒：高亮这个场景、自动展开，表示可以放进去
    private func hover(_ scene: SceneGroup?, _ inside: Bool) {
        let k = key(scene)
        if inside {
            guard hoverScene != k else { return }
            hoverScene = k
            armedScene = nil
            Task {
                try? await Task.sleep(for: .seconds(1))
                guard hoverScene == k else { return }
                withAnimation(.snappy) {
                    armedScene = k
                    setCollapsed(scene, false)
                }
            }
        } else if hoverScene == k {
            hoverScene = nil
            armedScene = nil
        }
    }

    /// 场景标题：点左边展开或收起；右边是“在这个场景里新建会话”和“编辑场景”。往上滑时吸在顶部。
    private func sceneHeader(_ scene: SceneGroup, count: Int, collapsed: Bool) -> some View {
        let armed = armedScene == key(scene)
        return HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { setCollapsed(scene, !collapsed) }
            } label: {
                HStack(spacing: 10) {
                    SceneCoverView(cover: scene.cover)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(scene.name).font(.callout.weight(.bold)).lineLimit(1)
                        Text(armed ? "松手放进这个场景" : "\(count) 个会话")
                            .font(.caption)
                            .foregroundStyle(armed ? Color.lxAccent : .secondary)
                    }
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(collapsed ? "展开" : "收起")

            Button {
                controller.newSession(sceneID: scene.id)
                onSelect()
            } label: {
                Image(systemName: "plus").frame(width: 40, height: 44)
            }
            .accessibilityLabel("在\(scene.name)里新建会话")

            Button { onAction(.editScene(scene.id)) } label: {
                Image(systemName: "ellipsis").frame(width: 40, height: 44)
            }
            .accessibilityLabel("编辑场景\(scene.name)")
        }
        .padding(.horizontal, 6)
        .background(armed ? Color.lxAccentSoft : Color.lxBackground, in: .rect(cornerRadius: 14))
        .overlay {
            if armed { RoundedRectangle(cornerRadius: 14).stroke(Color.lxAccent, lineWidth: 2) }
        }
        .contentShape(.rect)
        // 把会话拖到场景标题上：移到这个场景的最上面
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: scene, before: nil)
        } isTargeted: { hover(scene, $0) }
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
            .background(rowBackground(session), in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // 长按拖动：放到另一个会话上就排在它前面，并进入它所在的场景
        .draggable(session.id.uuidString) {
            Text(session.title)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.lxAccentSoft, in: .capsule)
        }
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: store.scene(session.sceneID), before: session.id)
        } isTargeted: { inside in
            dropTarget = inside ? "s-" + session.id.uuidString : (dropTarget == "s-" + session.id.uuidString ? nil : dropTarget)
            if let scene = store.scene(session.sceneID) { hover(scene, inside) }
        }
        .contextMenu {
            Button("重命名", systemImage: "pencil") {
                renameText = session.title
                renaming = session
            }
            Menu("移到场景", systemImage: "folder") {
                Button("不放进场景") { store.moveSession(session.id, toScene: nil, before: nil) }
                ForEach(store.scenes) { scene in
                    Button(scene.name) { store.moveSession(session.id, toScene: scene.id, before: nil) }
                }
            }
            Button("删除", systemImage: "trash", role: .destructive) { deleting = session }
        }
    }

    private func rowBackground(_ session: ChatSession) -> Color {
        if dropTarget == "s-" + session.id.uuidString { return Color.lxAccentSoft.opacity(0.6) }
        return session.id == controller.currentID ? Color.lxAccentSoft : Color.clear
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
}

/// 抽屉的编辑状态：会话和场景都出现拖动把手。会话拖到哪个场景标题下面，就归到那个场景。
struct DrawerEditList: View {
    @ObservedObject var store: ConversationStore
    let onEditScene: (UUID) -> Void
    let onNewScene: () -> Void

    @State private var tab = 0

    private enum Row: Identifiable {
        case header(SceneGroup?)
        case session(ChatSession)

        var id: String {
            switch self {
            case .header(let scene): "h-" + (scene?.id.uuidString ?? "none")
            case .session(let session): "s-" + session.id.uuidString
            }
        }
    }

    /// 和抽屉里一样的顺序：各个场景，最后是未分类
    private var rows: [Row] {
        var result: [Row] = []
        for scene in store.scenes {
            result.append(.header(scene))
            result += store.sessions(in: scene.id).map(Row.session)
        }
        result.append(.header(nil))
        result += store.sessions(in: nil).map(Row.session)
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            Picker("编辑", selection: $tab) {
                Text("会话").tag(0)
                Text("场景").tag(1)
            }
            .pickerStyle(.segmented)

            List {
                if tab == 0 {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let scene):
                            HStack(spacing: 10) {
                                SceneCoverView(cover: scene?.cover, size: 28)
                                Text(scene?.name ?? "不在场景里").font(.callout.weight(.bold))
                            }
                            .moveDisabled(true)
                            .deleteDisabled(true)
                            .listRowBackground(Color.lxSurface)
                        case .session(let session):
                            Text(session.title).font(.callout).lineLimit(1).padding(.leading, 10)
                        }
                    }
                    .onMove(perform: moveSessions)
                    .onDelete(perform: deleteSessions)
                } else {
                    ForEach(store.scenes) { scene in
                        HStack(spacing: 10) {
                            SceneCoverView(cover: scene.cover, size: 30)
                            Text(scene.name).font(.callout)
                            Spacer()
                            Button { onEditScene(scene.id) } label: {
                                Image(systemName: "pencil").frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("编辑\(scene.name)的名称和图标")
                        }
                    }
                    .onMove { store.moveScenes(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { store.scenes[$0].id }.forEach(store.deleteScene) }

                    Button { onNewScene() } label: {
                        Label("新建场景", systemImage: "plus")
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        }
    }

    private func moveSessions(from source: IndexSet, to destination: Int) {
        var list = rows
        list.move(fromOffsets: source, toOffset: destination)
        // 每个会话归到它上方最近的那个场景标题
        var currentScene: UUID?
        if case .header(let first)? = list.first { currentScene = first?.id }
        var order: [(sessionID: UUID, sceneID: UUID?)] = []
        for row in list {
            switch row {
            case .header(let scene): currentScene = scene?.id
            case .session(let session): order.append((session.id, currentScene))
            }
        }
        store.applyOrder(order)
    }

    private func deleteSessions(at offsets: IndexSet) {
        let list = rows
        for i in offsets {
            if case .session(let session) = list[i] { store.deleteSession(session.id) }
        }
    }
}
