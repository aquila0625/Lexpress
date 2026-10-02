import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TranslatorModel()
    private var window: NSWindow!
    private var hotKey: HotKey?
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Lexpress 快译"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false   // 关窗只是隐藏，再次呼出不用重建
        window.minSize = NSSize(width: 420, height: 420)
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        window.setFrameAutosaveName("LexpressMainWindow.v3")

        // ⌥D 全局呼出 / 隐藏
        hotKey = HotKey(keyCode: kVK_ANSI_D, modifiers: optionKey) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }

        // Esc 隐藏；输入法正在组字时把 Esc 留给输入法，弹出的面板里的 Esc 也不拦
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape), let self, event.window === self.window,
                  self.window.attachedSheet == nil else { return event }
            if (self.window.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            NSApp.hide(nil)
            return nil
        }

        // 系统“服务”：在任意 app 里选中文字 → 右键 → 用快译翻译（端口名要和 Info.plist 的 NSPortName 一致）
        NSRegisterServicesProvider(self, "Lexpress")

        show()

        // 支持带参数启动直接查询：open -a Lexpress --args hello，或传一张图片的路径
        let query = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.joined(separator: " ")
        if let image = NSImage(contentsOfFile: query) {
            model.translateImage(image)
        } else if !query.isEmpty {
            model.lookup(query)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }

    /// 右键服务的入口，方法名对应 Info.plist 里的 NSMessage
    @objc func translateSelection(_ pasteboard: NSPasteboard, userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string)?.trimmed, !text.isEmpty else { return }
        log.info("service: received \(text.count, privacy: .public) characters")
        show()
        model.lookup(text)
    }

    /// ⌘V：剪贴板里是图片就识别并翻译，否则按普通文字粘贴
    @objc func smartPaste(_ sender: Any?) {
        // 设置、写回复等面板打开时，只做普通粘贴
        if window.attachedSheet == nil, let image = Self.image(from: .general) {
            model.translateImage(image)
        } else {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
        }
    }

    private static func image(from pasteboard: NSPasteboard) -> NSImage? {
        // 在访达里复制的图片文件
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first {
            return NSImage(contentsOf: url)
        }
        // 有纯文本就当文字粘贴：表格、幻灯片里复制文字时也会附带一张图片。
        // 网页上“拷贝图像”附带的是图片地址，这种情况仍按图片处理。
        let text = pasteboard.string(forType: .string)?.trimmed ?? ""
        if !text.isEmpty, !text.lowercased().hasPrefix("http") { return nil }
        return NSImage(pasteboard: pasteboard)
    }

    private func toggle() {
        if NSApp.isActive, window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            show()
        }
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .focusInput, object: nil)
    }

    /// 纯 AppKit 启动没有默认菜单，补上最基本的，否则 ⌘C / ⌘V / ⌘Q 不生效
    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "隐藏 Lexpress", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "退出 Lexpress", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Lexpress"))

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(smartPaste(_:)), keyEquivalent: "v").target = self
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, title: "编辑"))

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(windowMenu, title: "窗口"))

        return main
    }

    private func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
