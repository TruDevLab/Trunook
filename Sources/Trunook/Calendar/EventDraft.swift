import Foundation

/// Событие, открытое на правку.
///
/// Плоская запись, а не `EKEvent`: у `EKEvent` есть хозяин — хранилище, — и,
/// правя его поля прямо в вёрстке, мы правили бы настоящую запись человека
/// до того, как он нажал «Сохранить». Отказ от правки тогда пришлось бы
/// откатывать вручную, а половина откатов однажды не сходится.
///
/// Здесь же становится возможным то, ради чего вся правка и затевалась:
/// поля меняются кнопками, а не набором в поле даты. Разбирать «12.09.2026»
/// из строки — работа, которая ломается на каждой второй раскладке; шаг
/// стрелкой не ломается никогда.
struct EventDraft: Equatable {
    /// Участник встречи. Только для чтения: `EventKit` списка приглашённых
    /// менять не даёт вовсе — ни добавить, ни убрать. Приглашения рассылает
    /// сервер календаря, и стороннему приложению этой двери не открыли.
    struct Attendee: Equatable, Identifiable {
        let name: String
        let status: Status
        /// Это я. Себя в списке видеть незачем — но и молча выкидывать нельзя:
        /// по своей строке видно, что ответ уже дан.
        let isMe: Bool

        var id: String { name + status.rawValue }

        enum Status: String, Equatable {
            case accepted
            case declined
            case tentative
            case pending

            var symbol: String {
                switch self {
                case .accepted: return "checkmark.circle.fill"
                case .declined: return "xmark.circle.fill"
                case .tentative: return "questionmark.circle.fill"
                case .pending: return "clock"
                }
            }

            var title: String {
                switch self {
                case .accepted: return t("придёт")
                case .declined: return t("отказался")
                case .tentative: return t("может быть")
                case .pending: return t("не ответил")
                }
            }
        }
    }

    /// `nil` — событие ещё не заведено.
    let id: String?
    var title: String
    var start: Date
    /// Сколько событие длится. Хранится длительностью, а не концом: сдвигая
    /// начало, человек ждёт, что встреча поедет целиком, а не растянется.
    var duration: TimeInterval
    var isAllDay: Bool
    var location: String
    /// Описание события.
    var notes: String
    let link: MeetingLink?
    /// В каком календаре событие живёт.
    ///
    /// Правится: до этого новое событие молча уходило туда, куда решало
    /// приложение, — в системный календарь по умолчанию, а если он был снят
    /// в списке показываемых, то в первый попавшийся. Узнать об этом можно
    /// было, только открыв Календарь.
    var calendarID: String?
    /// Цвет календаря — им помечена карточка правки.
    let colorComponents: [CGFloat]?
    /// Приглашённые. Пустой список — либо встреча личная, либо календарь
    /// приглашённых не отдаёт.
    let attendees: [Attendee]

    /// Событие повторяется. От этого зависит, что вообще значит «сохранить»:
    /// одно вхождение или весь ряд.
    let isRecurring: Bool

    /// Правится весь ряд, а не одно вхождение.
    ///
    /// По умолчанию **нет**. Разница молчаливая и необратимая: перенеся
    /// одну встречу на час, человек не ждёт, что переедут все прошлые
    /// и будущие тоже, — а откатить это в Календаре потом нечем.
    var editsSeries = false

    /// Когда вхождение начиналось, когда его открыли.
    ///
    /// Нужно, чтобы найти в хранилище **именно его**: у всех вхождений
    /// повторяющегося события один и тот же идентификатор, и поиск по нему
    /// отдаёт первое, а не то, по которому нажали.
    let originalStart: Date?

    var isNew: Bool { id == nil }

    var end: Date { start.addingTimeInterval(duration) }

    /// Шаг правки времени и длительности.
    ///
    /// Четверть часа: встречи назначают на круглые четверти, и шаг в минуту
    /// потребовал бы шестидесяти нажатий там, где хватает четырёх.
    static let step: TimeInterval = 15 * 60
    /// Сколько длится встреча, заведённая с нуля.
    static let defaultDuration: TimeInterval = 3600

    /// Новое событие на выбранный день.
    ///
    /// Час выбирается не «сейчас», а ближайший будущий круглый: заводя
    /// событие, назначают его вперёд, и время «14:37» пришлось бы править
    /// в любом случае. На чужой день — десять утра: угадывать там нечего,
    /// а начало рабочего дня промахивается реже всего.
    static func blank(
        on day: Date,
        calendarID: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> EventDraft {
        EventDraft(
            id: nil,
            title: "",
            start: suggestedStart(on: day, now: now, calendar: calendar),
            duration: defaultDuration,
            isAllDay: false,
            location: "",
            notes: "",
            link: nil,
            calendarID: calendarID,
            colorComponents: nil,
            attendees: [],
            isRecurring: false,
            originalStart: nil
        )
    }

    static func suggestedStart(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard calendar.isDate(day, inSameDayAs: now) else {
            return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
        }
        let rounded = Date(
            timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        )
        // Округление вверх поздним вечером выносит событие в завтра — а день
        // человек только что выбрал сам, ткнув в клетку месяца. Поймано
        // в 23:48: «плюс» на сегодняшнем дне заводил событие на седьмое.
        // Уехавшее прижимается к последней четверти того же дня.
        guard calendar.isDate(rounded, inSameDayAs: day) else {
            return calendar.date(bySettingHour: 23, minute: 45, second: 0, of: day) ?? day
        }
        return rounded
    }

    /// Сдвинуть начало на шаг. Длительность едет вместе с ним.
    func movingStart(bySteps steps: Int) -> EventDraft {
        var copy = self
        copy.start = start.addingTimeInterval(Self.step * Double(steps))
        return copy
    }

    /// Сдвинуть день, не трогая часа.
    func movingDay(by days: Int, calendar: Calendar = .current) -> EventDraft {
        var copy = self
        copy.start = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return copy
    }

    /// Растянуть или сжать. Меньше шага событие не бывает: нулевая
    /// длительность в календаре выглядит поломкой, а не пометкой.
    func stretched(bySteps steps: Int) -> EventDraft {
        var copy = self
        copy.duration = max(Self.step, duration + Self.step * Double(steps))
        return copy
    }

    /// «1 ч 30 мин», «45 мин», «2 ч».
    var durationLabel: String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tf("%d мин", rest) }
        return rest == 0 ? tf("%d ч", hours) : tf("%d ч %d мин", hours, rest)
    }

    /// Пустое название сохранять нельзя: список показывает имена, и событие
    /// без имени в нём неотличимо от любого другого безымянного.
    var isSavable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
