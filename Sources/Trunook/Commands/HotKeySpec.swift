import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш, заданное пользователем.
struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    /// Маска модификаторов в терминах Carbon — именно её ждёт
    /// `RegisterEventHotKey`.
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Собирает сочетание из нажатия. Возвращает nil, если модификаторов нет:
    /// глобальная клавиша без них перехватывала бы обычный набор текста.
    init?(event: NSEvent) {
        var mask: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }

        guard mask != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mask)
    }

    /// Человекочитаемая запись: ⌃⌥1.
    var display: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + Self.name(for: keyCode)
    }

    // MARK: - Значения по умолчанию

    /// Пара модификаторов, на которой сидит всё приложение.
    ///
    /// Выбрана не по вкусу, а по остаточному принципу: ⌘ и ⌥⌘ система
    /// разобрала под своё, ⇧⌘ традиционно занимают приложения, а ⌃⌥ macOS
    /// не использует ни под что. Одна пара на все вызовы Trunook — чтобы
    /// сочетание вспоминалось по первой букве, а не перебором модификаторов.
    private static let own = UInt32(controlKey | optionKey)

    /// ⌃⌥C — меню быстрых команд.
    ///
    /// Было ⌥⌘Space, и это оказалось системным сочетанием: им macOS открывает
    /// окно поиска Finder. Приложение регистрировало его поверх, и что
    /// сработает — зависело от того, кто успел первым.
    static let menu = HotKeySpec(keyCode: UInt32(kVK_ANSI_C), modifiers: own)

    /// ⌃⌥1 … ⌃⌥6 — слоты быстрых команд. Цифра совпадает с номером плитки
    /// в меню, так что подсматривать сочетание негде и не нужно.
    static func slot(_ index: Int) -> HotKeySpec? {
        guard index < QuickCommands.slotCount, digits.indices.contains(index) else { return nil }
        return HotKeySpec(keyCode: UInt32(digits[index]), modifiers: own)
    }

    /// ⌃⌥V — история буфера. Не ⇧⌘C и не ⇧⌘V: их занимают привычные
    /// менеджеры буфера обмена.
    static let clipboard = HotKeySpec(keyCode: UInt32(kVK_ANSI_V), modifiers: own)

    /// ⌃⌥S — полка.
    static let shelf = HotKeySpec(keyCode: UInt32(kVK_ANSI_S), modifiers: own)

    /// ⌃⌥T — таймер и секундомер.
    static let timer = HotKeySpec(keyCode: UInt32(kVK_ANSI_T), modifiers: own)

    /// ⌃⌥M — нагрузка на систему.
    static let monitor = HotKeySpec(keyCode: UInt32(kVK_ANSI_M), modifiers: own)

    /// Цифра для номерной строки истории буфера.
    static func clipboardSlot(_ index: Int, modifiers: UInt32) -> HotKeySpec? {
        guard digits.indices.contains(index) else { return nil }
        return HotKeySpec(keyCode: UInt32(digits[index]), modifiers: modifiers)
    }

    /// Умолчание слотов до 0.6.0: ⌥⌘ и цифра по номеру слота.
    ///
    /// Нужно ровно для одного — узнать нетронутое сочетание и перенести его
    /// на новую пару модификаторов. Своё, заданное человеком, остаётся.
    static func legacySlot(_ index: Int) -> HotKeySpec? {
        guard digits.indices.contains(index) else { return nil }
        return HotKeySpec(keyCode: UInt32(digits[index]), modifiers: UInt32(optionKey | cmdKey))
    }

    private static let digits = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    // MARK: - Имена клавиш

    /// Таблица вместо `UCKeyTranslate`: раскладка может быть кириллической,
    /// и тогда перевод кода в символ дал бы «Ф» вместо «A» — а сочетание
    /// физически висит на той же клавише независимо от раскладки.
    private static func name(for keyCode: UInt32) -> String {
        if let special = specialNames[Int(keyCode)] { return special }
        if let letter = letterNames[Int(keyCode)] { return letter }
        return tf("клавиша %d", keyCode)
    }

    private static let specialNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "esc",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static let letterNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
        kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=",
        kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Grave: "`",
    ]
}
