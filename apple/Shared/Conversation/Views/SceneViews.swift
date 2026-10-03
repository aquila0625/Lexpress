import SwiftUI

/// 场景封面的配色：浅色底 + 深色图标
enum ScenePalette {
    static let colors: [(background: Color, foreground: Color)] = [
        (Color(light: 0xDCEBFF, dark: 0x12305A), Color(light: 0x0A58C9, dark: 0x8CC0FF)),
        (Color(light: 0xE3F5EA, dark: 0x123322), Color(light: 0x1E7A45, dark: 0x7FD6A3)),
        (Color(light: 0xFFEEDD, dark: 0x3A2210), Color(light: 0xB8430A, dark: 0xFFAE78)),
        (Color(light: 0xDDF3F2, dark: 0x0F3331), Color(light: 0x0B6B66, dark: 0x6FD3CC)),
        (Color(light: 0xFFF4D6, dark: 0x3A2E0C), Color(light: 0x8A5A00, dark: 0xF2C14E)),
        (Color(light: 0xECEEF2, dark: 0x262A30), Color(light: 0x4A5565, dark: 0xAEB8C4)),
    ]

    static func color(_ index: Int) -> (background: Color, foreground: Color) {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

/// 场景封面小方块
struct SceneCoverView: View {
    let cover: SceneCover?
    var size: CGFloat = 40

    var body: some View {
        let palette = ScenePalette.color(cover?.palette ?? 5)
        Image(systemName: cover?.symbol ?? "tray.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(palette.foreground)
            .frame(width: size, height: size)
            .background(palette.background, in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// 新建或编辑场景：名称和封面
struct SceneEditorView: View {
    @ObservedObject var store: ConversationStore
    /// nil 表示新建
    let sceneID: UUID?
    var onCreated: (SceneGroup) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = SceneCover.symbols[0]
    @State private var palette = 0
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("场景名称") {
                    TextField("例如：教室、户外交流、租房", text: $name)
                }
                Section("封面") {
                    HStack {
                        Spacer()
                        SceneCoverView(cover: SceneCover(symbol: symbol, palette: palette), size: 72)
                        Spacer()
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(SceneCover.symbols, id: \.self) { item in
                            Button {
                                symbol = item
                            } label: {
                                Image(systemName: item)
                                    .font(.system(size: 18))
                                    .frame(width: 44, height: 44)
                                    .background(item == symbol ? Color.lxAccentSoft : Color.clear, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item)
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(ScenePalette.colors.indices, id: \.self) { i in
                            Button {
                                palette = i
                            } label: {
                                Circle()
                                    .fill(ScenePalette.colors[i].foreground)
                                    .frame(width: 30, height: 30)
                                    .overlay { if i == palette { Circle().stroke(Color.primary, lineWidth: 2).padding(-4) } }
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("配色 \(i + 1)")
                        }
                    }
                }
                if sceneID != nil {
                    Section {
                        Button("删除场景", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("删除场景不会删除里面的会话，它们会移到列表最下面。")
                    }
                }
            }
            .navigationTitle(sceneID == nil ? "新建场景" : "编辑场景")
            .inlineNavigationTitle()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button(sceneID == nil ? "创建" : "保存") { save() }
                        .disabled(name.trimmed.isEmpty)
                }
            }
            .confirmationDialog("删除这个场景？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除场景，会话移到最下面", role: .destructive) {
                    if let sceneID { store.deleteScene(sceneID) }
                    dismiss()
                }
            } message: {
                Text("要连同会话一起删除，请在列表里左滑场景，再勾选“同时删除会话”。")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .presentationDragIndicator(.visible)
        .tint(.lxAccent)
        .onAppear {
            if let scene = store.scene(sceneID) {
                name = scene.name
                symbol = scene.cover.symbol
                palette = scene.cover.palette
            }
        }
    }

    private func save() {
        let cover = SceneCover(symbol: symbol, palette: palette)
        if var scene = store.scene(sceneID) {
            scene.name = name.trimmed
            scene.cover = cover
            store.updateScene(scene)
        } else {
            onCreated(store.createScene(name: name, cover: cover))
        }
        dismiss()
    }
}

/// 新建会话：名称、所在场景、是否开启 AI 优化
struct NewSessionView: View {
    @ObservedObject var controller: ConversationController
    @ObservedObject var store: ConversationStore

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sceneID: UUID?
    @State private var aiEnabled = AISettings.shared.autoCalibrate
    @State private var showNewScene = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如：和老师约时间", text: $name)
                } header: {
                    Text("名称")
                } footer: {
                    Text("不填也可以，会用第一句话当名称，之后随时能改。")
                }
                Section {
                    Picker("场景", selection: $sceneID) {
                        Text("不放进场景").tag(UUID?.none)
                        ForEach(store.scenes) { scene in
                            Label(scene.name, systemImage: scene.cover.symbol).tag(Optional(scene.id))
                        }
                    }
                    Button("新建场景…") { showNewScene = true }
                }
                Section {
                    Toggle("这个会话开启 AI 优化", isOn: $aiEnabled)
                } footer: {
                    Text("开启后每次翻译句子都会用 AI 优化译文，需要先在设置里填写 API Key。")
                }
            }
            .navigationTitle("新建会话")
            .inlineNavigationTitle()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let session = store.createSession(title: name, sceneID: sceneID, aiEnabled: aiEnabled)
                        controller.select(session.id)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showNewScene) {
                SceneEditorView(store: store, sceneID: nil) { sceneID = $0.id }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
        .presentationDragIndicator(.visible)
        .tint(.lxAccent)
    }
}
