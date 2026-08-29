import TrunookXPC
import AppKit
import Foundation

/// Нажатие клавиши от имени приложения — ⌘C для захвата выделенного,
/// ⌘V для вставки.
///
/// Отдельно от тех, кто им пользуется, потому что вся сложность здесь одна
/// и общая: **сочетание посылается в ответ на сочетание**. ⌃⌥C, ⌃⌥1, Enter
/// в открытой панели — во всех случаях в момент отправки человек ещё держит
/// свои клавиши нажатыми, а событие уходит с флагами, собранными из
/// состояния клавиатуры. Чужое приложение получает не ⌘C, а ⌃⌥⌘C — то есть
/// не получает ничего, и захват молча не срабатывает.
///
/// Отсюда правило: **сперва дождаться, пока человек отпустит свои клавиши,
/// и только потом нажимать свою.** Ждём не бесконечно — зажатый модификатор
/// не должен вешать захват навсегда, — но полсекунды хватает с запасом:
/// столько человек клавишу не держит, если не забыл про неё вовсе.
enum SyntheticKey {
    static let c: CGKeyCode = 8
    static let v: CGKeyCode = 9

    /// Сколько ждём, пока клавиши отпустят.
    private static let releaseTimeout: TimeInterval = 0.5
    /// Как часто спрашиваем.
    private static let pollStep: TimeInterval = 0.02
    /// Пауза после отпускания: нажатия человека и наше идут одной очередью,
    /// и чужому приложению нужно мгновение, чтобы разобрать отпускание,
    /// прежде чем к нему придёт наше нажатие.
    private static let settle: TimeInterval = 0.03

    /// Модификаторы, которых ждём. `capsLock` сюда не входит намеренно:
    /// это переключатель, а не удерживаемая клавиша, — с включённым
    /// регистром ожидание не кончилось бы никогда.
    private static let watched: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Послать сочетание, дождавшись, пока освободится клавиатура.
    static func send(_ key: CGKeyCode, flags: CGEventFlags, completion: (() -> Void)? = nil) {
        waitForRelease(until: Date().addingTimeInterval(releaseTimeout)) {
            post(key, flags: flags)
            completion?()
        }
    }

    private static func waitForRelease(until deadline: Date, then body: @escaping () -> Void) {
        let held = NSEvent.modifierFlags.intersection(watched)
        guard !held.isEmpty, Date() < deadline else {
            if !held.isEmpty {
                DebugLog.write("клавиши: не дождались отпускания, шлём как есть")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: body)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pollStep) {
            waitForRelease(until: deadline, then: body)
        }
    }

    private static func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Своё нажатие запускает промежуток подавления, на время которого
        // система по умолчанию глушит настоящую клавиатуру и мышь. Человеку
        // в этот миг ничего не мешаем: он продолжает работать, а не ждёт,
        // пока мы отпустим его ввод.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
