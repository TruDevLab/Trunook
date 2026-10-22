import TrunookXPC
import AppKit
import CoreGraphics

/// Перехватчик ⌘Tab для переключателя окон.
///
/// На уровне HID, как блокировка клавиатуры: там он раньше системного
/// переключателя приложений, и проглоченное ⌘Tab до Dock не доходит.
/// Пропускает всё, кроме Tab с модификатором, а пока переключатель
/// открыт — глотает остальные нажатия: ⌘ в это время держат, и любая
/// клавиша ушла бы переднему приложению сочетанием с ⌘.
///
/// **Живёт в своём потоке, а не на главном.** Перехватчик стоит на пути
/// каждого нажатия во всей системе: пока его обработчик не вернулся,
/// буква не напечатается ни в одном приложении. Главный поток Trunook
/// бывает занят — вёрсткой, вопросами Универсальному доступу с таймаутом
/// в 0,2 с, — и печать во всей системе запиналась бы вместе с ним.
/// Здесь обработчик только сравнивает числа и отдаёт дело главному потоку.
final class SwitcherKeyTap {
    /// Что сделать — на главном потоке.
    var onKey: (SwitcherKey) -> Void = { _ in }

    private let lock = NSLock()
    private var open = false
    private var currentTrigger: SwitcherTrigger = .command
    private var port: CFMachPort?
    private var runLoop: CFRunLoop?

    var isRunning: Bool { port != nil }

    /// Открыт ли переключатель. Пишут оба: перехватчик — на открытии
    /// и отпускании ⌘, главный поток — на щелчке и отмене снаружи.
    var isOpen: Bool {
        get { lock.withLock { open } }
        set { lock.withLock { open = newValue } }
    }

    var trigger: SwitcherTrigger {
        get { lock.withLock { currentTrigger } }
        set { lock.withLock { currentTrigger = newValue } }
    }

    /// `false` — система не дала поставить перехватчик: нет Универсального доступа.
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<SwitcherKeyTap>.fromOpaque(info).takeUnretainedValue()
                return owner.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DebugLog.write("переключатель: перехватчик не поставлен — нет Универсального доступа?")
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        let thread = Thread { [weak self] in
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            self?.lock.withLock { self?.runLoop = loop }
            CGEvent.tapEnable(tap: port, enable: true)
            // Источник снимут вместе с портом — тогда цикл и кончится.
            CFRunLoopRun()
        }
        thread.name = "com.trunook.switcher-keys"
        thread.qualityOfService = .userInteractive
        thread.start()
        DebugLog.write("переключатель: перехватчик поставлен")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let loop = lock.withLock({ runLoop }) { CFRunLoopStop(loop) }
        lock.withLock { runLoop = nil }
        self.port = nil
        isOpen = false
        DebugLog.write("переключатель: перехватчик снят")
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let (isOpen, trigger) = lock.withLock { (open, currentTrigger) }
        switch type {
        // Система выключает замешкавшийся перехватчик — включаем обратно.
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let action = SwitcherKey.keyDown(code, flags: event.flags, isOpen: isOpen, trigger: trigger)
            switch action {
            case .pass:
                return pass
            case .lost:
                // Отпускание ⌘ мимо нас прошло — переключатель уже не держат.
                self.isOpen = false
                deliver(.commit)
                return pass
            case .swallow:
                return nil
            case .open:
                self.isOpen = true
            case .commit, .cancel:
                self.isOpen = false
            case .step, .tabs:
                break
            }
            deliver(action)
            return nil
        case .keyUp:
            return isOpen ? nil : pass
        case .flagsChanged:
            let action = SwitcherKey.flagsChanged(event.flags, isOpen: isOpen, trigger: trigger)
            if action == .commit {
                self.isOpen = false
                deliver(.commit)
            }
            return pass
        default:
            return pass
        }
    }

    private func deliver(_ action: SwitcherKey) {
        DispatchQueue.main.async { [weak self] in self?.onKey(action) }
    }
}
