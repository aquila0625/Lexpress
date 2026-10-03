import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum MenuBarKey {
    /// 只在菜单栏显示，隐藏程序坞图标
    static let hideDockIcon = "menubar.hideDockIcon"
    /// 剪贴板自动翻译
    static let watchClipboard = "menubar.watchClipboard"
}

/// 菜单栏图标：左键弹出小面板，右键是文字菜单。还管着全局快捷键：
/// ⌥F 翻译选中文字、⌥R 翻译并替换、⌥V 翻译剪贴板、⌥S 截图翻译、⌥A 输入翻译、⌥D 打开主窗口。
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: QuickPanelModel
    private var panel: QuickPanel!
    private var hotKeys: [HotKey] = []
    private var failedHotKeys: [String] = []
    private var clickOutsideMonitor: Any?
    private var clipboardWatcher: ClipboardWatcher!
    private let menuState = MenuBarState()
    private var menuPanel: MenuBarPanel!
    private var contextMenu: NSMenu!

    private let toggleMainWindow: () -> Void
    private let showMainWindow: () -> Void
    private let newSession: () -> Void
    private let openSettings: () -> Void

    private var permissionItem: NSMenuItem!
    private var dockItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var clipboardItem: NSMenuItem!

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
                guard let self else { return }
                self.menuPanel.orderOut(nil)
                if !self.model.pinned, self.panel.isVisible { self.panel.orderOut(nil) }
            }
        }

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Q-Translator")
            button.image?.isTemplate = true
            button.toolTip = "Q-Translator 快译"
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        contextMenu = makeMenu()
        menuPanel = MenuBarPanel(rootView: MenuBarView(state: menuState, actions: makeActions()))
        registerHotKeys()

        clipboardWatcher = ClipboardWatcher { [weak self] pasteboard in self?.clipboardChanged(pasteboard) }
        if UserDefaults.standard.bool(forKey: MenuBarKey.watchClipboard) { clipboardWatcher.start() }
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

    /// 选中一段文字，翻译后直接替换成译文：中文换成英文，英文换成中文
    func translateAndReplace() {
        Task {
            guard SelectionReader.hasPermission else {
                SelectionReader.requestPermission()
                return
            }
            guard let text = await SelectionReader.selectedText(), !text.isEmpty else {
                showPanel(origin: .selection, text: nil,
                          message: "没有读到选中的文字。先在输入框里选中要替换的文字，再按 ⌥R。")
                return
            }
            guard let translated = await model.controller.quickTranslate(text)?.trimmed, !translated.isEmpty else {
                showPanel(origin: .selection, text: nil, message: "翻译失败，原文没有改动。请检查网络后重试。")
                return
            }
            await SelectionReader.paste(translated)
            log.info("replace: \(text.count, privacy: .public) -> \(translated.count, privacy: .public) chars")
        }
    }

    /// 剪贴板自动翻译：复制了文字或图片就在鼠标旁边显示译文，不抢键盘焦点
    private func clipboardChanged(_ pasteboard: NSPasteboard) {
        // 在访达里复制文件时剪贴板里是文件名，不翻译
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let text = pasteboard.string(forType: .string)?.trimmed, !text.isEmpty, fileURLs.isEmpty {
            model.translate(text: text, origin: .clipboard)
        } else if let image = Self.image(from: pasteboard) {
            model.translate(image: image, origin: .clipboard)
        } else {
            return
        }
        panel.show(near: anchor, takeFocus: false)
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
            ("⌥R", kVK_ANSI_R, { [weak self] in self?.translateAndReplace() }),
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

    // MARK: 菜单栏图标

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            menuPanel.orderOut(nil)
            statusItem.menu = contextMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if menuPanel.isVisible {
            menuPanel.orderOut(nil)
        } else if let button = statusItem.button {
            refreshMenuState()
            menuPanel.show(below: button)
            menuState.focusRequest += 1
        }
    }

    private func refreshMenuState() {
        menuState.hasAccessibility = SelectionReader.hasPermission
        menuState.watchClipboard = clipboardWatcher.isRunning
        menuState.hideDockIcon = UserDefaults.standard.bool(forKey: MenuBarKey.hideDockIcon)
        menuState.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func makeActions() -> MenuBarActions {
        // 先收起面板再做事。面板不激活 App，所以别的 App 里选中的文字还在，
        // 稍等一下让那个 App 的窗口重新拿到键盘焦点，再去读选中的文字。
        func run(_ delay: Bool = false, _ action: @escaping (StatusBarController) -> Void) -> () -> Void {
            { [weak self] in
                guard let self else { return }
                self.menuPanel.orderOut(nil)
                Task { @MainActor in
                    if delay { try? await Task.sleep(for: .milliseconds(150)) }
                    action(self)
                }
            }
        }
        return MenuBarActions(
            translateText: { [weak self] text in
                self?.menuPanel.orderOut(nil)
                self?.showPanel(origin: .input, text: text)
            },
            selection: run(true) { $0.translateSelection() },
            replace: run(true) { $0.translateAndReplace() },
            clipboard: run { $0.translateClipboard() },
            screenshot: run { $0.translateScreenshot() },
            recognize: run { $0.translateScreenshot(onlyRecognize: true) },
            mainWindow: run { $0.showMainWindow() },
            settings: run { $0.openSettings() },
            quit: { NSApp.terminate(nil) },
            requestPermission: run { _ in SelectionReader.requestPermission() },
            setWatchClipboard: { [weak self] in self?.setWatchClipboard($0) },
            setHideDockIcon: { [weak self] in self?.setHideDockIcon($0) },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) }
        )
    }

    // MARK: 开关

    private func setWatchClipboard(_ on: Bool) {
        on ? clipboardWatcher.start() : clipboardWatcher.stop()
        UserDefaults.standard.set(on, forKey: MenuBarKey.watchClipboard)
        refreshMenuState()
    }

    private func setHideDockIcon(_ hide: Bool) {
        UserDefaults.standard.set(hide, forKey: MenuBarKey.hideDockIcon)
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        refreshMenuState()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on {
                try service.register()
                // 系统要求用户在设置里确认一次
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try service.unregister()
            }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshMenuState()
    }

    // MARK: 右键菜单

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("翻译选中文字", key: "f", symbol: "text.cursor", action: #selector(menuSelection)))
        menu.addItem(item("翻译并替换选中文字", key: "r", symbol: "arrow.left.arrow.right", action: #selector(menuReplace)))
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
        clipboardItem = item("剪贴板自动翻译", key: "", symbol: nil, action: #selector(menuToggleClipboard))
        clipboardItem.toolTip = "每复制一段文字或一张图片，就在鼠标旁边显示译文"
        menu.addItem(clipboardItem)
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
        clipboardItem.state = clipboardWatcher.isRunning ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func menuSelection() { translateSelection() }
    @objc private func menuClipboard() { translateClipboard() }
    @objc private func menuReplace() { translateAndReplace() }

    @objc private func menuToggleClipboard() { setWatchClipboard(!clipboardWatcher.isRunning) }
    @objc private func menuScreenshot() { translateScreenshot() }
    @objc private func menuRecognize() { translateScreenshot(onlyRecognize: true) }
    @objc private func menuInput() { translateInput() }
    @objc private func menuMainWindow() { showMainWindow() }
    @objc private func menuNewSession() { newSession() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuPermission() { SelectionReader.requestPermission() }

    @objc private func menuToggleDock() {
        let hide = !UserDefaults.standard.bool(forKey: MenuBarKey.hideDockIcon)
        setHideDockIcon(hide)
        if !hide { showMainWindow() }
    }

    @objc private func menuToggleLogin() { setLaunchAtLogin(SMAppService.mainApp.status != .enabled) }
}
