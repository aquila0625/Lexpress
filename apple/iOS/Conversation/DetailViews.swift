import SwiftUI

/// 完整词条。传入 entry 时直接显示，否则按 word 去查。
struct WordDetailView: View {
    let word: String
    var entry: WordEntry?
    /// 点词组、同根词时：在当前会话里查这个词
    let onLookup: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loaded: WordEntry?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let current = entry ?? loaded {
                    WordView(entry: current, onLookup: onLookup, wide: false)
                        .padding(20)
                } else if failed {
                    ContentUnavailableView("查不到这个词", systemImage: "exclamationmark.magnifyingglass",
                                           description: Text("请检查网络后重试"))
                        .padding(.top, 80)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .background(Color.lxBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task {
                guard entry == nil, loaded == nil else { return }
                loaded = try? await Youdao.lookup(word).entry
                failed = loaded == nil
            }
        }
        .tint(.lxAccent)
    }
}

/// 生词本：加了星标的词
struct StarredWordsView: View {
    /// 在当前会话里查这个词
    let onLookup: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var history = HistoryStore.shared

    var body: some View {
        NavigationStack {
            List {
                ForEach(history.starred) { item in
                    NavigationLink(value: item.text) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.text).font(.body.weight(.semibold))
                            Text(item.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button("移除", role: .destructive) { history.toggleStar(item.text) }
                    }
                }
            }
            .overlay {
                if history.starred.isEmpty {
                    ContentUnavailableView("生词本是空的", systemImage: "star",
                                           description: Text("在词典卡片上点星标，就能把词加进来。"))
                }
            }
            .navigationDestination(for: String.self) { word in
                WordDetailView(word: word, onLookup: onLookup)
            }
            .navigationTitle("生词本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .tint(.lxAccent)
    }
}

/// 编辑一张图片：旋转后重新识别这一张，或删除它和它的译文
struct ImageEditView: View {
    @ObservedObject var controller: ConversationController
    @ObservedObject var store: ConversationStore
    let turnID: UUID
    let imageID: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let turn = store.turn(controller.currentID, turnID)
        let index = turn?.images.firstIndex { $0.id == imageID }
        let item = index.flatMap { turn?.images[$0] }
        NavigationStack {
            VStack(spacing: 16) {
                if let item, let image = store.image(named: item.fileName) {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if item.done {
                        Text(item.recognized.isEmpty ? "没有识别到文字" : item.recognized)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(4)
                            .padding(.horizontal)
                    } else {
                        ProgressView("重新识别中…").tint(.white).foregroundStyle(.white)
                    }
                } else {
                    Spacer()
                }
                HStack(spacing: 12) {
                    Button { controller.rotateImage(turnID, imageID) } label: {
                        Label("旋转", systemImage: "rotate.right").frame(minHeight: 44)
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) {
                        controller.deleteImage(turnID, imageID)
                        dismiss()
                    } label: {
                        Label("删除这张", systemImage: "trash").frame(minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.bottom, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(index.map { "图 \($0 + 1) / \(turn?.images.count ?? 0)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: item == nil) { if item == nil { dismiss() } }
    }
}
