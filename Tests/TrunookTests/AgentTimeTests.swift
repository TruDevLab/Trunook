import Foundation
import Testing
@testable import Trunook

@Suite("Время, присланное моделью")
struct AgentTimeTests {
    /// Свой календарь с закреплённым поясом — иначе ответ менялся бы
    /// от того, в какой стране запустили тест. Тем же приёмом устроены
    /// `CalendarMonthTests`.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }

    /// 11 сентября 2026, пятница, 14:07 по Москве.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 7))!
    }

    private func parts(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test("Канонический вид разбирается местным временем")
    func канонРазбираетсяМестным() throws {
        let moment = try #require(AgentTime.parse("2026-09-12 15:00", now: now, calendar: calendar))
        let got = parts(moment.date)
        #expect(got.year == 2026)
        #expect(got.month == 9)
        #expect(got.day == 12)
        #expect(got.hour == 15)
        #expect(got.minute == 0)
        #expect(!moment.isDateOnly)
    }

    /// Маленькая модель сбивается на привычный ей ISO. Отказ человек
    /// прочитал бы как «помощник не работает», а не как «модель приписала
    /// лишнюю букву».
    @Test("Буква T и секунды не мешают")
    func терпимИСОБезПояса() throws {
        for text in ["2026-09-12T15:00", "2026-09-12T15:00:00", "2026-09-12 15:00:00"] {
            let moment = try #require(
                AgentTime.parse(text, now: now, calendar: calendar),
                "не разобрано: \(text)"
            )
            #expect(parts(moment.date).hour == 15, "не то время у \(text)")
            #expect(parts(moment.date).day == 12, "не тот день у \(text)")
        }
    }

    /// Пояс назван нарочно — спорить с прямо сказанным нельзя. 15:00 UTC
    /// это 18:00 по Москве, и именно это увидит человек на карточке.
    @Test("Названный пояс слушается, а не подменяется местным")
    func поясСлушается() throws {
        for text in ["2026-09-12T15:00Z", "2026-09-12T15:00:00Z", "2026-09-12T15:00+00:00"] {
            let moment = try #require(
                AgentTime.parse(text, now: now, calendar: calendar),
                "не разобрано: \(text)"
            )
            #expect(parts(moment.date).hour == 18, "пояс потерян у \(text)")
        }
    }

    /// Дефисы внутри самой даты к поясу отношения не имеют. Поиск знака
    /// по всей строке объявил бы поясом каждую вторую дату — и время
    /// уехало бы на разбор не тем путём.
    @Test("Дефис в дате не считается поясом")
    func дефисВДатеНеПояс() throws {
        let moment = try #require(AgentTime.parse("2026-09-12", now: now, calendar: calendar))
        #expect(moment.isDateOnly)
        #expect(parts(moment.date).day == 12)
        #expect(parts(moment.date).hour == 0)
    }

    /// Названное одним временем «в три» не может значить «вчера».
    @Test("Одно время — ближайшее такое впереди")
    func одноВремяЕдетВперёд() throws {
        let ahead = try #require(AgentTime.parse("15:00", now: now, calendar: calendar))
        #expect(parts(ahead.date).day == 11, "15:00 ещё впереди — это сегодня")

        let passed = try #require(AgentTime.parse("09:30", now: now, calendar: calendar))
        #expect(parts(passed.date).day == 12, "09:30 уже прошло — значит завтра")
    }

    /// Модель, обученная до 2025-го, пишет «2024-09-12» на «двенадцатое
    /// сентября». Встреча уезжает на два года назад и просто исчезает
    /// из календаря — ошибка молчаливая, и поймать её человеку нечем.
    @Test("Прошедший год перекатывается вперёд")
    func годПравитсяДляБудущего() throws {
        let parsed = try #require(AgentTime.parse("2024-09-12 15:00", now: now, calendar: calendar))
        #expect(!parsed.yearRepaired, "сам разбор год не трогает")

        let rolled = AgentTime.rollingForward(parsed, now: now, calendar: calendar)
        #expect(rolled.yearRepaired)
        #expect(parts(rolled.date).year == 2026)
        #expect(parts(rolled.date).day == 12)
    }

    /// «Сегодня в 10:00», сказанное в 10:30, — это оговорка о сегодняшнем
    /// дне, а не о следующем годе. Сутки допуска.
    @Test("Сегодняшнее утро вперёд не катится")
    func сегодняшнееУтроОстаётся() throws {
        let parsed = try #require(AgentTime.parse("2026-09-11 10:00", now: now, calendar: calendar))
        let rolled = AgentTime.rollingForward(parsed, now: now, calendar: calendar)
        #expect(!rolled.yearRepaired)
        #expect(parts(rolled.date).year == 2026)
        #expect(parts(rolled.date).day == 11)
    }

    /// У дел на прошедший день спрашивают законно. Перекатывать такой
    /// запрос вперёд значило бы ответить не о том — поэтому читающие
    /// инструменты `rollingForward` не зовут, и `parse` год не трогает.
    @Test("Разбор сам по себе прошлое не правит")
    func разборПрошлоеНеТрогает() throws {
        let moment = try #require(AgentTime.parse("2026-09-01", now: now, calendar: calendar))
        #expect(parts(moment.date).month == 9)
        #expect(parts(moment.date).day == 1)
        #expect(parts(moment.date).year == 2026)
        #expect(!moment.yearRepaired)
    }

    /// Пойман на живых данных. На «что у меня сегодня» модель прислала
    /// `2023-10-10` — дату своего обучения, — приложение честно прочитало
    /// тот день и ответило расписанием за позапрошлый год. Про прошедший
    /// день спрашивают законно, поэтому разбор его не правит; отличить
    /// вопрос от промаха можно только по расстоянию до сегодняшнего дня.
    @Test("День не из этого времени видно по расстоянию")
    func дальняяДатаНеОтЧеловека() throws {
        let stale = try #require(AgentTime.parse("2023-10-10", now: now, calendar: calendar))
        #expect(!AgentTime.isPlausible(stale.date, now: now))

        // А вот эти спрашивают всерьёз — и правка бы им только помешала.
        for text in ["2026-09-01", "2026-09-11", "2026-12-31", "2025-10-10"] {
            let asked = try #require(AgentTime.parse(text, now: now, calendar: calendar))
            #expect(AgentTime.isPlausible(asked.date, now: now), "отвергли живой вопрос: \(text)")
        }
    }

    /// Без года подпись врёт молча: «Дела на 10 окт.» выглядит безобидно
    /// и тогда, когда речь про позапрошлый год. В нынешнем году год, наоборот,
    /// только шум — его и так знают.
    @Test("Год в подписи появляется, только когда он не нынешний")
    func годВПодписиТолькоЧужой() throws {
        let ru = Locale(identifier: "ru_RU")
        let thisYear = try #require(AgentTime.parse("2026-09-12", now: now, calendar: calendar))
        let text = AgentTime.humanize(
            thisYear.date, isDateOnly: true, calendar: calendar, locale: ru, now: now
        )
        #expect(!text.contains("2026"), "нынешний год в подписи лишний: «\(text)»")

        let other = try #require(AgentTime.parse("2023-10-10", now: now, calendar: calendar))
        let stale = AgentTime.humanize(
            other.date, isDateOnly: true, calendar: calendar, locale: ru, now: now
        )
        #expect(stale.contains("2023"), "чужой год потерян: «\(stale)»")
    }

    /// Пойман на живых данных, и это худший случай из всех: ошибки нет
    /// нигде. В субботу двенадцатого на «а на понедельник?» модель прислала
    /// `2026-09-13` — воскресенье, — а потом заявила, что следующий
    /// понедельник девятнадцатого, хотя это суббота. Считать дни недели
    /// она не умеет; называть их — умеет. Арифметику надо забирать.
    @Test("День недели словом разбирается сам")
    func деньНеделиСловом() throws {
        let ru = Locale(identifier: "ru_RU")
        // 11 сентября 2026 — пятница, значит понедельник это 14-е.
        let monday = try #require(
            AgentTime.parse("понедельник", now: now, calendar: calendar, locale: ru)
        )
        #expect(parts(monday.date).day == 14)
        #expect(monday.isDateOnly)

        let tomorrow = try #require(
            AgentTime.parse("завтра", now: now, calendar: calendar, locale: ru)
        )
        #expect(parts(tomorrow.date).day == 12)

        let today = try #require(
            AgentTime.parse("сегодня", now: now, calendar: calendar, locale: ru)
        )
        #expect(parts(today.date).day == 11)
    }

    /// Названный день — это ближайший такой впереди, считая сегодняшний:
    /// «пятница», сказанная в пятницу, — это сегодня, а не через неделю.
    @Test("Сегодняшний день недели означает сегодня")
    func сегодняшнийДеньЭтоСегодня() throws {
        let friday = try #require(AgentTime.parse(
            "пятница", now: now, calendar: calendar, locale: Locale(identifier: "ru_RU")
        ))
        #expect(parts(friday.date).day == 11)
    }

    /// День словом плюс время цифрами. «Завтра в три» — не принимается:
    /// разбирать время словами это другая работа, и вполсилы она хуже,
    /// чем никак.
    @Test("К названному дню можно приписать время цифрами")
    func деньСловомИВремяЦифрами() throws {
        let ru = Locale(identifier: "ru_RU")
        let moment = try #require(
            AgentTime.parse("завтра 15:00", now: now, calendar: calendar, locale: ru)
        )
        #expect(parts(moment.date).day == 12)
        #expect(parts(moment.date).hour == 15)
        #expect(!moment.isDateOnly)

        #expect(AgentTime.parse("завтра в три", now: now, calendar: calendar, locale: ru) == nil)
    }

    /// Список ближайших дней уходит модели в системной реплике — чтобы
    /// считать ей не приходилось вовсе: названный день она найдёт готовым.
    @Test("Ближайшие дни названы и днём недели, и датой")
    func неделяНазванаЦеликом() {
        let text = AgentTime.week(
            now: now, calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        #expect(text.contains("2026-09-11"))
        #expect(text.contains("2026-09-14"))
        #expect(text.lowercased().contains("понедельник"))
    }

    @Test("Мусор не разбирается вовсе")
    func мусорОтвергается() {
        for text in ["", "   ", "завтра в три", "12 сентября", "не время", "25:99", "2026-13-45"] {
            #expect(
                AgentTime.parse(text, now: now, calendar: calendar) == nil,
                "разобралось то, что не должно: «\(text)»"
            )
        }
    }

    @Test("Длительность обрезается по краям")
    func длительностьОбрезается() {
        #expect(AgentTime.minutes(nil, default: 60, in: 1...600) == 60)
        #expect(AgentTime.minutes(0, default: 60, in: 1...600) == 1)
        #expect(AgentTime.minutes(5000, default: 60, in: 1...600) == 600)
        #expect(AgentTime.minutes(25, default: 60, in: 1...600) == 25)
    }

    /// Карточку читает человек, решая, то ли поняла модель. «Двенадцатое»
    /// ни о чём не говорит, «суббота» говорит сразу.
    @Test("На карточке видно день недели")
    func вПодписиЕстьДеньНедели() throws {
        let moment = try #require(AgentTime.parse("2026-09-12 15:00", now: now, calendar: calendar))
        let text = AgentTime.humanize(
            moment.date,
            isDateOnly: false,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        )
        #expect(text.contains("12"))
        #expect(text.contains("15:00"))
        #expect(text.lowercased().contains("сб"), "нет дня недели: «\(text)»")
    }

    /// Модель не знает, какое сегодня число: она считает от даты своего
    /// обучения. «Сейчас» приходится называть словами.
    @Test("Указание называет сегодняшний день")
    func указаниеНазываетСегодня() {
        let text = AgentTime.stamp(now: now, calendar: calendar, locale: Locale(identifier: "ru_RU"))
        #expect(text.contains("2026"))
        #expect(text.contains("11"))
        #expect(text.contains("14:07"))
    }
}
