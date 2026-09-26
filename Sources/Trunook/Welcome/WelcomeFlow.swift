import SwiftUI

/// Что человек выбирает на шаге «Чем пользуетесь» и что из этого следует:
/// какие шаги знакомства он увидит и какой главный экран ему собрать.
///
/// Без вёрстки и без служб — чистые правила, под тестом. Сам выбор хранится
/// не здесь, а в настройках: плитка на шаге и есть выключатель функции,
/// поэтому знакомство, открытое второй раз, показывает то, что включено
/// на деле.
enum WelcomeFlow {
    /// Функции, о которых спрашивают в начале. Только те, что настраивают
    /// в знакомстве или без которых главный экран собирать не из чего;
    /// Obsidian, сводки, слежка за сайтами, провайдеры и команды — в настройках.
    enum Use: String, CaseIterable, Identifiable {
        case calendar, music, assistant, notes, clipboard, weather, breaks, timer, shelf

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return t("Календарь и встречи")
            case .music: return t("Музыка")
            case .assistant: return t("Помощник ИИ")
            case .notes: return t("Заметки")
            case .clipboard: return t("Буфер обмена")
            case .weather: return t("Погода")
            case .breaks: return t("Перерывы и вода")
            case .timer: return t("Таймер")
            case .shelf: return t("Полка для файлов")
            }
        }

        var summary: String {
            switch self {
            case .calendar: return t("Встреча заранее, кнопки звонка")
            case .music: return t("Что играет и управление")
            case .assistant: return t("Вопрос модели из выреза")
            case .notes: return t("Быстрые записи")
            case .clipboard: return t("История копирований")
            case .weather: return t("Дождь — заранее")
            case .breaks: return t("Вовремя встать и попить")
            case .timer: return t("Отсчёт в чёлке")
            case .shelf: return t("Файлы на чёлку")
            }
        }

        var symbol: String {
            switch self {
            case .calendar: return "calendar"
            case .music: return "music.note"
            case .assistant: return "sparkles"
            case .notes: return "list.bullet.rectangle"
            case .clipboard: return "doc.on.clipboard.fill"
            case .weather: return "cloud.sun.fill"
            case .breaks: return "figure.cooldown"
            case .timer: return "timer"
            case .shelf: return "tray.full.fill"
            }
        }

        var tint: Color {
            switch self {
            case .calendar, .clipboard, .weather: return WelcomePalette.cyan
            case .music, .assistant, .notes, .shelf: return WelcomePalette.violet
            case .breaks, .timer: return WelcomePalette.mint
            }
        }

        func isOn(in settings: Settings) -> Bool {
            switch self {
            case .calendar: return settings.calendarEnabled
            case .music: return settings.musicEnabled
            case .assistant: return settings.ollamaEnabled
            case .notes: return settings.notesEnabled
            case .clipboard: return settings.clipboardEnabled
            case .weather: return settings.weatherEnabled
            case .breaks: return BreakKind.allCases.contains { $0.minutes(in: settings) > 0 }
            case .timer: return settings.timerEnabled
            case .shelf: return settings.shelfEnabled
            }
        }

        /// Включить или выключить саму функцию.
        ///
        /// Перерывам выключателя нет — их задают частотой. Включённые разом
        /// получают по часу на перерыв и воду; точнее — на шаге погоды
        /// и перерывов.
        func set(_ on: Bool, in settings: Settings) {
            switch self {
            case .calendar: settings.calendarEnabled = on
            case .music: settings.musicEnabled = on
            case .assistant: settings.ollamaEnabled = on
            case .notes: settings.notesEnabled = on
            case .clipboard: settings.clipboardEnabled = on
            case .weather: settings.weatherEnabled = on
            case .breaks:
                BreakKind.rest.setMinutes(on ? 60 : 0, in: settings)
                BreakKind.water.setMinutes(on ? 60 : 0, in: settings)
                if !on { BreakKind.stretch.setMinutes(0, in: settings) }
            case .timer: settings.timerEnabled = on
            case .shelf: settings.shelfEnabled = on
            }
        }
    }

    static func uses(in settings: Settings) -> Set<Use> {
        Set(Use.allCases.filter { $0.isOn(in: settings) })
    }

    /// Шаги, которые увидит человек с таким набором. Настройка календаря,
    /// погоды с перерывами и помощника — только для отмеченного.
    static func steps(uses: Set<Use>) -> [WelcomeModel.Step] {
        WelcomeModel.Step.allCases.filter { step in
            switch step {
            case .calendar: return uses.contains(.calendar)
            case .weather: return uses.contains(.weather) || uses.contains(.breaks)
            case .ai: return uses.contains(.assistant)
            default: return true
            }
        }
    }

    /// Главный экран из того, чем пользуются: сперва крупное — музыка
    /// и встречи, — потом мелочь. Укладка плотная (`HomeGrid.place`),
    /// поэтому маленькие плитки сами заходят в пустые клетки; не влезшее
    /// в четыре ряда отбрасывается, чтобы раскладка не хранила невидимого.
    static func home(for uses: Set<Use>) -> [HomeWidget] {
        var kinds: [(HomeWidgetKind, HomeWidgetSize)] = []
        if uses.contains(.music) { kinds.append((.music, .threeWide)) }
        if uses.contains(.weather) { kinds.append((.weather, .small)) }
        if uses.contains(.calendar) {
            kinds.append((.schedule, .large))
            kinds.append((.month, .large))
        }
        // Вопрос к ИИ в половину ряда: во весь ряд он вытеснял таймер,
        // заметки и полку за четвёртый ряд (снято снимком).
        if uses.contains(.assistant) { kinds.append((.ask, .wide)) }
        if uses.contains(.timer) { kinds.append((.timer, .small)) }
        if uses.contains(.breaks) { kinds.append((.water, .small)) }
        if uses.contains(.notes) { kinds.append((.notes, .wide)) }
        if uses.contains(.clipboard) { kinds.append((.clipboard, .wide)) }
        if uses.contains(.shelf) { kinds.append((.shelf, .small)) }
        // Отмечено совсем мало — пустой экран хуже стандартного.
        guard !kinds.isEmpty else { return HomeWidgets.standard }

        let widgets = kinds.enumerated().map { index, item in
            HomeWidget(id: index, kind: item.0, size: item.1)
        }
        let placed = HomeGrid.place(widgets)
        let kept = Set(placed.placements.map(\.widget.id))
        return widgets.filter { kept.contains($0.id) }
    }
}
