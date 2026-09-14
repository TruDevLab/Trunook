import SwiftUI

/// Состав меню всех функций — кольца быстрого доступа.
///
/// Отдельный тип, а не список внутри вёрстки: число кружков нужно ещё
/// и расчёту размера окна, а повторённое руками число расходится
/// с настоящим списком при первой же правке состава. Имя осталось от панели
/// «Всё сразу», которую кольцо заменило.
enum HubEntry: String, CaseIterable, Identifiable {
    // Главного экрана здесь нет намеренно: кольцо открывают с него же,
    // и закрытие кольца мимо кружков к нему и возвращает.
    case assistant
    // Заметки стоят сразу за командами: это соседние половины одного дела —
    // спросить и записать, — и добираться до записанного через панель команд
    // было лишним заходом.
    case notes
    case calendar
    case clipboard
    case shelf
    case timer
    case monitor
    case teleprompter
    // Новости и сайты — два кружка, а не один «Сводки»: открывают разные
    // вкладки одной панели, и человек, пришедший за ценой, не должен
    // пролистывать сводку.
    case news
    case sites
    // Бодрость включают на бегу, под начатое дело, и кружок для неё — путь
    // короче, чем раскрыть вырез и попасть в значок в крыле.
    case caffeine
    // Рядом с чашкой: чистку клавиатуры тоже включают на бегу.
    case keyboardLock
    // Голос и диктовка жили только на жесте и на сочетании: до них нельзя
    // было добраться мышью, то есть половине людей их попросту не было видно.
    case voice
    case dictation

    var id: String { rawValue }

    /// Что показывает кольцо быстрого доступа — всё, что есть.
    static var ringCases: [HubEntry] { allCases }

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
        case .news: return t("Новости")
        case .sites: return t("Сайты")
        // Тем же словом, что и панель выбора срока, и кнопка-чашка: одно
        // место с одним именем, откуда бы к нему ни шли.
        case .caffeine: return t("Бодрость")
        case .keyboardLock: return t("Чистка клавиатуры")
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
        case .news: return "newspaper"
        case .sites: return "binoculars"
        case .caffeine: return "cup.and.saucer.fill"
        case .keyboardLock: return "keyboard"
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
        case .keyboardLock: return Palette.keyboardLock
        case .news, .sites: return Palette.feeds
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
        // Выключателя нет: как телесуфлер, сама по себе ничего не делает.
        case .keyboardLock: return true
        case .news: return settings.digestEnabled
        case .sites: return settings.siteWatchEnabled
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
        // Сочетанием клавиатуру не блокируют: включают мышью и мышью же снимают.
        case .keyboardLock: return nil
        // Сочетание у панели одно на обе вкладки.
        case .news, .sites: return settings.feedsHotKey?.display
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
