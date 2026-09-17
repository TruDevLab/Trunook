import SwiftUI

/// Размер плитки главного экрана в клетках сетки.
///
/// Набор закрытый, а не «сколько угодно на сколько угодно»: каждому размеру
/// каждого виджета нужна своя вёрстка, и размер, под который её нет,
/// показал бы то же содержимое, растянутое или обрезанное.
enum HomeWidgetSize: String, Codable, CaseIterable, Identifiable {
    case small
    case wide
    case threeWide
    case large
    case full
    case fullTall

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .small: return 1
        case .wide, .large: return 2
        case .threeWide: return 3
        case .full, .fullTall: return HomeGrid.columns
        }
    }

    var rows: Int {
        switch self {
        case .small, .wide, .threeWide, .full: return 1
        case .large, .fullTall: return 2
        }
    }

    /// Подпись в настройках: клетками, а не словами — «широкий» и «большой»
    /// не говорят, что из них выше.
    var title: String { "\(columns)×\(rows)" }
}

/// Что может стоять на главном экране.
///
/// Порядок перечисления — порядок в списке «Добавить виджет» в настройках:
/// от того, на что смотрят чаще, к ярлыкам.
enum HomeWidgetKind: String, Codable, CaseIterable, Identifiable {
    case music
    case schedule
    /// День шкалой времени — то же представление, что и в самой панели
    /// календаря.
    case timeline
    case month
    case tasks
    case ask
    case timer
    /// Обратный отсчёт до события, которое задал человек.
    case countdown
    case weather
    /// Сколько воды выпито за сегодня.
    case water
    case monitor
    case battery
    case caffeine
    case news
    case sites
    case clipboard
    case shelf
    case notes
    /// Закреплённые заметки — до трёх, под рукой.
    case pinnedNotes
    case voice
    case dictation
    case teleprompter

    var id: String { rawValue }

    /// Функция из кольца быстрого доступа, если виджет её повторяет. Имя, значок,
    /// цвет и выключатель берутся оттуда: одно место — одно имя, откуда бы
    /// к нему ни шли.
    var hubEntry: HubEntry? {
        switch self {
        case .schedule, .month, .timeline: return .calendar
        case .ask: return .assistant
        case .timer: return .timer
        case .monitor: return .monitor
        case .caffeine: return .caffeine
        case .news: return .news
        case .sites: return .sites
        case .clipboard: return .clipboard
        case .shelf: return .shelf
        case .notes: return .notes
        case .voice: return .voice
        case .dictation: return .dictation
        case .teleprompter: return .teleprompter
        case .music, .tasks, .weather, .battery, .pinnedNotes, .countdown, .water: return nil
        }
    }

    var title: String {
        switch self {
        case .music: return t("Музыка")
        // Два виджета одного календаря различаются тем, что показывают.
        case .schedule: return t("Ближайшие встречи")
        case .timeline: return t("Шкала дня")
        case .month: return t("Месяц")
        case .tasks: return t("Задачи Things")
        case .ask: return t("Вопрос к ИИ")
        case .weather: return t("Погода")
        case .water: return t("Вода")
        case .battery: return t("Батарея")
        case .pinnedNotes: return t("Закреплённые заметки")
        case .countdown: return t("Обратный отсчёт")
        default: return hubEntry?.title ?? rawValue
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        // Значок шкалы отдан шкале: у ближайших встреч он обещал
        // размещение во времени, которого в их списке нет.
        case .schedule: return "calendar.badge.clock"
        case .timeline: return "calendar.day.timeline.left"
        case .tasks: return "checklist"
        case .weather: return "cloud.sun.fill"
        case .water: return "drop.fill"
        case .battery: return "battery.75percent"
        case .pinnedNotes: return "pin.fill"
        case .countdown: return "hourglass"
        default: return hubEntry?.symbol ?? "square"
        }
    }

    var tint: Color {
        switch self {
        case .music: return Palette.voice
        case .tasks: return Palette.calendar
        case .weather: return Palette.weather
        case .water: return Palette.blue
        case .battery: return Palette.positive
        case .pinnedNotes: return Palette.notes
        case .countdown: return Palette.magenta
        default: return hubEntry?.tint ?? .white
        }
    }

