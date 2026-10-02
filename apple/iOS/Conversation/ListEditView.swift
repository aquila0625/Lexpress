import SwiftUI

/// 编辑会话列表：拖动会话排序，拖到别的场景标题下面就移到那个场景；场景本身也可以排序。
struct ListEditView: View {
    @ObservedObject var store: ConversationStore

    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var editingScene: SceneGroup?

    /// 会话页里的一行：场景标题（不能拖）或会话
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
        NavigationStack {
            List {
                if tab == 0 {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let scene):
                            HStack(spacing: 10) {
                                SceneCoverView(cover: scene?.cover, size: 30)
                                Text(scene?.name ?? "未分类").font(.headline)
                            }
                            .moveDisabled(true)
                            .deleteDisabled(true)
                            .listRowBackground(Color.lxSurface)
                        case .session(let session):
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title).lineLimit(1)
                                Text(session.lastSnippet).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.leading, 12)
                        }
                    }
                    .onMove(perform: moveSessions)
                    .onDelete(perform: deleteSessions)
                } else {
                    ForEach(store.scenes) { scene in
                        Button {
                            editingScene = scene
                        } label: {
                            HStack(spacing: 10) {
                                SceneCoverView(cover: scene.cover, size: 34)
                                VStack(alignment: .leading) {
                                    Text(scene.name)
                                    Text("\(store.sessions(in: scene.id).count) 个会话").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { store.moveScenes(from: $0, to: $1) }
                    .onDelete { offsets in offsets.map { store.scenes[$0].id }.forEach(store.deleteScene) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .safeAreaInset(edge: .top) {
                Picker("编辑", selection: $tab) {
                    Text("会话").tag(0)
                    Text("场景").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .navigationTitle("编辑列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Text(tab == 0 ? "拖动右侧把手排序；拖到另一个场景标题下面，就移到那个场景。" : "拖动排序，点场景改名称和封面。删除场景不会删除里面的会话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .sheet(item: $editingScene) { scene in
                SceneEditorView(store: store, sceneID: scene.id)
            }
        }
        .tint(.lxAccent)
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
