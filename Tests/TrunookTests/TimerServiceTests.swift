import Foundation
import Testing
@testable import Trunook

@Suite("Таймер и секундомер")
struct TimerServiceTests {
    @Test("Запись времени: минуты и секунды, часы — только когда они есть")
    func записьВремени() {
        #expect(TimerService.clock(0) == "00:00")
        #expect(TimerService.clock(59) == "00:59")
        #expect(TimerService.clock(25 * 60) == "25:00")
        #expect(TimerService.clock(3600 + 5 * 60) == "1:05:00")
    }

    /// Секунда округляется вверх: пока хоть доля секунды осталась, на экране
    /// должна стоять единица, а не ноль. Иначе таймер показывает «00:00»
    /// раньше, чем звонит.
    @Test("Неполная секунда показывается целой")
    func округлениеВверх() {
        #expect(TimerService.clock(0.2) == "00:01")
        #expect(TimerService.clock(59.5) == "01:00")
    }

    @Test("Свежая служба ничего не отсчитала")
    func свежаяЧиста() {
        let timer = TimerService()
        #expect(timer.isClean)
        #expect(!timer.isRunning)
        #expect(timer.remaining == TimerService.pomodoro)
    }

    @Test("Пуск и пауза переключают ход")
    func пускПауза() {
        let timer = TimerService()
        timer.toggle()
        #expect(timer.isRunning)
        timer.toggle()
        #expect(!timer.isRunning)
        #expect(!timer.isClean, "пауза не должна выглядеть как нетронутый таймер")
    }

    @Test("Сброс возвращает в исходное")
    func сброс() {
        let timer = TimerService()
        timer.start()
        timer.pause()
        timer.reset()
        #expect(timer.isClean)
        #expect(timer.phase == .work)
    }

    @Test("Готовая длительность заводит таймер и останавливает ход")
    func готоваяДлительность() {
        let timer = TimerService()
        timer.start()
        timer.select(minutes: 5)
        #expect(!timer.isRunning, "выбор длительности на ходу должен остановить прежний отсчёт")
        #expect(timer.duration == 5 * 60)
        #expect(timer.isClean)
    }

    @Test("Смена режима обнуляет отсчёт")
    func сменаРежима() {
        let timer = TimerService()
        timer.start()
        timer.select(mode: .stopwatch)
        #expect(timer.mode == .stopwatch)
        #expect(timer.isClean)
    }

    @Test("«Ещё минута» продлевает, а не запускает заново")
    func продление() {
        let timer = TimerService()
        timer.select(minutes: 5)
        timer.extend()
        #expect(timer.duration == 6 * 60)
    }

    /// Помидоры считаются по работе, а не по перерывам — иначе счётчик
    /// показывал бы вдвое больше сделанного.
    @Test("В секундомере продлевать нечего")
    func секундомерНеПродлевается() {
        let timer = TimerService()
        timer.select(mode: .stopwatch)
        let before = timer.duration
        timer.extend()
        #expect(timer.duration == before)
    }
}

@Suite("Полоска таймера в чёлке")
struct TimerChipTests {
    private func meeting() -> CalendarItem {
        CalendarItem(
            id: "встреча", title: "созвон", start: Date().addingTimeInterval(600),
            end: nil, isAllDay: false, source: .event, link: nil,
            colorComponents: [1, 1, 1]
        )
    }

    @Test("Стоящий таймер чёлку не раздвигает")
    func стоящийНеРаздвигает() {
        let timer = TimerService()
        #expect(timer.chip == nil)
        #expect(NotchInputs().resolve().presentation == .collapsed)
    }

    @Test("Идущий таймер раздвигает свёрнутую чёлку")
    func идущийРаздвигает() {
        let timer = TimerService()
        timer.start()
        #expect(timer.chip != nil)
        #expect(NotchInputs(timerChip: timer.chip).resolve().presentation == .chip)
    }

    /// Таймер завели руками и смотрят на него нарочно, а отсчёт до встречи
    /// всплывает сам — поэтому в одной полосе побеждает таймер.
    @Test("Таймер важнее отсчёта до встречи")
    func таймерВажнееОтсчёта() {
        let timer = TimerService()
        timer.start()
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let both = NotchInputs(chip: meeting(), timerChip: timer.chip).resolve()
        #expect(both.presentation == .chip)
        #expect(both.size(metrics: metrics).width
                == TimerChipView.width(metrics: metrics, showsHours: false))
    }

    @Test("Часы делают полоску шире")
    func часыШире() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        #expect(TimerChipView.width(metrics: metrics, showsHours: true)
                > TimerChipView.width(metrics: metrics, showsHours: false))
    }
}

@Suite("Нагрузка на систему")
struct MonitorServiceTests {
    /// Доля процессора считается разностью счётчиков, и по одному замеру
    /// её не существует. Ноль здесь читался бы как «процессор простаивает»,
    /// хотя это «ещё не знаем».
    @Test("До первого промежутка доли процессора нет")
    func процессорМолчитДоВторогоЗамера() {
        #expect(MonitorService().sample.cpu == nil)
    }

    @Test("Память и диск читаются с первого раза")
    func памятьИДискЧитаются() {
        let monitor = MonitorService()
        monitor.start()
        defer { monitor.stop() }
        #expect(monitor.sample.memoryTotal > 0, "объём памяти не прочитан")
        #expect(monitor.sample.memoryUsed > 0, "занятая память не прочитана")
        #expect(monitor.sample.diskTotal > 0, "объём диска не прочитан")
        #expect(monitor.sample.memoryShare > 0 && monitor.sample.memoryShare <= 1)
        #expect(monitor.sample.diskShare > 0 && monitor.sample.diskShare <= 1)
    }

    /// Опрос идёт только пока панель открыта, поэтому остановка обязана
    /// забыть счётчики: иначе первое значение после долгого перерыва было бы
    /// средним за всё время простоя — и выглядело бы как правда.
    @Test("Остановка забывает набранное по процессору")
    func остановкаЗабывает() {
        let monitor = MonitorService()
        monitor.start()
        monitor.stop()
        #expect(monitor.sample.cpu == nil)
    }

    @Test("Доли не выходят за границы")
    func долиВГраницах() {
        var sample = MonitorService.Sample()
        #expect(sample.memoryShare == 0, "деления на ноль быть не должно")
        #expect(sample.diskShare == 0)
        sample.memoryTotal = 100
        sample.memoryUsed = 25
        #expect(sample.memoryShare == 0.25)
    }

    @Test("Запись величин")
    func записьВеличин() {
        #expect(MonitorService.percent(0) == "0%")
        #expect(MonitorService.percent(0.755) == "76%")
        #expect(MonitorService.percent(1) == "100%")
        // Разделитель зависит от системы, поэтому задаём его явно —
        // иначе тест падал бы на машине с русской локалью.
        #expect(MonitorService.gigabytes(25_770_000_000, locale: Locale(identifier: "en_US")) == "25.8")
        #expect(MonitorService.gigabytes(25_770_000_000, locale: Locale(identifier: "ru_RU")) == "25,8")
    }
}