    /// Размеры, под которые у виджета есть вёрстка. Первый — размер,
    /// с которым виджет добавляется.
    var allowedSizes: [HomeWidgetSize] {
        switch self {
        case .music: return [.full, .small, .wide, .threeWide, .large]
        case .schedule: return [.fullTall, .wide, .threeWide, .full, .large]
        // Плитки в один ряд получают ленту дня, в два — шкалу с часами
        // сбоку. Размера 1×1 нет: в одну клетку не встаёт ни то ни другое.
        case .timeline: return [.fullTall, .large, .full, .threeWide, .wide]
        case .month: return [.large]
        case .tasks: return [.full, .wide, .threeWide, .large, .fullTall]
        case .ask: return [.full, .wide, .threeWide]
        case .timer: return [.small, .wide, .threeWide]
        case .countdown: return [.wide, .small, .threeWide, .full]
        case .weather: return [.small, .wide, .threeWide]
        // Двух рядов нет: столбики заходов и одно число во весь рост плитки
        // растянулись бы пустотой — показывать там больше нечего.
        case .water: return [.wide, .small, .threeWide, .full]
        case .monitor: return [.wide, .small, .threeWide, .full]
        case .battery: return [.small]
        case .caffeine: return [.small, .wide, .threeWide]
        case .news: return [.full, .wide, .threeWide, .fullTall]
        case .sites: return [.wide, .threeWide, .full, .fullTall]
        case .clipboard: return [.wide, .threeWide, .full]
        case .shelf: return [.small, .wide, .threeWide]
        case .notes: return [.wide, .threeWide, .large, .full]
        case .pinnedNotes: return [.large, .wide, .threeWide, .full]
        case .voice, .dictation, .teleprompter: return [.small]
        }
    }

    var defaultSize: HomeWidgetSize { allowedSizes[0] }

    /// Выключенная функция остаётся на экране приглушённой, как и в кольце:
    /// пропавшая плитка читается как «виджет удалили», и
    /// вернуть его человек пошёл бы не в тот раздел.
    func isEnabled(_ settings: Settings) -> Bool {
        switch self {
        // Вода не спрашивает ни модели, ни доступов: пить можно и с
        // выключенным напоминанием.
        case .music, .battery, .countdown, .water: return true
        case .tasks: return settings.thingsEnabled
        case .weather: return settings.weatherEnabled
        case .pinnedNotes: return settings.notesEnabled
        default: return hubEntry?.isEnabled(settings) ?? true
        }
    }
}

/// Плитка главного экрана: что стоит и какого размера.
struct HomeWidget: Codable, Equatable, Identifiable {
    var id: Int
    var kind: HomeWidgetKind
    var size: HomeWidgetSize

    private enum CodingKeys: String, CodingKey { case id, kind, size }

    init(id: Int, kind: HomeWidgetKind, size: HomeWidgetSize) {
        self.id = id
        self.kind = kind
        self.size = kind.allowedSizes.contains(size) ? size : kind.defaultSize
    }

    /// Размер, которого у вида больше нет, заменяется размером по умолчанию,
    /// а не роняет всю раскладку: вёрстку виджета однажды поправят, и
    /// раскладка человека не должна пропасть из-за этого целиком.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(HomeWidgetKind.self, forKey: .kind)
        let size = (try? container.decode(HomeWidgetSize.self, forKey: .size)) ?? kind.defaultSize
        self.init(id: try container.decode(Int.self, forKey: .id), kind: kind, size: size)
    }
}

/// Хранение раскладки в настройках.
enum HomeWidgets {
    static let key = "homeWidgets"

    /// Раскладка по умолчанию — та, которую собрал себе пользователь:
    /// музыка 3×1 и погода рядом, под ними ближайшие встречи и месяц по 2×2.
    ///
    /// Погода стоит в списке последней, а на экране — в первом ряду: укладка
    /// плотная, и 1×1 сама заходит в клетку справа от музыки.
    static let standard: [HomeWidget] = [
        HomeWidget(id: 0, kind: .music, size: .threeWide),
        HomeWidget(id: 1, kind: .schedule, size: .large),
        HomeWidget(id: 2, kind: .month, size: .large),
        HomeWidget(id: 3, kind: .weather, size: .small),
    ]

    /// `nil` — раскладку ещё не сохраняли, и действует стандартная.
    ///
    /// Записи незнакомого вида пропускаются по одной: раскладка, сохранённая
    /// более новой версией, не должна обнулиться в более старой.
    static func load(from defaults: UserDefaults) -> [HomeWidget]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
        return raw.compactMap { item in
            guard let itemData = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(HomeWidget.self, from: itemData)
        }
    }

    static func save(_ widgets: [HomeWidget], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        defaults.set(data, forKey: key)
    }

    static func nextID(after widgets: [HomeWidget]) -> Int {
        (widgets.map(\.id).max() ?? -1) + 1
    }

    /// Проверочные раскладки: каждый вид в каждом своём размере, разложенные
    /// по страницам так, чтобы на странице ничего не выпало за четыре ряда.
    /// Глазами обрезку плитки иначе не поймать — ради неё и снимают.
    static func showcasePages(
        of kinds: [HomeWidgetKind] = HomeWidgetKind.allCases
    ) -> [[HomeWidget]] {
        var pages: [[HomeWidget]] = []
        var page: [HomeWidget] = []
        var id = 0
        for kind in kinds {
            for size in kind.allowedSizes {
                let widget = HomeWidget(id: id, kind: kind, size: size)
                id += 1
                if HomeGrid.place(page + [widget]).overflow.isEmpty {
                    page.append(widget)
                } else {
                    pages.append(page)
                    page = [widget]
                }
            }
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }
}
