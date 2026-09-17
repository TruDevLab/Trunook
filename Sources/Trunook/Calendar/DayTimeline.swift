import Foundation

/// Каким показывать дела дня: списком строк или шкалой времени.
///
/// Список отвечает на «что сегодня есть», шкала — на «как лежит день»:
/// где пусто, где встречи идут подряд и где две наложились друг на друга.
/// Второго списком не показать никак — строки одинаковой высоты врут
/// о длительности, а одновременные дела в них выглядят последовательными.
enum CalendarDayView: String, CaseIterable, Identifiable {
    case list
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return t("Списком")
        case .timeline: return t("Шкалой времени")
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .timeline: return "calendar.day.timeline.left"
        }
    }

    /// Другое из двух.
    ///
    /// Представлений ровно два, поэтому в крыле стоит одна кнопка, а не
    /// сегментный переключатель: выбирать не из чего, есть только «не это».
    /// Переключатель занял бы крыло целиком и оставил бы панель без крестика.
    var other: CalendarDayView { self == .list ? .timeline : .list }

    /// Подпись кнопки, которая к этому представлению переключает.
    ///
    /// Кнопка показывает действие, а не состояние, — как «пауза» у играющего
    /// трека: значок списка означает «показать списком», а не «сейчас
    /// список».
    var switchHint: String {
        switch self {
        case .list: return t("Показать списком")
        case .timeline: return t("Показать шкалой")
        }
    }
}

/// Раскладка дня на шкале времени: какое окно у шкалы и какую полосу
/// занимает каждое дело.
///
/// Без единого обращения к SwiftUI, как и `CalendarMonth`: «во сколько
/// начинается шкала», «какой длины полоса» и «сколько дел стоят рядом,
/// потому что идут одновременно» — вопросы арифметики. Ошибки здесь
/// молчаливые и злые: полоса, уехавшая на полчаса, выглядит настоящим
/// временем встречи, а две наложившиеся друг на друга читаются как одна.
struct DayTimeline: Equatable {
    /// Полоса одного дела.
    struct Block: Equatable, Identifiable {
        /// Номер дела в исходном списке. По номеру, а не по самой записи:
        /// два вхождения одного повторяющегося события в один день делят
        /// идентификатор, и перебор по нему показал бы одну полосу вместо
        /// двух — та же ловушка, что была у списка дня.
        let index: Int
        /// Минуты от полуночи выбранного дня.
        let startMinute: Int
        let endMinute: Int
        /// Столбец среди одновременных и сколько их всего в этой связке.
        let lane: Int
        let lanes: Int

        var id: Int { index }
        var minutes: Int { endMinute - startMinute }
    }

    /// Дела на весь день — номерами в исходном списке.
    ///
    /// Отдельно от полос, а не полосой во всю шкалу: у них нет часа,
    /// и полоса от края до края закрасила бы день целиком, ничего о нём
    /// не сказав.
    let allDay: [Int]
    /// Полосы в порядке начала.
    let blocks: [Block]
    /// Окно шкалы в минутах от полуночи, по целым часам.
    let startMinute: Int
    let endMinute: Int
    /// Где стоит «сейчас». `nil` — день не сегодняшний либо текущее время
    /// за окном шкалы.
    let currentMinute: Int?

    /// Наименьшее окно шкалы. Три часа: день с одной получасовой встречей
    /// не должен превращаться в шкалу из одного деления, где эта встреча
    /// занимает всю высоту и перестаёт быть событием во времени.
    static let minimumSpan = 3 * 60
    /// Наименьшая длина полосы. У напоминания конца нет вовсе, а встреча
    /// в пять минут — нитка: две таких подряд наложились бы, и по шкале это
    /// читалось бы как одно дело.
    ///
    /// Длина живёт здесь, а не в вёрстке: от неё зависит, считаются ли дела
    /// одновременными, — а это уже не рисунок, а раскладка.
    static let minimumBlock = 15
    /// Окно пустого не сегодняшнего дня: рабочий день целиком.
    static let quietStart = 9 * 60
    static let quietEnd = 18 * 60

    var minutes: Int { max(1, endMinute - startMinute) }
    /// Сколько целых часов в окне.
    var hours: Int { max(1, minutes / 60) }

