import AppKit
import Foundation

/// Распознаёт модификатор, нажатый дважды подряд.
///
/// Чистая логика: принимает флаги и время, а не `NSEvent`, — иначе жест
/// нельзя было бы проверить тестом, а проверять его надо. **Ложное
/// срабатывание здесь хуже несработавшего:** несработавший жест повторяют,
/// а сработавший посреди работы открывает микрофон, о котором не просили.
///
/// Тап засчитывается, только если выполнено всё сразу:
///
/// 1. Нажат **ровно** нужный модификатор и никакой другой. ⌥ в составе ⌃⌥ —
///    не тап: человек набирает сочетание.
/// 2. Между нажатием и отпусканием **не было ни одной другой клавиши
///    и ни одного щелчка**. Без этого ⌃C, набранный дважды подряд, звал бы
///    ассистента — а это обычное копирование.
/// 3. Нажатие было коротким. Зажатый и удерживаемый модификатор — это
///    навигация или перетаскивание, а не жест.
/// 4. Второй тап пришёл в пределах окна.
final class DoubleTapModifier {
    /// Сколько ждать второго тапа. Больше — и два не связанных нажатия
    /// модификатора начнут склеиваться в жест; меньше — жест придётся
    /// выстукивать.
    static let window: TimeInterval = 0.4

    /// Дольше этого нажатие считается удержанием, а не тапом.
    static let maxHold: TimeInterval = 0.35

    private let flag: NSEvent.ModifierFlags

    /// Когда началось текущее нажатие. `nil` — сейчас ничего не нажато
    /// или нажатие уже испорчено.
    private var pressStartedAt: Date?
    /// Когда закончился первый засчитанный тап.
    private var firstTapEndedAt: Date?

    init(flag: NSEvent.ModifierFlags) {
        self.flag = flag
    }

    /// Модификаторы изменились. Возвращает `true`, если это был второй тап
    /// и жест состоялся.
    func flagsChanged(to flags: NSEvent.ModifierFlags, at time: Date = Date()) -> Bool {
        let pressed = Self.significant(flags)

        // Нажат ровно наш модификатор и ничего сверх — начало возможного тапа.
        if pressed == flag {
            pressStartedAt = time
            return false
        }

        // Всё отпущено — возможный конец тапа.
        if pressed.isEmpty {
            defer { pressStartedAt = nil }
            guard let started = pressStartedAt else {
                // Нажатия не было или его испортили — считать нечего.
                return false
            }
            guard time.timeIntervalSince(started) <= Self.maxHold else {
                // Удержание, а не тап. Счёт сбрасывается целиком: держали —
                // значит жеста не делали.
                firstTapEndedAt = nil
                return false
            }
            if let first = firstTapEndedAt, time.timeIntervalSince(first) <= Self.window {
                firstTapEndedAt = nil
                return true
            }
            firstTapEndedAt = time
            return false
        }

        // Нажато что-то ещё — например ⌃ поверх ⌥. Это набор сочетания,
        // а не жест: и текущее нажатие, и начатый счёт идут насмарку.
        pressStartedAt = nil
        firstTapEndedAt = nil
        return false
    }

    /// Нажали обычную клавишу или кнопку мыши.
    ///
    /// Это и есть проверка «модификатор нажали вхолостую»: ⌃C — сначала ⌃,
    /// потом C. Без этого второе такое копирование подряд звало бы голос.
    func otherInput() {
        pressStartedAt = nil
        firstTapEndedAt = nil
    }

    /// Забыть начатое — например, когда заход уже идёт.
    func reset() {
        pressStartedAt = nil
        firstTapEndedAt = nil
    }

    /// Только те модификаторы, что человек нажимает пальцами.
    ///
    /// `modifierFlags` приносит ещё и служебные биты — Caps Lock, признак
    /// цифровой клавиатуры, `.function` (её ставит любая стрелка и Fn),
    /// — и сравнение «нажат ровно наш модификатор» без чистки не сходилось
    /// бы никогда.
    private static func significant(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.control, .option, .command, .shift])
    }
}
