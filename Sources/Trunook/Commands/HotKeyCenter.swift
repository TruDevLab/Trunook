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

    /// Что должно быть назначено: сочетание, имя для журнала и действие.
    ///
    /// Хранится отдельно от самих регистраций, потому что их приходится
    /// снимать и ставить заново — на время записи нового сочетания
    /// в настройках. Без этого списка восстанавливать было бы нечего.
    private struct Entry {
        let spec: HotKeySpec
        let name: String
        let action: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    /// Свои сочетания сняты на время записи нового.
    private var isSuspended = false

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
        dropRegistrations()
        entries.removeAll()
        isSuspended = false
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    /// Снимает все зарегистрированные сочетания, оставляя обработчик событий.
    func unregisterAll() {
        dropRegistrations()
        entries.removeAll()
    }

    @discardableResult
    func register(_ shortcut: HotKeySpec, name: String, action: @escaping () -> Void) -> Bool {
        start()

        let id = nextID
        nextID += 1
        let entry = Entry(spec: shortcut, name: name, action: action)
        entries[id] = entry
        // Пока свои сочетания отпущены, новое только запоминается: поставит
        // его `resume`. Иначе назначенное прямо во время записи сочетание
        // снова перехватило бы клавиши у поля записи.
        guard !isSuspended else { return true }
        return install(id: id, entry: entry)
    }

    /// Отпустить свои сочетания.
    ///
    /// Нужно ровно на время записи нового сочетания в настройках.
    /// `RegisterEventHotKey` забирает нажатие себе **раньше** приложения —
    /// и раньше поля записи в его же окне: ⌃⌥1 уходила команде, стоящей
    /// на этой цифре, а поле не получало ничего и молчало. Снаружи это
    /// выглядело как «цифры не записываются».
    ///
    /// Список назначенного при этом цел: `resume` ставит всё обратно.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        dropRegistrations()
        DebugLog.write("горячие клавиши: отпущены на время записи")
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for (id, entry) in entries { install(id: id, entry: entry) }
        DebugLog.write("горячие клавиши: назначены заново — \(entries.count)")
    }

    private func install(id: UInt32, entry: Entry) -> Bool {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F4F4B), id: id) // 'NOOK'
        let status = RegisterEventHotKey(
            entry.spec.keyCode, entry.spec.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &reference
        )

        guard status == noErr, let reference else {
            // Чаще всего сочетание уже занято другим приложением.
            DebugLog.write("горячая клавиша «\(entry.name)»: не удалось назначить, код \(status)")
            return false
        }
        registered[id] = reference
        return true
    }

    private func dropRegistrations() {
        registered.values.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }

    private func fire(_ id: UInt32) {
        entries[id]?.action()
    }

    /// Сколько сочетаний числится назначенными. Нужно проверке.
    var count: Int { entries.count }
    /// Сколько стоит на самом деле: отпущенные не считаются.
    var liveCount: Int { registered.count }
}
