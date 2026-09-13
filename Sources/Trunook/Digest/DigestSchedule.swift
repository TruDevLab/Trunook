import Foundation

/// Когда собирать сводку: дни недели и время.
///
/// Чистый тип под тестом, как `UpdateSchedule`: расписание ломается тихо,
/// а проверить его живьём — значит прождать утро.
struct DigestSchedule: Codable, Equatable {
    /// Дни недели в счёте `Calendar`: 1 — воскресенье, 2 — понедельник.
    var weekdays: Set<Int> = Set(1...7)
    var hour: Int = 10
    var minute: Int = 0

    static let key = "digestSchedule"

    /// Самый широкий период поиска. Сводка раз в неделю ищет за неделю,
    /// а после месяца выключенного компьютера — всё равно за неделю: старее
    /// это уже не новости.
    static let longestPeriod: TimeInterval = 7 * 24 * 60 * 60
    /// Самый узкий. Ручная сборка в девять и плановая в десять не должны
    /// дать плановой один час новостей.
    static let shortestPeriod: TimeInterval = 24 * 60 * 60

    /// Последний срок по расписанию, не позже `now`. Ищется на неделю назад:
    /// дальше хотя бы один выбранный день встретится обязательно.
    func latestOccurrence(atOrBefore now: Date, calendar: Calendar = .current) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        for back in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let moment = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  moment <= now
            else { continue }
            return moment
        }
        return nil
    }

    /// Пора ли собирать.
    ///
    /// Срок пропущен, пока компьютер спал, — сводка соберётся при пробуждении,
    /// **один раз**, а не за каждый пропущенный день: `last` после сборки
    /// встаёт на «сейчас», и прошлые сроки остаются позади.
    func isDue(now: Date, last: Date, calendar: Calendar = .current) -> Bool {
        guard let moment = latestOccurrence(atOrBefore: now, calendar: calendar) else { return false }
        return moment > last
    }

    /// От какого времени считать расписание.
    ///
    /// Без прошлой сборки — от «сейчас»: включив сводку в три часа дня,
    /// человек не ждёт, что утренняя соберётся тут же. Дата из будущего
    /// значит, что часы перевели назад, — тогда тоже от «сейчас», иначе
    /// сводка замолчала бы до того дня.
    static func anchor(now: Date, last: Date?) -> Date {
        guard let last, last <= now else { return now }
        return last
    }

    /// С какого времени искать новости.
    static func since(now: Date, last: Date?) -> Date {
        let widest = now.addingTimeInterval(-longestPeriod)
        let narrowest = now.addingTimeInterval(-shortestPeriod)
        guard let last, last <= now else { return narrowest }
        return max(widest, min(last, narrowest))
    }
}
