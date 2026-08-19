import Carbon.HIToolbox

/// Каким сочетанием вызываются номерные строки истории буфера.
///
/// Один переключатель на весь набор, а не девять полей записи, как у команд:
/// строки нумеруются по порядку, а не по смыслу — сегодня под первым номером
/// одно, завтра другое. Настраивать каждую по отдельности здесь нечего,
/// а вот увести весь набор с чужих сочетаний бывает нужно.
/// Какими клавишами вставляются записи истории по номеру.
///
/// По умолчанию ⌃⇧, а не ⌃⌥, хотя ⌃⌥ — «своя» пара приложения: цифры этой
/// пары заняты слотами быстрых команд, и две девятки на одних клавишах
/// не разошлись бы. Выбор оставлен пользователю: `.controlOption` в списке
/// есть, но тогда слоты команд с первого по шестой перестанут срабатывать.
enum ClipboardSlotModifiers: String, CaseIterable, Identifiable {
    case controlOption
    case controlShift
    case commandShift
    case off

    var id: String { rawValue }

    /// Маска Carbon. `nil` — номерные клавиши выключены.
    var carbonMask: UInt32? {
        switch self {
        case .controlOption: return UInt32(controlKey | optionKey)
        case .controlShift: return UInt32(controlKey | shiftKey)
        case .commandShift: return UInt32(cmdKey | shiftKey)
        case .off: return nil
        }
    }

    var title: String {
        switch self {
        case .controlOption: return "⌃⌥1 … ⌃⌥9"
        case .controlShift: return "⌃⇧1 … ⌃⇧9"
        case .commandShift: return "⇧⌘1 … ⇧⌘9"
        case .off: return t("Выключены")
        }
    }

    /// Короткая подпись для шапки панели: клавиши нужно как-то показать,
    /// иначе о них никто не узнает.
    var hint: String? {
        switch self {
        // Диапазон, а не буква: «⌃⌥N» читалось как сочетание с латинской N,
        // хотя означало «любая цифра».
        case .controlOption: return "⌃⌥1…9"
        case .controlShift: return "⌃⇧1…9"
        case .commandShift: return "⇧⌘1…9"
        case .off: return nil
        }
    }
}
