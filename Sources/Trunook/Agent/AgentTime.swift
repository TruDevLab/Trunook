import Foundation

/// Разбор времени, присланного моделью.
///
/// Самый вероятный способ сломать всю затею — модель, выдумавшая дату
/// или часовой пояс. Промах молчаливый: встреча просто ложится не туда,
/// и узнают об этом, когда на неё опоздают. Защиты три, и они разные
/// по природе.
///
/// **Первая — формат.** Просим `ГГГГ-ММ-ДД ЧЧ:ММ` и ничего больше: без
/// буквы `T`, без `Z`, без смещения. Строка, не несущая сведений о поясе,
/// не может быть сдвинута ошибкой в поясе — мы всегда читаем её местной.
/// ISO-8601, наоборот, заставляет модель гадать про смещение, и промах
/// на три часа приходит без единого признака.
///
/// **Вторая — `stamp`.** Модель не знает, какое сегодня число: она считает
/// от даты своего обучения. Поэтому «сейчас» называется словами в системной
/// реплике, вместе с поясом.
///
/// **Третья — `rollingForward`.** Модель, обученная до 2025-го, пишет
/// «2024-09-12» на «двенадцатое сентября». Встреча уезжает на два года
/// назад и исчезает из календаря. Но правку года просят **не все**: у дел
/// на прошедший день спрашивают законно, и перекатывать такой запрос
/// вперёд значило бы отвечать не о том. Поэтому `parse` год не трогает,
/// а перекатывают его только те инструменты, которые пишут будущее.
enum AgentTime {
    /// Что модель прислала временем.
    struct Moment: Equatable {
        let date: Date
        /// Времени в строке не было — только дата.
        let isDateOnly: Bool
        /// Год пришлось поправить: модель назвала прошедший день.
        var yearRepaired = false
    }

    /// Канонический вид, который просим у модели.
    static let format = "ГГГГ-ММ-ДД ЧЧ:ММ"

    // MARK: - Разбор

    /// Разбирает всё, что модель может прислать вместо канонического вида.
    ///
    /// Терпим пять написаний сверх канона, потому что маленькая модель
    /// сбивается на привычный ей ISO, а отказ человек прочитает как
    /// «помощник не работает», а не как «модель ошиблась буквой `T`».
    ///
    /// Написание со смещением (`…Z`, `…+03:00`) читается **как абсолютный
    /// миг**: пояс назван нарочно, и подменять его местным значило бы
    /// спорить с тем, что сказано прямо. Отличить «модель имела в виду UTC»
    /// от «модель приписала лишнюю `Z`» не может ни один разборщик —
    /// и это ровно тот случай, ради которого заведена карточка
    /// подтверждения: последним рубежом стоит человек, читающий время
    /// своими глазами.
    static func parse(
        _ text: String,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale? = nil
    ) -> Moment? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Сперва — день, названный словом: «завтра», «понедельник».
        //
        // Считать дату по названию дня недели модель не умеет, и это
        // не придирка: на «а на понедельник?» в субботу двенадцатого она
        // прислала тринадцатое — воскресенье, — а потом заявила, что
        // следующий понедельник девятнадцатого, хотя это суббота.
        // Арифметику у неё надо забирать, а не перепроверять: назвать день
        // она умеет, посчитать — нет.
        if let named = relative(raw, now: now, calendar: calendar, locale: locale) {
            return named
        }

        if hasZone(raw), let instant = absolute(raw) {
            return Moment(date: instant, isDateOnly: false)
        }

        // `T` между датой и временем и секунды в хвосте убираем: ни то
        // ни другое ничего не добавляет, а разборов плодит вдвое больше.
        var plain = raw.replacingOccurrences(of: "T", with: " ")
        plain = plain.replacingOccurrences(of: "т", with: " ")
        plain = plain.trimmingCharacters(in: .whitespaces)

