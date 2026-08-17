import SwiftUI
import AppKit

/// Ссылка на онлайн-встречу с опознанным сервисом.
struct MeetingLink: Equatable {
    let url: URL
    let provider: Provider

    enum Provider: String, Equatable {
        case zoom = "Zoom"
        case teams = "Teams"
        case meet = "Google Meet"
        case telemost = "Телемост"
        case webex = "Webex"
        case whereby = "Whereby"
        case other = "Встреча"

        /// Показываемое имя. Названия сервисов — марки, их не переводят;
        /// переводится только запасное «Встреча» для неопознанной ссылки.
        var title: String { self == .other ? t("Встреча") : rawValue }

        var symbol: String {
            switch self {
            case .zoom, .teams, .meet, .webex, .whereby, .telemost: return "video.fill"
            case .other: return "link"
            }
        }
    }

    /// Ищет ссылку по всем полям, куда её кладут разные календари:
    /// приглашения Exchange пишут в notes, Google — в url, а люди руками —
    /// в location. Проверяем всё, в порядке надёжности.
    static func extract(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        if let url, let link = make(from: url) { return link }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = firstLink(in: text) { return link }
        }
        return nil
    }

    private static func firstLink(in text: String) -> MeetingLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range).compactMap(\.url)

        // Сначала ищем знакомый сервис по всему тексту: в приглашении обычно
        // соседствуют ссылка на конференцию и ссылки на карты или телефоны.
        for candidate in matches {
            if let link = make(from: candidate), link.provider != .other {
                return link
            }
        }
        return matches.first.flatMap { make(from: $0) }
    }

    private static func make(from url: URL) -> MeetingLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        let provider: Provider
        switch true {
        case host.contains("zoom.us"), host.contains("zoom.com"):
            provider = .zoom
        case host.contains("teams.microsoft.com"), host.contains("teams.live.com"):
            provider = .teams
        case host.contains("meet.google.com"):
            provider = .meet
        case host.contains("telemost.yandex"), host.contains("telemost.360"):
            provider = .telemost
        case host.contains("webex.com"):
            provider = .webex
        case host.contains("whereby.com"):
            provider = .whereby
        default:
            // Ссылку без узнаваемого хоста считаем встречей только если она
            // похожа на приглашение, а не на вложение или карту.
            guard path.contains("meet") || path.contains("call") || path.contains("conf") else {
                return nil
            }
            provider = .other
        }
        return MeetingLink(url: url, provider: provider)
    }
}

/// Событие в вырезе: встреча из календаря, напоминание или задача Things.
struct CalendarItem: Identifiable, Equatable {
    enum Source: Equatable {
        case event
        case reminder
        case things
    }

    let id: String
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let source: Source
    let link: MeetingLink?
    /// Цвет календаря, к которому относится событие.
    let colorComponents: [CGFloat]?

    var color: Color {
        guard let colorComponents, colorComponents.count >= 3 else { return .accentColor }
        return Color(
            red: Double(colorComponents[0]),
            green: Double(colorComponents[1]),
            blue: Double(colorComponents[2])
        )
    }

    var symbol: String {
        switch source {
        case .event: return link == nil ? "calendar" : "video.fill"
        case .reminder: return "checklist"
        case .things: return "checkmark.circle"
        }
    }

    func minutesUntilStart(from date: Date = Date()) -> Int {
        Int((start.timeIntervalSince(date) / 60).rounded(.down))
    }

    /// «5 мин», «сейчас», «1 ч 20 мин».
    ///
    /// Без слова «через»: отсчёт живёт в полоске по бокам от чёлки, и каждое
    /// лишнее слово раздвигает её на свою ширину в обе стороны сразу —
    /// остров обязан оставаться симметричным относительно выреза.
    func countdown(from date: Date = Date()) -> String {
        let seconds = start.timeIntervalSince(date)
        if seconds <= 30 { return t("сейчас") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return tf("%d мин", minutes) }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? tf("%d ч", hours) : tf("%d ч %d мин", hours, rest)
    }

    /// Адрес, по которому запись открывается в своём приложении.
    ///
    /// У задач Things идентификатор синтетический — он собран нами из
    /// названия и времени, потому что сам Things наружу его не отдаёт.
    /// Открыть по нему конкретную задачу нельзя, поэтому там `nil`,
    /// а вызывающий показывает список на сегодня.
    var appURL: URL? {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        switch source {
        case .event:
            return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
        case .reminder:
            return URL(string: "x-apple-reminderkit://REMCDReminder/\(encoded)")
        case .things:
            return nil
        }
    }

    var timeLabel: String {
        guard !isAllDay else { return t("весь день") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }
}
