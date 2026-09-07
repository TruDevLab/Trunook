import Foundation

/// Раскладка месяца: шесть недель по семь дней, у каждой недели свой номер.
///
/// Отдельно от вёрстки и без единого обращения к SwiftUI: «какой день стоит
/// в этой клетке» — вопрос арифметики календаря, а не рисования. Ошибки здесь
/// молчаливые и злые: смещение на день ловится только тем, что человек
/// однажды нажал не на ту дату, а первая неделя года в декабре ломается
/// раз в году. Всё это ловится тестом, а не глазами.
///
/// Шесть недель всегда, даже когда месяц укладывается в пять: панель, меняющая
/// рост при перелистывании, дёргала бы вырез на каждом нажатии стрелки.
struct CalendarMonth: Equatable {
    /// Клетка сетки.
    struct Day: Equatable, Identifiable {
        /// Полночь этого дня.
        let date: Date
        let number: Int
        /// Свой день месяца или хвост соседнего.
        ///
        /// Хвосты рисуются бледными, но остаются нажимаемыми: перейти
        /// к первому числу следующего месяца, ткнув в него, — то же самое
        /// движение, что и перелистнуть, только короче.
        let isInMonth: Bool

        var id: Date { date }
    }

    /// Строка сетки: номер недели и семь дней.
    struct Week: Equatable, Identifiable {
        /// Номер недели в году — то, что стоит в левой колонке.
        let number: Int
        let days: [Day]

        /// Не номер недели: в шестинедельном окне через Новый год номера
        /// идут 52, 1, 2 — они не повторяются, но опираться на это, когда
        /// под рукой есть заведомо уникальная дата, незачем.
        var id: Date { days.first?.date ?? .distantPast }
    }

    /// Полночь первого числа месяца.
    let anchor: Date
    let weeks: [Week]

    static let rows = 6

    static func make(monthOf date: Date, calendar: Calendar = .current) -> CalendarMonth {
        let anchor = firstDay(ofMonthOf: date, calendar: calendar)
        // Сетка начинается не с первого числа, а с начала той недели,
        // в которую оно попало: иначе первый день месяца встал бы в колонку
        // понедельника, каким бы днём недели он ни был.
        let gridStart = startOfWeek(for: anchor, calendar: calendar)
        let month = calendar.component(.month, from: anchor)

        var weeks: [Week] = []
        for row in 0..<rows {
            guard let weekStart = calendar.date(byAdding: .day, value: row * 7, to: gridStart) else {
                continue
            }
            let days = (0..<7).compactMap { offset -> Day? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                    return nil
                }
                return Day(
                    date: day,
                    number: calendar.component(.day, from: day),
                    isInMonth: calendar.component(.month, from: day) == month
                )
            }
            weeks.append(Week(
                number: calendar.component(.weekOfYear, from: weekStart),
                days: days
            ))
        }
        return CalendarMonth(anchor: anchor, weeks: weeks)
    }

    /// Соседний месяц — то, куда ведут стрелки в шапке.
    static func shifted(_ anchor: Date, byMonths months: Int, calendar: Calendar = .current) -> Date {
        let moved = calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
        return firstDay(ofMonthOf: moved, calendar: calendar)
    }

    static func firstDay(ofMonthOf date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// Подписи колонок — короткие имена дней с той же первой, что и в сетке.
    ///
    /// Берутся у системы, а не выписаны строкой: первый день недели у разных
    /// стран разный, и заголовок, начинающийся с понедельника над сеткой,
    /// начинающейся с воскресенья, — это ошибка, которую видно только там,
    /// где мы её не проверяем.
    static func weekdayTitles(calendar: Calendar = .current) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Localization.shared.resolved.locale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.shortStandaloneWeekdaySymbols
            ?? ["1", "2", "3", "4", "5", "6", "7"]
        let shift = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + shift) % symbols.count] }
    }

    /// «Сентябрь 2026» — заголовок над сеткой.
    static func title(of anchor: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Localization.shared.resolved.locale
        // Формат прямой, а не собранный из шаблона: в русском шаблон
        // добавляет «г.» после года — «Сентябрь 2026 г.», — и заголовок
        // из двух слов становится заголовком из трёх ради сокращения,
        // которое в календаре не значит ничего.
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: anchor).capitalizedFirst
    }
}

extension String {
    /// Первая буква прописной, остальное как было.
    ///
    /// `capitalized` не годится: он трогает **каждое** слово, и «Сентябрь
    /// 2026» ещё переживёт, а «12 Сентября» уже нет.
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