        if let date = date(plain, format: "yyyy-MM-dd HH:mm:ss", calendar: calendar) {
            return Moment(date: date, isDateOnly: false)
        }
        if let date = date(plain, format: "yyyy-MM-dd HH:mm", calendar: calendar) {
            return Moment(date: date, isDateOnly: false)
        }
        if let date = date(plain, format: "yyyy-MM-dd", calendar: calendar) {
            return Moment(date: calendar.startOfDay(for: date), isDateOnly: true)
        }
        if let clock = time(plain, calendar: calendar) {
            return Moment(date: next(clock, after: now, calendar: calendar), isDateOnly: false)
        }
        return nil
    }

    /// Перекатывает названный день на ближайший такой же впереди.
    ///
    /// Просят этого только те инструменты, которые заводят будущее:
    /// встречу и напоминание. Читающим это противопоказано — «что было
    /// первого сентября» перекатилось бы на следующий год.
    ///
    /// Сутки допуска, а не ноль: «сегодня в 10:00», сказанное в 10:30, —
    /// это оговорка о сегодняшнем дне, а не о следующем годе.
    static func rollingForward(_ moment: Moment, now: Date, calendar: Calendar = .current) -> Moment {
        let slack = now.addingTimeInterval(-24 * 3600)
        guard moment.date < slack else { return moment }

        for years in 1...3 {
            guard let moved = calendar.date(byAdding: .year, value: years, to: moment.date) else { continue }
            if moved >= slack {
                return Moment(date: moved, isDateOnly: moment.isDateOnly, yearRepaired: true)
            }
        }
        return moment
    }

    /// Число минут в разумных пределах. Модель присылает и ноль, и тысячу.
    static func minutes(_ raw: Int?, default fallback: Int, in range: ClosedRange<Int>) -> Int {
        guard let raw else { return fallback }
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    // MARK: - Словами

    /// Как время выглядит на карточке подтверждения: «12 сент, сб, 15:00».
    ///
    /// Читает это человек, решая, то ли поняла модель, — поэтому день
    /// недели стоит рядом с числом. «Двенадцатое» ни о чём не говорит,
    /// «суббота» говорит сразу.
    static func humanize(
        _ date: Date,
        isDateOnly: Bool,
        calendar: Calendar = .current,
        locale: Locale? = nil,
        now: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale ?? Localization.shared.resolved.locale
        formatter.timeZone = calendar.timeZone
        // Год показывается, только когда он **не** нынешний.
        //
        // Без него подпись врёт молча. Модель, не знающая сегодняшнего числа,
        // прислала «2023-10-10», приложение честно прочитало тот день
        // и ответило «Дела на 10 окт.» — и ни человек, ни сама модель
        // не увидели в этой строке ничего странного. С годом это «10 окт.
        // 2023 г.», и вопрос возникает сразу.
        var template = isDateOnly ? "dMMMEEE" : "dMMMEEEHm"
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            template = isDateOnly ? "dMMMyEEE" : "dMMMyEEEHm"
        }
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Насколько далеко от сегодняшнего дня дату ещё можно принять всерьёз.
    ///
    /// Про прошедший день спрашивают законно — «что у меня было в понедельник»
    /// обычный вопрос. Но день, отстоящий больше чем на год, приходит не от
    /// человека: так модель, обученная до 2025-го, подставляет дату своего
    /// обучения вместо сегодняшней. Отличить одно от другого можно только
    /// по расстоянию.
    static let plausibleRange: TimeInterval = 366 * 24 * 3600

    /// Похоже ли, что этот день и правда спрашивали.
    static func isPlausible(_ date: Date, now: Date = Date()) -> Bool {
        abs(date.timeIntervalSince(now)) <= plausibleRange
    }

    /// Строка «сегодня и сейчас» для системного указания.
    ///
    /// Собирается тем же типом, что и разбор, нарочно: указание и разборщик
    /// обязаны говорить об одном формате, а два места разошлись бы на первой
    /// же правке.
    static func stamp(
        now: Date,
        calendar: Calendar = .current,
        locale: Locale? = nil
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale ?? Localization.shared.resolved.locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMMyEEEEHm")
        return formatter.string(from: now)
    }

    // MARK: - Разбор по частям

    /// День, названный словом, а не числом.
    ///
    /// Принимается либо сам день («завтра», «понедельник»), либо день
    /// со временем («завтра 15:00»). «Завтра в три» не принимается нарочно:
    /// разбирать время словами — это уже другая работа, и делать её вполсилы
    /// хуже, чем не делать вовсе. Модель получит отказ и назовёт время
    /// цифрами.
    private static func relative(
        _ text: String,
        now: Date,
        calendar: Calendar,
        locale: Locale?
    ) -> Moment? {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard let head = words.first else { return nil }

        // Время, если оно приписано следом, — только цифрами.
        var clock: DateComponents?
        if words.count == 2 {
            guard let parsed = time(words[1], calendar: calendar) else { return nil }
            clock = parsed
        } else if words.count > 2 {
            return nil
        }

        guard let day = day(named: head, now: now, calendar: calendar, locale: locale) else {
            return nil
        }
        guard let clock else {
            return Moment(date: calendar.startOfDay(for: day), isDateOnly: true)
        }
        let stamped = calendar.date(
            bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day
        ) ?? day
        return Moment(date: stamped, isDateOnly: false)
    }

    private static func day(
        named word: String,
        now: Date,
        calendar: Calendar,
        locale: Locale?
    ) -> Date? {
        // Слова «сегодня» и «завтра» переводятся таблицей: их читает модель,
        // и на английском окне она пришлёт «tomorrow».
        let offsets: [String: Int] = [
            t("сегодня").lowercased(): 0,
            t("завтра").lowercased(): 1,
            t("послезавтра").lowercased(): 2,
            t("вчера").lowercased(): -1,
        ]
        if let shift = offsets[word] {
            return calendar.date(byAdding: .day, value: shift, to: now)
        }

        // Названия дней недели берутся у системы, а не выписываются списком:
        // выписанные, они разошлись бы с языком интерфейса на первом же
        // переключении.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale ?? Localization.shared.resolved.locale
        let names = (formatter.weekdaySymbols ?? []).map { $0.lowercased() }
        let short = (formatter.shortWeekdaySymbols ?? []).map { $0.lowercased() }
        guard let index = names.firstIndex(of: word) ?? short.firstIndex(of: word) else {
            return nil
        }

        // Ближайший такой день, считая сегодняшний: «понедельник»,
        // сказанное в понедельник, — это сегодня, а не через неделю.
        let wanted = index + 1
        let today = calendar.component(.weekday, from: now)
        let ahead = (wanted - today + 7) % 7
        return calendar.date(byAdding: .day, value: ahead, to: now)
    }

    /// Ближайшая неделя словами — для системного указания.
    ///
    /// Чтобы модели не приходилось считать вовсе: названный день она найдёт
    /// в этом же списке готовым.
    static func week(
        now: Date,
        calendar: Calendar = .current,
        locale: Locale? = nil,
        days: Int = 7
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale ?? Localization.shared.resolved.locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.calendar = calendar
        iso.timeZone = calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"

        return (0..<max(1, days)).compactMap { shift -> String? in
            guard let date = calendar.date(byAdding: .day, value: shift, to: now) else { return nil }
            return formatter.string(from: date) + " — " + iso.string(from: date)
        }.joined(separator: "; ")
    }

    /// Есть ли в строке пояс.
    ///
    /// Смотрим **только хвост после `ГГГГ-ММ-ДД`**: дефисы внутри самой
    /// даты к поясу отношения не имеют, и поиск по всей строке объявил бы
    /// поясом каждую вторую дату.
    private static func hasZone(_ text: String) -> Bool {
        if text.hasSuffix("Z") || text.hasSuffix("z") { return true }
        guard text.count > 10 else { return false }
        let tail = text.dropFirst(10)
        return tail.contains("+") || tail.contains("-")
    }

    /// Абсолютный миг: пояс назван, и мы его слушаем.
    ///
    /// Своим разбором, а не `ISO8601DateFormatter`: тот требует секунд,
    /// а модель их обычно не пишет — `2026-09-12T15:00+03:00` он не берёт
    /// вовсе, и строка со смещением молча свалилась бы в разбор местного
    /// времени, то есть ровно в ту ошибку, от которой всё это заведено.
    private static func absolute(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mmXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mmXXXXX",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func date(_ text: String, format: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        // Разбор — не показ: раскладка человека здесь только помешала бы,
        // а `en_US_POSIX` читает образец буквально и всегда одинаково.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    /// Одно только время: «15:00».
    private static func time(_ text: String, calendar: Calendar) -> DateComponents? {
        let parts = text.split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return DateComponents(hour: hour, minute: minute)
    }

    /// Ближайшее такое время впереди: сегодня, а если оно уже прошло —
    /// завтра. Названное одним временем «в три» не может значить «вчера».
    private static func next(_ clock: DateComponents, after now: Date, calendar: Calendar) -> Date {
        let today = calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: 0,
            of: now
        ) ?? now
        guard today <= now else { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
