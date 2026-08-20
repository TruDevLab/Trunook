import SwiftUI

/// Состав меню всех функций.
///
/// Отдельный тип, а не список внутри вёрстки: число плиток нужно ещё
/// и для расчёта высоты панели, а повторённое руками число расходится
/// с настоящим списком при первой же правке состава.
enum HubEntry: String, CaseIterable, Identifiable {
    // Главного экрана здесь нет намеренно. Меню открывается **поверх** него,
    // и возврат уже есть — крестик в правом крыле, общий для всех накладок.
    // Плитка «Главный экран» дублировала его вторым способом на том же
    // экране, а два способа одного действия человек читает как два разных.
    case commands
    case clipboard
    case shelf
    case timer
    case monitor
    case teleprompter

    var id: String { rawValue }

    static var count: Int { allCases.count }

    var title: String {
        switch self {
        case .commands: return t("Команды")
        case .clipboard: return t("Буфер обмена")
        case .shelf: return t("Полка")
        case .timer: return t("Таймер")
        case .monitor: return t("Нагрузка")
        case .teleprompter: return t("Телесуфлер")
        }
    }

    var symbol: String {
        switch self {
        case .commands: return "square.grid.2x2.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .monitor: return "gauge.with.dots.needle.67percent"
        case .teleprompter: return "text.alignleft"
        }
    }

    var tint: Color {
        switch self {
        case .commands: return Palette.commands
        case .clipboard: return Palette.clipboard
        case .shelf: return Palette.shelf
        case .timer: return Palette.timer
        case .monitor: return Palette.monitor
        case .teleprompter: return Palette.teleprompter
        }
    }

    /// Выключенная в настройках функция остаётся в меню, но недоступной:
    /// исчезающая плитка читается как «функцию убрали совсем», хотя её всего
    /// лишь выключили, — а вернуть её тогда неоткуда.
    func isEnabled(_ settings: Settings) -> Bool {
        switch self {
        case .commands: return settings.quickCommandsEnabled
        case .clipboard: return settings.clipboardEnabled
        case .shelf: return settings.shelfEnabled
        case .timer: return settings.timerEnabled
        case .monitor: return settings.monitorEnabled
        // Телесуфлер выключателя не имеет: он ничего не делает сам по себе —
        // ни опросов, ни клавиш, ни полосы под чёлкой, — и выключать в нём
        // нечего. Открыли окно — работает, закрыли — нет.
        case .teleprompter: return true
        }
    }

    /// Сочетание клавиш, если оно у функции есть. Меню заодно им и учит.
    func hint(_ settings: Settings) -> String? {
        switch self {
        case .commands: return settings.menuHotKey?.display
        case .clipboard: return settings.clipboardHotKey?.display
        case .shelf: return settings.shelfHotKey?.display
        case .timer: return settings.timerHotKey?.display
        case .monitor: return settings.monitorHotKey?.display
        case .teleprompter: return settings.teleprompterHotKey?.display
        }
    }
}