    /// Доля от начала шкалы, 0…1. Переводить минуты в точки — дело вёрстки:
    /// у шкалы в панели и у ленты в плитке разные и высота, и ширина.
    func fraction(of minute: Int) -> Double {
        Double(minute - startMinute) / Double(minutes)
    }

    // MARK: - Сборка

    static func make(
        items: [CalendarItem],
        day: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayTimeline {
        let dayStart = calendar.startOfDay(for: day)
        // Длину суток спрашиваем у календаря, а не берём 1440: в день
        // перевода часов их 23 или 25, и шкала, посчитанная по постоянной,
        // сдвинула бы все дела на час ровно тогда, когда время и без того
        // путается.
        let dayLength = minutes(
            from: dayStart,
            to: calendar.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(86_400)
        )

        var allDay: [Int] = []
        var spans: [(index: Int, start: Int, end: Int)] = []

        for (index, item) in items.enumerated() {
            guard !item.isAllDay else {
                allDay.append(index)
                continue
            }
            // Событие, начавшееся вчера и кончающееся завтра, приходит
            // в список дня целиком: на шкале ему место от края до края,
            // а не за её пределами.
            let from = clamp(minutes(from: dayStart, to: item.start), to: dayLength)
            let plain = item.end.map { clamp(minutes(from: dayStart, to: $0), to: dayLength) } ?? from
            var start = from
            var end = max(plain, from + minimumBlock)
            // Дело у самой полуночи не сплющивается в нитку: полоса
            // не вылезает за конец суток, а поднимается вверх.
            if end > dayLength {
                end = dayLength
                start = max(0, dayLength - minimumBlock)
            }
            spans.append((index, start, end))
        }

        let window = self.window(
            spans: spans,
            dayLength: dayLength,
            currentMinute: calendar.isDate(dayStart, inSameDayAs: now)
                ? clamp(minutes(from: dayStart, to: now), to: dayLength)
                : nil
        )

        return DayTimeline(
            allDay: allDay,
            blocks: lanes(of: spans),
            startMinute: window.start,
            endMinute: window.end,
            currentMinute: window.current
        )
    }

    /// Окно шкалы: от чего до чего её рисовать.
    ///
    /// Не сутки целиком. Двадцать четыре часа — это двадцать три часа
    /// пустоты вокруг одной встречи: всё, что в дне есть, сжимается в полосу
    /// толщиной в пару точек, и шкала перестаёт отвечать на то, ради чего
    /// её открыли.
    private static func window(
        spans: [(index: Int, start: Int, end: Int)],
        dayLength: Int,
        currentMinute: Int?
    ) -> (start: Int, end: Int, current: Int?) {
        var low = spans.map(\.start).min() ?? quietStart
        var high = spans.map(\.end).max() ?? quietEnd
        // «Сейчас» входит в окно всегда, когда день сегодняшний: черта
        // текущего времени — то главное, чем шкала отличается от списка,
        // а черта за краем окна не рисуется вовсе.
        if let currentMinute {
            low = min(low, currentMinute)
            high = max(high, currentMinute)
        }
        // По целым часам: подписи стоят на часах, и окно, начатое в 9:40,
        // поставило бы первую подпись в пустоту над первым делом.
        low = max(0, low - low % 60)
        high = min(dayLength, (high + 59) / 60 * 60)
        if high - low < minimumSpan {
            high = min(dayLength, low + minimumSpan)
            low = max(0, high - minimumSpan)
        }
        return (low, high, currentMinute.flatMap { $0 >= low && $0 <= high ? $0 : nil })
    }

    /// Раскладка одновременных дел по столбцам.
    ///
    /// Связкой, а не попарно: ширина полос считается по всей связке
    /// пересекающихся дел разом — иначе соседние по времени встречи вышли бы
    /// разной ширины, и глаз прочитал бы разницу как разницу в важности.
    private static func lanes(of spans: [(index: Int, start: Int, end: Int)]) -> [Block] {
        // Порядок устойчивый: у двух дел с одинаковым началом столбцы
        // не должны меняться местами от того, как их вернуло хранилище.
        let ordered = spans.sorted {
            $0.start == $1.start ? $0.index < $1.index : $0.start < $1.start
        }

        var blocks: [Block] = []
        var cluster: [(index: Int, start: Int, end: Int, lane: Int)] = []
        var laneEnds: [Int] = []

        func close() {
            let width = max(1, laneEnds.count)
            for entry in cluster {
                blocks.append(Block(
                    index: entry.index,
                    startMinute: entry.start,
                    endMinute: entry.end,
                    lane: entry.lane,
                    lanes: width
                ))
            }
            cluster.removeAll()
            laneEnds.removeAll()
        }

        for span in ordered {
            // Связка кончается там, где очередное дело не задевает ни одного
            // из предыдущих: дальше столбцы можно начинать заново.
            if !laneEnds.isEmpty, laneEnds.allSatisfy({ $0 <= span.start }) { close() }
            let lane = laneEnds.firstIndex { $0 <= span.start } ?? laneEnds.count
            if lane == laneEnds.count {
                laneEnds.append(span.end)
            } else {
                laneEnds[lane] = max(laneEnds[lane], span.end)
            }
            cluster.append((span.index, span.start, span.end, lane))
        }
        close()
        return blocks
    }

    /// Окно не длиннее `hours` часов — вокруг того, на что смотрят.
    ///
    /// Плитка не прокручивается, и день целиком в неё вписывается только
    /// сжатием часа: восемь часов в сотне точек — это одиннадцать точек
    /// на час, то есть пять с половиной на получасовое дело. Название туда
    /// не встаёт никак, и плитка превращается в штрих-код.
    ///
    /// Поэтому в плитке показывается **часть дня, но с названиями**:
    /// сколько часов влезает при читаемой высоте, столько и берётся.
    /// Что не поместилось, плитка считает и пишет числом — «+3»: иначе
    /// обрезанный день читался бы как весь день.
    ///
    /// Начало — там же, где стоит прокрутка панели: «сейчас», а если день
    /// не сегодняшний — первое дело. У конца суток окно прижимается
    /// к концу, а не вылезает за него.
    func limited(to hours: Int) -> DayTimeline {
        let span = max(1, hours) * 60
        guard minutes > span else { return self }
        let anchor = currentMinute ?? blocks.first?.startMinute ?? startMinute
        let low = min(max(startMinute, anchor - anchor % 60), endMinute - span)
        let high = low + span
        return DayTimeline(
            allDay: allDay,
            // Дело, целиком оставшееся за окном, из раскладки убирается:
            // иначе полоса рисовалась бы выше или ниже шкалы, а обрезка
            // вида — не то место, где решают, что показывать.
            blocks: blocks.filter { $0.endMinute > low && $0.startMinute < high },
            startMinute: low,
            endMinute: high,
            currentMinute: currentMinute.flatMap { $0 >= low && $0 <= high ? $0 : nil }
        )
    }

    /// Сколько дел не попало в укороченное окно.
    func hidden(from full: DayTimeline) -> Int {
        max(0, full.blocks.count - blocks.count)
    }

    // MARK: - Подписи

    /// Через сколько часов ставить подпись, чтобы их было не больше, чем
    /// помещается.
    ///
    /// Шаг из ряда делителей суток, а не «часы поделить на число подписей»:
    /// подписи через пять часов читаются как случайные, через шесть —
    /// как четверти дня.
    static func hourStep(hours: Int, fitting labels: Int) -> Int {
        guard labels > 0 else { return max(1, hours) }
        for step in [1, 2, 3, 4, 6, 12] where (hours + step - 1) / step <= labels {
            return step
        }
        return max(1, hours)
    }

    /// Подпись часа: «14». Без минут — они на шкале всегда нулевые,
    /// а «14:00» вдвое шире и в колонке слева не помещается.
    static func hourLabel(minute: Int) -> String {
        String(minute / 60 % 24)
    }

    /// «9:00 – 18:00» — окно шкалы целиком, подписью плитки.
    static func rangeLabel(from: Int, to: Int) -> String {
        String(format: "%d:%02d – %d:%02d", from / 60 % 24, from % 60, to / 60 % 24, to % 60)
    }

    // MARK: - Мелочи

    private static func minutes(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) / 60).rounded())
    }

    private static func clamp(_ minute: Int, to dayLength: Int) -> Int {
        max(0, min(dayLength, minute))
    }
}
