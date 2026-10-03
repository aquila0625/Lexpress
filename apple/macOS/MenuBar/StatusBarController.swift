import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum MenuBarKey {
    /// 只在菜单栏显示，隐藏程序坞图标
    static let hideDockIcon = "menubar.hideDockIcon"
}

/// 菜单栏图标和它的菜单，以及全局快捷键：
/// ⌥F 翻译选中文字、⌥V 翻译剪贴板、⌥S 截图翻译、⌥A 输入翻译、⌥D 打开主窗口。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: QuickPanelModel
    private var panel: QuickPanel!
    private var hotKeys: [HotKey] = []
    private var failedHotKeys: [String] = []
    private var clickOutsideMonitor: Any?

    private let toggleMainWindow: () -> Void
    private let showMainWindow: () -> Void
    private let newSession: () -> Void
    private let openSettings: () -> Void

    private var permissionItem: NSMenuItem!
    private var dockItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    init(controller: ConversationController, toggleMainWindow: @escaping () -> Void, showMainWindow: @escaping () -> Void,
         newSession: @escaping () -> Void, openSettings: @escaping () -> Void) {
        model = QuickPanelModel(controller: controller)
        self.toggleMainWindow = toggleMainWindow
        self.showMainWindow = showMainWindow
        self.newSession = newSession
        self.openSettings = openSettings
        super.init()

        panel = QuickPanel(rootView: QuickPanelView(model: model, translator: controller.translator) { [weak self] in
            self?.panel.orderOut(nil)
        })
        model.openInMainWindow = { [weak self] in
            self?.panel.orderOut(nil)
            showMainWindow()
        }
        // 像弹出菜单一样，点到别的 App 就收起；固定后不收。
        // 不用“失去焦点”判断：小窗不激活 App，焦点随时可能被系统交还给原来的 App。
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.model.pinned, self.panel.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Q-Translator")
            button.image?.isTemplate = true
            button.toolTip = "Q-Translator 快译"
        }
        statusItem.menu = makeMenu()
        registerHotKeys()
    }

    // MARK: 四种快捷翻译

    func translateSelection() {
        Task {
            guard SelectionReader.hasPermission else {
                SelectionReader.requestPermission()
                return
            }
            guard let text = await SelectionReader.selectedText(), !text.isEmpty else {
                model.message = nil
                showPanel(origin: .selection, text: nil,
                          message: "没有读到选中的文字。先在别的 App 里选中一段文字，再按 ⌥F。")
                return
            }
            showPanel(origin: .selection, text: text)
        }
    }

    func translateClipboard() {
        let pasteboard = NSPasteboard.general
        if let image = Self.image(from: pasteboard) {
            model.translate(image: image, origin: .clipboard)
            panel.show(near: anchor)
        } else if let text = pasteboard.string(forType: .string)?.trimmed, !text.isEmpty {
            showPanel(origin: .clipboard, text: text)
        } else {
            showPanel(origin: .clipboard, text: nil, message: "剪贴板里没有文字或图片。")
        }
    }

    func translateScreenshot(onlyRecognize: Bool = false) {
        panel.orderOut(nil)
        Task {
            guard let image = await ScreenCapture.selectRegion() else { return }   // 按了 Esc
            model.translate(image: image, origin: onlyRecognize ? .recognize : .screenshot)
            panel.show(near: anchor)
        }
    }

    func translateInput() {
        model.startInput()
        panel.show(near: anchor)
    }

    /// 右键菜单“服务 › 用快译翻译”也走这里，就地显示结果
    func translate(text: String) {
        showPanel(origin: .selection, text: text)
    }

    private func showPanel(origin: QuickPanelModel.Origin, text: String?, message: String? = nil) {
        if let text {
            model.translate(text: text, origin: origin)
        } else {
            model.startInput()
            model.origin = origin
            model.message = message
        }
        panel.show(near: anchor)
    }

    /// 小窗出现的位置：鼠标附近
    private var anchor: NSPoint { NSEvent.mouseLocation }

    /// 剪贴板里的图片；有纯文本时按文字处理（表格、幻灯片复制文字时也会带一张图片）
    static func image(from pasteboard: NSPasteboard) -> NSImage? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first {
            return NSImage(contentsOf: url)
        }
        let text = pasteboard.string(forType: .string)?.trimmed ?? ""
        if !text.isEmpty, !text.lowercased().hasPrefix("http") { return nil }
        return NSImage(pasteboard: pasteboard)
    }

    // MARK: 快捷键

    private func registerHotKeys() {
        let keys: [(String, Int, () -> Void)] = [
            ("⌥D", kVK_ANSI_D, { [weak self] in self?.toggleMainWindow() }),
            ("⌥F", kVK_ANSI_F, { [weak self] in self?.translateSelection() }),
            ("⌥V", kVK_ANSI_V, { [weak self] in self?.translateClipboard() }),
            ("⌥S", kVK_ANSI_S, { [weak self] in self?.translateScreenshot() }),
            ("⌥A", kVK_ANSI_A, { [weak self] in self?.translateInput() }),
        ]
        for (name, keyCode, action) in keys {
            if let hotKey = HotKey(keyCode: keyCode, modifiers: optionKey, action: { Task { @MainActor in action() } }) {
                hotKeys.append(hotKey)
            } else {
                failedHotKeys.append(name)
            }
        }
    }

    // MARK: 菜单

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("翻译选中文字", key: "f", symbol: "text.cursor", action: #selector(menuSelection)))
        menu.addItem(item("翻译剪贴板", key: "v", symbol: "doc.on.clipboard", action: #selector(menuClipboard)))
        menu.addItem(item("截图翻译", key: "s", symbol: "camera.viewfinder", action: #selector(menuScreenshot)))
        menu.addItem(item("截图识字（只复制文字）", key: "", symbol: "text.viewfinder", action: #selector(menuRecognize)))
        menu.addItem(item("输入翻译…", key: "a", symbol: "keyboard", action: #selector(menuInput)))
        menu.addItem(.separator())
        menu.addItem(item("打开主窗口", key: "d", symbol: "macwindow", action: #selector(menuMainWindow)))
        menu.addItem(item("新建会话", key: "", symbol: "square.and.pencil", action: #selector(menuNewSession)))
        menu.addItem(.separator())
        permissionItem = item("开启划词翻译（需要辅助功能权限）…", key: "", symbol: "hand.raised", action: #selector(menuPermission))
        menu.addItem(permissionItem)
        dockItem = item("只在菜单栏显示", key: "", symbol: nil, action: #selector(menuToggleDock))
        menu.addItem(dockItem)
        loginItem = item("登录时自动启动", key: "", symbol: nil, action: #selector(menuToggleLogin))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("设置…", key: ",", symbol: nil, action: #selector(menuSettings), modifiers: .command))
        menu.addItem(NSMenuItem(title: "退出 Q-Translator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func item(_ title: String, key: String, symbol: String?, action: Selector,
                      modifiers: NSEvent.ModifierFlags = .option) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissionItem.isHidden = SelectionReader.hasPermission
        dockItem.state = UserDefaults.standard.bool(forKey: MenuBarKey.hideDockIcon) ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func menuSelection() { translateSelection() }
    @objc private func menuClipboard() { translateClipboard() }
    @objc private func menuScreenshot() { translateScreenshot() }
    @objc private func menuRecognize() { translateScreenshot(onlyRecognize: true) }
    @objc private func menuInput() { translateInput() }
    @objc private func menuMainWindow() { showMainWindow() }
    @objc private func menuNewSession() { newSession() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuPermission() { SelectionReader.requestPermission() }

    @objc private func menuToggleDock() {
        let hide = !UserDefaults.standard.bool(forKey: MenuBarKey.hideDockIcon)
        UserDefaults.standard.set(hide, forKey: MenuBarKey.hideDockIcon)
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        if !hide { showMainWindow() }
    }

    @objc private func menuToggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                // 系统要求用户在设置里确认一次
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
