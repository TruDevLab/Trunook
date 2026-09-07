import CoreGraphics
import Testing
@testable import Trunook

@Suite("Шкала времени")
struct TimerDialTests {
    private let range = 1...180

    @Test("Середина шкалы — выбранное значение")
    func серединаЭтоВыбранное() {
        let width: CGFloat = 400
        let ticks = TimerDialLayout.ticks(centerMinutes: 25, width: width, range: range)
        let middle = ticks.first { $0.minutes == 25 }
        #expect(middle?.x == width / 2)
    }

    @Test("Соседнее деление отстоит ровно на шаг")
    func шагМеждуДелениями() {
        let ticks = TimerDialLayout.ticks(centerMinutes: 25, width: 400, range: range)
        let here = ticks.first { $0.minutes == 25 }
        let next = ticks.first { $0.minutes == 26 }
        #expect(next.map { $0.x - (here?.x ?? 0) } == TimerDialLayout.step)
    }

    /// Пока таймер идёт, остаток убывает непрерывно. Если бы шкала считала
    /// середину целыми минутами, она стояла бы шестьдесят секунд и потом
    /// прыгала на деление.
    @Test("Дробная середина сдвигает всю шкалу")
    func дробнаяСередина() {
        let width: CGFloat = 400
        let ticks = TimerDialLayout.ticks(centerMinutes: 25.5, width: width, range: range)
        let here = ticks.first { $0.minutes == 25 }
        #expect(here?.x == width / 2 - TimerDialLayout.step / 2)
    }

    @Test("Каждое пятое деление — длинное")
    func пятиминуткиДлинные() {
        let ticks = TimerDialLayout.ticks(centerMinutes: 25, width: 400, range: range)
        #expect(ticks.first { $0.minutes == 25 }?.isMajor == true)
        #expect(ticks.first { $0.minutes == 24 }?.isMajor == false)
        #expect(ticks.first { $0.minutes == 30 }?.isMajor == true)
    }

    /// Деления за пределами допустимого не рисуются вовсе: иначе шкала
    /// обещает то, до чего можно дотянуть, но чем нельзя воспользоваться.
    @Test("За границами делений нет")
    func границыПустые() {
        let ticks = TimerDialLayout.ticks(centerMinutes: 2, width: 400, range: range)
        #expect(ticks.allSatisfy { $0.minutes >= 1 })
        #expect(ticks.contains { $0.minutes == 1 })
    }

    /// Знак обратный движению пальца: шкала едет вместе с рукой, как барабан.
    /// Ошибка здесь выглядит как «шкала крутится не в ту сторону», и ловить
    /// её живой рукой дорого — поэтому направление под тестом.
    @Test("Тянут влево — значение растёт")
    func направлениеВращения() {
        let step = TimerDialLayout.step
        #expect(TimerDialLayout.minutes(from: 25, drag: -step, range: range) == 26)
        #expect(TimerDialLayout.minutes(from: 25, drag: step, range: range) == 24)
        #expect(TimerDialLayout.minutes(from: 25, drag: -step * 5, range: range) == 30)
    }

    @Test("Шкала встаёт по делениям, а не между ними")
    func остановПоДелениям() {
        let step = TimerDialLayout.step
        // Меньше половины шага — деление ещё не проехало.
        #expect(TimerDialLayout.minutes(from: 25, drag: -step * 0.4, range: range) == 25)
        // Больше половины — уже проехало.
        #expect(TimerDialLayout.minutes(from: 25, drag: -step * 0.6, range: range) == 26)
    }

    @Test("Дальше границ шкала не уезжает")
    func упорВГраницы() {
        let step = TimerDialLayout.step
        #expect(TimerDialLayout.minutes(from: 25, drag: step * 1000, range: range) == 1)
        #expect(TimerDialLayout.minutes(from: 25, drag: -step * 1000, range: range) == 180)
    }

    /// Секундомер считает, пока его не остановят, и упереться шкале не во что.
    @Test("У секундомера верхней границы нет")
    func секундомерБезПотолка() {
        let ticks = TimerDialLayout.ticks(
            centerMinutes: 240,
            width: 400,
            range: 0...Int.max - 1
        )
        #expect(ticks.contains { $0.minutes == 240 })
        #expect(ticks.contains { $0.minutes == 245 })
    }

    /// Полоса нулевой ширины случается на первом кадре, до раскладки.
    /// Деление, посчитанное в ней, встало бы в ноль и мигнуло бы у левого края.
    @Test("В полосе без ширины делений нет")
    func пустаяПолоса() {
        #expect(TimerDialLayout.ticks(centerMinutes: 25, width: 0, range: range).isEmpty)
    }
}
