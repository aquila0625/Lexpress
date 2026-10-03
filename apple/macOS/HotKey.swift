import Carbon.HIToolbox

/// 全局快捷键。用 Carbon 的 RegisterEventHotKey，不需要“辅助功能”权限，可以同时注册多个。
final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerRef: EventHandlerRef?
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?

    /// 组合键已被别的 App 占用时返回 nil
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.installHandler()
        id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x51544C54), id: id) // 'QTLT'
        guard RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
        HotKey.actions[id] = action
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        HotKey.actions[id] = nil
    }

    /// 所有快捷键共用一个事件处理器，按按下的快捷键 ID 分发
    private static func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.actions[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
