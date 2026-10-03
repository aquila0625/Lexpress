import AppKit
import SwiftUI

/// 点菜单栏图标弹出的小面板：上面一个输入框，中间是常用功能的图标格子，下面是几个开关。
/// 右键点图标仍然是文字菜单。
@MainActor
final class MenuBarState: ObservableObject {
    @Published var draft = ""
    @Published var hasAccessibility = false
    @Published var watchClipboard = false
    @Published var hideDockIcon = false
    @Published var launchAtLogin = false
    /// 每次弹出时加一，让输入框获得焦点
    @Published var focusRequest = 0
}

/// 面板上的每个操作都交回给 StatusBarController 去做
struct MenuBarActions {
    let translateText: (String) -> Void
    let selection: () -> Void
    let replace: () -> Void
    let clipboard: () -> Void
    let screenshot: () -> Void
    let recognize: () -> Void
    let mainWindow: () -> Void
    let settings: () -> Void
    let quit: () -> Void
    let requestPermission: () -> Void
    let setWatchClipboard: (Bool) -> Void
    let setHideDockIcon: (Bool) -> Void
    let setLaunchAtLogin: (Bool) -> Void
}

struct MenuBarView: View {
    @ObservedObject var state: MenuBarState
    let actions: MenuBarActions

    @FocusState private var focused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "translate")
                    .foregroundStyle(Color.lxAccent)
                Text("Q-Translator").font(.headline)
                Text("快译").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                iconButton("gearshape", help: "设置", action: actions.settings)
                iconButton("power", help: "退出 Q-Translator", action: actions.quit)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("输入要翻译的文字，回车", text: $state.draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        let text = state.draft.trimmed
                        guard !text.isEmpty else { return }
                        state.draft = ""
                        actions.translateText(text)
                    }
                Text("⌥A").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 9))

            LazyVGrid(columns: columns, spacing: 8) {
                Tile(title: "划词翻译", key: "⌥F", symbol: "text.cursor", action: actions.selection)
                Tile(title: "翻译并替换", key: "⌥R", symbol: "arrow.left.arrow.right", action: actions.replace)
                Tile(title: "翻译剪贴板", key: "⌥V", symbol: "doc.on.clipboard", action: actions.clipboard)
                Tile(title: "截图翻译", key: "⌥S", symbol: "camera.viewfinder", action: actions.screenshot)
                Tile(title: "截图识字", key: "只复制文字", symbol: "text.viewfinder", action: actions.recognize)
                Tile(title: "主窗口", key: "⌥D", symbol: "macwindow", action: actions.mainWindow)
            }

            if !state.hasAccessibility {
                Button(action: actions.requestPermission) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(Color.lxAI)
                        Text("划词和替换需要“辅助功能”权限").foregroundStyle(.primary)
                        Spacer()
                        Text("去开启").foregroundStyle(Color.lxAccent)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.lxAISoft, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(spacing: 6) {
                toggle("剪贴板自动翻译", isOn: state.watchClipboard, set: actions.setWatchClipboard,
                       help: "每复制一段文字或一张图片，就在鼠标旁边显示译文")
                toggle("只在菜单栏显示", isOn: state.hideDockIcon, set: actions.setHideDockIcon,
                       help: "隐藏程序坞里的图标")
                toggle("登录时自动启动", isOn: state.launchAtLogin, set: actions.setLaunchAtLogin, help: nil)
            }
        }
        .padding(14)
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .tint(.lxAccent)
        .onChange(of: state.focusRequest) { focused = true }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func toggle(_ title: String, isOn: Bool, set: @escaping (Bool) -> Void, help: String?) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .help(help ?? "")
    }
}

/// 一个功能格子：图标、名称、快捷键
private struct Tile: View {
    let title: String
    let key: String
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.lxAccent)
                    .frame(height: 22)
                Text(title).font(.system(size: 12, weight: .medium))
                Text(key).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(hovering ? Color.lxAccentSoft : Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 面板窗口：不激活 App（别的 App 里选中的文字保持选中），可以打字，Esc 关闭
final class MenuBarPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = .preferredContentSize
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// 贴在菜单栏图标正下方
    func show(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        contentViewController?.view.layoutSubtreeIfNeeded()
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = frame.size
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 6)
        if let visible = buttonWindow.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }
}
