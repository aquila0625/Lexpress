import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// 划词翻译：读取其它 App 里当前选中的文字。需要“辅助功能”权限。
enum SelectionReader {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 弹出系统的辅助功能授权提示，并打开对应的设置页
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// 先直接问辅助功能接口要选中的文字；有些 App（浏览器、Electron 应用）不提供，
    /// 就模拟按一次 ⌘C，读完再把剪贴板原来的内容放回去。
    static func selectedText() async -> String? {
        guard hasPermission else {
            requestPermission()
            return nil
        }
        if let text = viaAccessibility()?.trimmed, !text.isEmpty { return text }
        return await viaCopy()?.trimmed
    }

    private static func viaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func viaCopy() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        let before = pasteboard.changeCount

        // 等用户松开快捷键里的 ⌥，否则发出去的会是 ⌥⌘C
        try? await Task.sleep(for: .milliseconds(150))
        pressCommandC()
        for _ in 0..<12 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        restore(saved, to: pasteboard)
        return text
    }

    private static func pressCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restore(_ items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { contents in
            let item = NSPasteboardItem()
            contents.forEach { item.setData($0.value, forType: $0.key) }
            return item
        })
    }
}
