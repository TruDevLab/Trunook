import TrunookXPC
import AppKit
import CoreGraphics
import Foundation

/// Глушит клавиатуру на короткий срок — чтобы протереть её, ничего
/// не напечатав.
///
/// Через перехватчик событий `CGEvent.tapCreate` на уровне HID: он стоит
/// раньше всех приложений и сочетаний Carbon, и проглоченное нажатие
/// не доходит никуда. Мышь и трекпад не трогаются — ими блокировку
/// и снимают досрочно.
///
/// Сроки только короткие и только со сроком: заблокированную клавиатуру
/// без мыши не вернуть, и «без ограничения» здесь было бы ловушкой.
/// Перехватчик живёт вместе с процессом — упади приложение, клавиатура
/// вернётся сама.
///
/// Не глушится то, что идёт мимо событий: кнопка питания, Touch ID
/// и поля пароля с защищённым вводом — туда перехватчик не заглядывает.
final class KeyboardLock: ObservableObject {
    /// Сроки в секундах, которые предлагает панель.
    static let durations = [30, 60, 90]

    /// До какого момента клавиатура заглушена. `nil` — работает.
    @Published private(set) var endsAt: Date?

    /// С каким сроком заглушили в этот раз, в секундах.
    @Published private(set) var activeSeconds = 0

    /// Последняя попытка не удалась: система не дала поставить перехватчик.
    /// Держится до следующей попытки — панель говорит, почему ничего
    /// не произошло.
    @Published private(set) var failed = false

    var isOn: Bool { endsAt != nil }

    /// Срок вышел, и клавиатура вернулась сама. Досрочное снятие рукой
    /// сюда не приходит: человек сам нажал и сам всё видел.
    var onExpired: (() -> Void)?

    private let tap: KeyboardTap
    private var limitTimer: Timer?

    init(tap: KeyboardTap = EventKeyboardTap()) {
        self.tap = tap
    }

    deinit {
        limitTimer?.invalidate()
        tap.stop()
    }

    /// Заглушить или переставить срок у уже заглушённой.
    @discardableResult
    func lock(seconds: Int) -> Bool {
        guard seconds > 0 else { return false }
        if !isOn {
            guard tap.start() else {
                failed = true
                DebugLog.write("клавиатура: перехватчик не поставлен — нет Универсального доступа?")
                return false
            }
        }
        failed = false
        activeSeconds = seconds
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        limitTimer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            self?.expire()
        }
        // .common, иначе будильник замрёт, пока открыто меню, — а срок
        // здесь то единственное, что возвращает клавиатуру.
        RunLoop.main.add(timer, forMode: .common)
        limitTimer = timer
        DebugLog.write("клавиатура: заглушена на \(seconds) с")
        return true
    }

    func unlock() {
        guard isOn else { return }
        release()
        DebugLog.write("клавиатура: снята рукой")
    }

    /// Отладочный вход: ждать полторы минуты в сессии незачем.
    func debugExpireNow() { expire() }

    private func expire() {
        guard isOn else { return }
        release()
        DebugLog.write("клавиатура: срок вышел")
        onExpired?()
    }

    private func release() {
        limitTimer?.invalidate()
        limitTimer = nil
        tap.stop()
        endsAt = nil
        activeSeconds = 0
    }

    /// Остаток для строки состояния: «0:42».
    static func clock(until endsAt: Date, now: Date) -> String {
        let left = Int(max(0, endsAt.timeIntervalSince(now)).rounded(.up))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    /// Какие события глотать.
    ///
    /// Клавиши и модификаторы — всегда. Системные события — только
    /// подтипа 8, это клавиши громкости, яркости и музыки в верхнем ряду;
    /// подтип 7 у того же типа — кнопки мыши, их трогать нельзя.
    ///
    /// Тип числом, а не `CGEventType`: у системных событий в нём нет своего
    /// случая, и из числа 14 перечисление не собрать.
    static func swallows(type: UInt32, subtype: Int16?) -> Bool {
        switch type {
        case CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
             CGEventType.flagsChanged.rawValue:
            return true
        default:
            return type == systemDefined && subtype == auxControlButtons
        }
    }

    /// `NSEvent.EventType.systemDefined` — в `CGEventType` своего имени нет.
    static let systemDefined: UInt32 = 14
    /// `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
    static let auxControlButtons: Int16 = 8
}

/// Перехватчик клавиш — отдельно, чтобы службу можно было проверить
/// без настоящей блокировки клавиатуры тестового процесса.
protocol KeyboardTap: AnyObject {
    /// `false` — система не дала поставить перехватчик.
    func start() -> Bool
    func stop()
}

/// Настоящий перехватчик на уровне HID.
final class EventKeyboardTap: KeyboardTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        guard port == nil else { return true }
        let types: [UInt32] = [
            CGEventType.keyDown.rawValue,
            CGEventType.keyUp.rawValue,
            CGEventType.flagsChanged.rawValue,
            KeyboardLock.systemDefined,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<EventKeyboardTap>.fromOpaque(info).takeUnretainedValue()
                return owner.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        // Система выключает перехватчик, если он замешкался, — и клавиатура
        // молча оживала бы посреди чистки. Включаем обратно.
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        default:
            let subtype = type.rawValue == KeyboardLock.systemDefined
                ? NSEvent(cgEvent: event).map { Int16($0.subtype.rawValue) }
                : nil
            return KeyboardLock.swallows(type: type.rawValue, subtype: subtype)
                ? nil
                : Unmanaged.passUnretained(event)
        }
    }
}
