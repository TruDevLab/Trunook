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
    case assistant
    // Заметки стоят сразу за командами: это соседние половины одного дела —
    // спросить и записать, — и добираться до записанного через панель команд
    // было лишним заходом.
    case notes
    // Календарь — восьмой и последний: место под него в сетке было оставлено
    // ровно на такой случай.
    case calendar
    case clipboard
    case shelf
    case timer
    case monitor
    case teleprompter
    // Чашка — девятая. До неё можно было добраться только кнопкой в левом
    // крыле раскрытой панели, то есть сперва раскрыв вырез наведением
    // и попав в значок в одиннадцать пунктов. Бодрость включают на бегу,
    // под начатое дело, и жест для неё — путь короче наведения.
    case caffeine
    // Голос и диктовка — десятая и одиннадцатая. Обе про речь, и обе до сих пор
    // жили только на жесте и на сочетании: до них нельзя было добраться
    // ни мышью, ни из меню, то есть половине людей их попросту не было
    // видно. Сетка от этого выросла на ряд — тот случай, когда лишний ряд
    // дешевле недоступной функции.
    case voice
    case dictation

    var id: String { rawValue }

    /// Стоит ли плитка в меню «Всё сразу».
    ///
    /// Чашка, голос и диктовка — не стоят, и это не забывчивость. Сетка меню
    /// держится в два ряда нарочно: оно вызывается правой кнопкой поверх
    /// чужих окон, и третий ряд отнимает у экрана семьдесят четыре точки
    /// ровно там, ради чего меню и открыли. У кольца такого ограничения
    /// нет вовсе — оно веер, а не сетка, — и лишние кружки ему ничего
    /// не стоят.
    ///
    /// Списка два, а состав один: расходиться им можно только длиной.
    var inHubPanel: Bool {
        switch self {
        case .caffeine, .voice, .dictation: return false
        default: return true
        }
    }

    /// Что показывает меню «Всё сразу».
    static var panelCases: [HubEntry] { allCases.filter(\.inHubPanel) }

    /// Что показывает кольцо быстрого доступа — всё, что есть.
    static var ringCases: [HubEntry] { allCases }

    /// Длина списка меню: по ней считается высота панели.
    static var count: Int { panelCases.count }

    var title: String {
        switch self {
        // «Команды» — тем же словом, что и шапка самой панели, и переключатель
        // в ней. Плитка звалась «ИИ», панель открывалась под заголовком
        // «Модель», а подпись под чёлкой обещала «Модель и заметки»: три имени
        // одного места, и по ним не собрать, что это одно и то же место.
        case .assistant: return t("Команды")
        case .notes: return t("Заметки")
        case .calendar: return t("Календарь")
        case .clipboard: return t("Буфер обмена")
        case .shelf: return t("Полка")
        case .timer: return t("Таймер")
        case .monitor: return t("Нагрузка")
        case .teleprompter: return t("Телесуфлер")
        // Тем же словом, что и панель выбора срока, и кнопка-чашка: одно
        // место с одним именем, откуда бы к нему ни шли.
        case .caffeine: return t("Бодрость")
        case .voice: return t("Спросить голосом")
        case .dictation: return t("Надиктовать заметку")
        }
    }

    var symbol: String {
        switch self {
        case .assistant: return "sparkles"
        case .notes: return "note.text"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shelf: return "tray.full.fill"
        case .timer: return "timer"
        case .monitor: return "gauge.with.dots.needle.67percent"
        case .teleprompter: return "text.alignleft"
        case .caffeine: return "cup.and.saucer.fill"
        case .voice: return "waveform"
        case .dictation: return "mic"
        }
    }

    var tint: Color {
        switch self {
        case .assistant: return Palette.assistant
        case .notes: return Palette.notes
        case .calendar: return Palette.calendar
        case .clipboard: return Palette.clipboard
        case .shelf: return Palette.shelf
        case .timer: return Palette.timer
        case .monitor: return Palette.monitor
        case .teleprompter: return Palette.teleprompter
        case .caffeine: return Palette.caffeine
        case .voice, .dictation: return Palette.assistant
        }
    }

    /// Выключенная в настройках функция остаётся в меню, но недоступной:
    /// исчезающая плитка читается как «функцию убрали совсем», хотя её всего
    /// лишь выключили, — а вернуть её тогда неоткуда.
    func isEnabled(_ settings: Settings) -> Bool {
        switch self {
        // Не `quickCommandsEnabled`: плитка открывает разговор, а команды
        // в нём — только один из способов спросить. С выключенными командами
        // остаются свой вопрос и заметки, и закрывать вход к ним незачем.
        case .assistant:
            return settings.ollamaEnabled || settings.notesEnabled
                || settings.quickCommandsEnabled
        case .notes: return settings.notesEnabled
        case .calendar: return settings.calendarEnabled
        case .clipboard: return settings.clipboardEnabled
        case .shelf: return settings.shelfEnabled
        case .timer: return settings.timerEnabled
        case .monitor: return settings.monitorEnabled
        // Телесуфлер выключателя не имеет: он ничего не делает сам по себе —
        // ни опросов, ни клавиш, ни полосы под чёлкой, — и выключать в нём
        // нечего. Открыли окно — работает, закрыли — нет.
        case .teleprompter: return true
        case .caffeine: return settings.caffeineEnabled
        // Голосу нужна и сама модель: спросить вслух не у кого,
        // когда отвечать некому.
        case .voice: return settings.voiceEnabled && settings.ollamaEnabled
        // Диктовке модель не нужна вовсе — надиктованное ложится
        // в заметку текстом, без всякого разговора.
        case .dictation: return settings.voiceEnabled && settings.notesEnabled
        }
    }

    /// Сочетание клавиш, если оно у функции есть. Меню заодно им и учит.
    func hint(_ settings: Settings) -> String? {
        switch self {
        case .assistant: return settings.assistantHotKey?.display
        case .notes: return settings.notesHotKey?.display
        case .calendar: return settings.calendarHotKey?.display
        case .clipboard: return settings.clipboardHotKey?.display
        case .shelf: return settings.shelfHotKey?.display
        case .timer: return settings.timerHotKey?.display
        case .monitor: return settings.monitorHotKey?.display
        case .teleprompter: return settings.teleprompterHotKey?.display
        // У чашки сочетания нет, и это не пробел в настройках: она и не
        // должна отниматься клавишей у чужого приложения, а нажать её
        // по-прежнему можно в левом крыле раскрытой панели.
        case .caffeine: return nil
        // Голос зовут жестом, а не сочетанием, — его и показываем.
        // «Своё сочетание» в списке как раз и означает, что жеста нет.
        case .voice:
            return settings.voiceTrigger == .hotKey
                ? settings.voiceHotKey?.display
                : settings.voiceTrigger.title
        case .dictation: return settings.recordHotKey?.display
        }
    }
}
