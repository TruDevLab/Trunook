import TrunookXPC
import AppKit
import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon.
///
/// Именно Carbon, а не `NSEvent.addGlobalMonitorForEvents`: монитор событий
/// требует разрешения «Универсальный доступ» и, что важнее, не может
/// перехватить нажатие — оно всё равно уйдёт в активное приложение.
/// `RegisterEventHotKey` не требует разрешений и забирает сочетание себе.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    func start() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr else { return status }
            Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().fire(id.id)
            return noErr
        }, 1, &spec, context, &eventHandler)
    }

    func stop() {
        registered.values.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        handlers.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    /// Снимает все зарегистрированные сочетания, оставляя обработчик событий.
    func unregisterAll() {
        registered.values.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        handlers.removeAll()
    }

    @discardableResult
    func register(_ shortcut: HotKeySpec, name: String, action: @escaping () -> Void) -> Bool {
        start()

        let id = nextID
        nextID += 1

        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F4F4B), id: id) // 'NOOK'
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &reference
        )

        guard status == noErr, let reference else {
            // Чаще всего сочетание уже занято другим приложением.
            DebugLog.write("горячая клавиша «\(name)»: не удалось назначить, код \(status)")
            return false
        }
        registered[id] = reference
        handlers[id] = action
        return true
    }

    private func fire(_ id: UInt32) {
        handlers[id]?()
    }
}
