import SwiftUI
import Translation

/// iPhone 的根界面：左边是抽屉，右边是会话。拉开抽屉时会话整体被推到右边。
struct ConversationRootView: View {
    @StateObject private var controller = ConversationController()
    @State private var drawerOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var sheet: RootSheet?

    enum RootSheet: Identifiable {
        case settings, newSession, newScene, editScene(UUID), editList, starred

        var id: String {
            switch self {
            case .settings: "settings"
            case .newSession: "newSession"
            case .newScene: "newScene"
            case .editScene(let id): "scene-" + id.uuidString
            case .editList: "editList"
            case .starred: "starred"
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(320, geometry.size.width * 0.82)
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let offset = drawerOpen ? max(0, drawerWidth + dragOffset) : max(0, dragOffset)

            ZStack(alignment: .topLeading) {
                DrawerView(controller: controller, store: controller.store,
                           onSelect: { setDrawer(false) },
                           onAction: handle)
                    .frame(width: drawerWidth)

                ConversationView(controller: controller, store: controller.store, screenHeight: fullHeight,
                                 onMenu: { setDrawer(true) },
                                 onNewSession: { sheet = .newSession },
                                 onSettings: { sheet = .settings })
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background { WashBackground() }
                    // 遮罩要盖住状态栏和底部安全区，背景才能一直铺满
                    .mask { RoundedRectangle(cornerRadius: offset > 0 ? 36 : 0).ignoresSafeArea() }
                    .shadow(color: .black.opacity(offset > 0 ? 0.18 : 0), radius: 24, x: -6)
                    .overlay {
                        if drawerOpen {
                            Color.black.opacity(0.06)
                                .clipShape(.rect(cornerRadius: 36))
                                .contentShape(.rect)
                                .onTapGesture { setDrawer(false) }
                                .accessibilityLabel("关闭会话列表")
                        }
                    }
                    .offset(x: offset)
                    .simultaneousGesture(dragGesture(drawerWidth: drawerWidth))
            }
        }
        .tint(.lxAccent)
        .translationTask(controller.translator.configuration) { session in
            await controller.translator.run(session)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings: SettingsView()
            case .newSession: NewSessionView(controller: controller, store: controller.store)
            case .newScene: SceneEditorView(store: controller.store, sceneID: nil)
            case .editScene(let id): SceneEditorView(store: controller.store, sceneID: id)
            case .editList: ListEditView(store: controller.store)
            case .starred: StarredWordsView { word in
                self.sheet = nil
                setDrawer(false)
                controller.draft = word
                controller.send()
            }
            }
        }
    }

    private func handle(_ action: DrawerAction) {
        switch action {
        case .newSession:
            sheet = .newSession
        case .newScene: sheet = .newScene
        case .editScene(let id): sheet = .editScene(id)
        case .editList: sheet = .editList
        case .starred: sheet = .starred
        case .settings: sheet = .settings
        }
    }

    private func setDrawer(_ open: Bool) {
        if open {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        withAnimation(.snappy(duration: 0.3)) {
            drawerOpen = open
            dragOffset = 0
        }
    }

    /// 从屏幕左边缘向右滑拉开；拉开后向左滑收起
    private func dragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if drawerOpen {
                    dragOffset = min(0, value.translation.width)
                } else if value.startLocation.x < 32 {
                    dragOffset = min(drawerWidth, max(0, value.translation.width))
                }
            }
            .onEnded { value in
                if drawerOpen {
                    setDrawer(value.translation.width > -60)
                } else if value.startLocation.x < 32 {
                    setDrawer(value.translation.width > 60)
                } else {
                    setDrawer(false)
                }
            }
    }
}
