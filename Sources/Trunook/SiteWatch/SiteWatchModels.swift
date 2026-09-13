import Foundation

/// Слежка за сайтом: что открыть, что искать и когда сообщать.
struct SiteWatch: Codable, Equatable, Identifiable {
    var id: Int
    var url: String
    var name: String
    /// За чем следить, словами человека: что угодно, что написано на странице.
    var target: String
    /// По умолчанию — любое изменение: оно работает с любым значением,
    /// а числовые условия только с числом.
    var condition: WatchCondition = .anyChange
    /// Порог для `.below` и `.above`. Для остальных условий не нужен.
    var threshold: Double?
    var interval: WatchInterval = .hour
    var isEnabled: Bool = true

    var pageURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        // Пробел внутри — это не адрес, а текст: `URL(string:)` его молча
        // закодировал бы и принял.
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil
        else { return nil }
        return url
    }

    /// Имя для плашки: своё, а без него — адрес без «www.».
    var displayName: String {
        let own = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        guard let host = pageURL?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

enum WatchCondition: String, Codable, CaseIterable, Identifiable {
    case anyChange
    case decrease
    case increase
    case below
    case above

    var id: String { rawValue }

    /// Условие сравнивает числа. У значения без числа («Нет в наличии»)
    /// оно не сработает никогда — об этом надо сказать, а не молчать.
    var needsNumber: Bool { self != .anyChange }

    /// Порог нужен только двум условиям.
    var usesThreshold: Bool { self == .below || self == .above }

    var title: String {
        switch self {
        case .anyChange: return t("Любое изменение")
        case .decrease: return t("Стало меньше")
        case .increase: return t("Стало больше")
        case .below: return t("Ниже порога")
        case .above: return t("Выше порога")
        }
    }
}

enum WatchInterval: Int, Codable, CaseIterable, Identifiable {
    case quarter = 15
    case hour = 60
    case threeHours = 180
    case sixHours = 360
    case day = 1440

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    var title: String {
        switch self {
        case .quarter: return t("Каждые 15 минут")
        case .hour: return t("Каждый час")
        case .threeHours: return t("Каждые 3 часа")
        case .sixHours: return t("Каждые 6 часов")
        case .day: return t("Раз в сутки")
        }
    }
}

enum SiteWatches {
    static let key = "siteWatches"

    static func load(from defaults: UserDefaults) -> [SiteWatch] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([SiteWatch].self, from: data)
        else { return [] }
        return stored
    }

    static func save(_ watches: [SiteWatch], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(watches) else { return }
        defaults.set(data, forKey: key)
    }

    static func nextID(after watches: [SiteWatch]) -> Int {
        (watches.map(\.id).max() ?? -1) + 1
    }
}

/// Прочитанное со страницы значение.
struct WatchReading: Codable, Equatable {
    /// Как написано на странице — это и показывается человеку.
    var text: String
    /// Число из него, если это число. Сравниваются числа, а не строки:
    /// «12 990 ₽» и «12990 ₽» — одна цена.
    var number: Double?
}

enum WatchStatus: String, Codable {
    case waiting
    case ok
    /// Сайт показал проверку на робота или отказ.
    case blocked
    /// Страница открылась, но искомого на ней не нашлось.
    case notFound
    case failed
}

/// Что известно о слежке после проверок. Лежит отдельно от настроек:
/// меняется на каждой проверке, и держать его в UserDefaults значило бы
/// перерисовывать окно настроек раз в пятнадцать минут.
struct WatchState: Codable, Equatable {
    var reading: WatchReading?
    var previous: WatchReading?
    var status: WatchStatus = .waiting
    var checkedAt: Date?
    var changedAt: Date?
    /// Хэш текста страницы: не изменился — модель не зовём.
    var textHash: String?
    /// Изменение ещё не видели. Гасится открытием панели.
    var unseen: Bool = false
    /// Для какой цели и какого адреса всё это получено.
    ///
    /// Без них правка цели ничего не сбрасывала: цель «цена» сменили
    /// на «версия», страница осталась прежней, проверка по отпечатку
    /// решала «та же» и не звала модель — и в строке так и висело
    /// «цена не указана».
    var target: String?
    var url: String?

    /// Относится ли состояние к слежке в нынешнем виде.
    func matches(_ watch: SiteWatch) -> Bool {
        target == watch.target && url == watch.url
    }
}
