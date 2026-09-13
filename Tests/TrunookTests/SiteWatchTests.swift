import Foundation
import Testing
@testable import Trunook

@Suite("Слежка за сайтом")
struct SiteWatchTests {
    @Test("Числа цен: разряды пробелами, запятой и точкой")
    func числа() {
        #expect(WatchNumber.parse("12 990 ₽") == 12_990)
        #expect(WatchNumber.parse("12\u{00A0}990\u{202F}₽") == 12_990)
        #expect(WatchNumber.parse("11 490,50 ₽") == 11_490.5)
        #expect(WatchNumber.parse("$1,299.99") == 1_299.99)
        #expect(WatchNumber.parse("1,299") == 1_299)
        #expect(WatchNumber.parse("12.990,00") == 12_990)
        #expect(WatchNumber.parse("4,5") == 4.5)
        #expect(WatchNumber.parse("от 990 руб.") == 990)
        #expect(WatchNumber.parse("в наличии") == nil)
        #expect(WatchNumber.parse("1.234.567") == 1_234_567)
        #expect(WatchNumber.parse("v0.18.0") == nil)
        #expect(WatchNumber.parse("Trunook 1.2.10") == nil)
    }

    /// Страница «нет соединения» — ровно то, что Озон отдал браузеру через VPN.
    @Test("Отказ сайта узнаётся по началу страницы и по пустоте")
    func отказ() {
        let filler = String(repeating: "Описание товара. ", count: 20)
        #expect(PageBlock.detect(title: "Похоже, нет соединения", text: "Выключите VPN\n" + filler))
        #expect(PageBlock.detect(title: "Just a moment...", text: filler))
        #expect(PageBlock.detect(title: "Товар", text: "Цена 100"))
        #expect(!PageBlock.detect(title: "Наушники", text: filler + "12 990 ₽"))
        let lateMention = filler + String(repeating: "Отзыв. ", count: 400) + "капча"
        #expect(!PageBlock.detect(title: "Наушники", text: lateMention))
    }

    @Test("Ответ модели: значение и число, «НЕТ» и мусор")
    func ответМодели() {
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: 12 990 ₽\nЧИСЛО: 12990")
                == WatchReading(text: "12 990 ₽", number: 12_990))
        #expect(WatchExtract.parse("**Значение:** В наличии\n**Число:** -")
                == WatchReading(text: "В наличии", number: nil))
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: 990 руб.") == WatchReading(text: "990 руб.", number: 990))
        #expect(WatchExtract.parse("НЕТ") == nil)
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: цена не указана\nЧИСЛО: -") == nil)
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: Информация не найдена") == nil)
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: Нет в наличии") == WatchReading(text: "Нет в наличии", number: nil))
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: v0.18.0\nЧИСЛО: 0.18") == WatchReading(text: "v0.18.0", number: nil))
        #expect(WatchExtract.parse("Не могу помочь") == nil)
    }

    @Test("Из нескольких чисел берётся только названное моделью")
    func несколькоЧисел() {
        #expect(WatchNumber.values(in: "12 990 ₽") == [12_990])
        #expect(WatchNumber.values(in: "1,299.99") == [1_299.99])
        #expect(WatchNumber.values(in: "80x28x202 cm") == [80, 28, 202])
        #expect(WatchNumber.values(in: "от 990 до 1 200") == [990, 1_200])
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: 80x28x202 cm\nЧИСЛО: 8028202")
                == WatchReading(text: "80x28x202 cm", number: nil))
        #expect(WatchExtract.parse("ЗНАЧЕНИЕ: 4,5 из 5\nЧИСЛО: 4.5")
                == WatchReading(text: "4,5 из 5", number: 4.5))
    }

    @Test("Выше порога — при пересечении снизу")
    func вышеПорога() {
        #expect(WatchRule.evaluate(previous: reading(90), current: reading(120),
                                   condition: .above, threshold: 100) != nil)
        #expect(WatchRule.evaluate(previous: reading(110), current: reading(120),
                                   condition: .above, threshold: 100) == nil)
        #expect(WatchRule.evaluate(previous: nil, current: reading(120),
                                   condition: .above, threshold: 100) != nil)
    }

    @Test("Цена узнаётся в цели на трёх языках")
    func хочетЦену() {
        #expect(WatchExtract.wantsPrice("Цена"))
        #expect(WatchExtract.wantsPrice("стоимость со скидкой"))
        #expect(WatchExtract.wantsPrice("price"))
        #expect(!WatchExtract.wantsPrice("есть ли в наличии"))
    }

    private func reading(_ number: Double?) -> WatchReading {
        WatchReading(text: number.map { "\(Int($0)) ₽" } ?? "нет", number: number)
    }

    @Test("Первая проверка молчит")
    func перваяМолчит() {
        for condition in WatchCondition.allCases where !condition.usesThreshold {
            #expect(WatchRule.evaluate(previous: nil, current: reading(100),
                                       condition: condition, threshold: nil) == nil)
        }
    }

    @Test("Снизилась и выросла — по числу, а не по тексту")
    func внизВверх() {
        #expect(WatchRule.evaluate(previous: reading(120), current: reading(100),
                                   condition: .decrease, threshold: nil)?.text == "120 ₽ → 100 ₽")
        #expect(WatchRule.evaluate(previous: reading(100), current: reading(120),
                                   condition: .decrease, threshold: nil) == nil)
        #expect(WatchRule.evaluate(previous: reading(100), current: reading(120),
                                   condition: .increase, threshold: nil) != nil)
        let spaced = WatchReading(text: "12 990 ₽", number: 12_990)
        let tight = WatchReading(text: "12990₽", number: 12_990)
        #expect(WatchRule.evaluate(previous: spaced, current: tight, condition: .anyChange, threshold: nil) == nil)
    }

    @Test("Любое изменение без чисел — по тексту")
    func текст() {
        let out = WatchReading(text: "Нет в наличии", number: nil)
        let back = WatchReading(text: "В наличии", number: nil)
        #expect(WatchRule.evaluate(previous: out, current: back, condition: .anyChange, threshold: nil) != nil)
        #expect(WatchRule.evaluate(previous: out, current: out, condition: .anyChange, threshold: nil) == nil)
    }

    @Test("Порог: сообщаем при пересечении, а не на каждой проверке")
    func порог() {
        #expect(WatchRule.evaluate(previous: reading(120), current: reading(90),
                                   condition: .below, threshold: 100) != nil)
        #expect(WatchRule.evaluate(previous: reading(95), current: reading(90),
                                   condition: .below, threshold: 100) == nil)
        #expect(WatchRule.evaluate(previous: nil, current: reading(90),
                                   condition: .below, threshold: 100) != nil)
        #expect(WatchRule.evaluate(previous: reading(120), current: reading(90),
                                   condition: .below, threshold: nil) == nil)
    }

    @Test("Состояние от прежней цели или адреса к слежке не относится")
    func состояниеПоЦели() {
        let watch = SiteWatch(id: 0, url: "https://github.com/a/b/releases", name: "", target: "версия")
        var state = WatchState(reading: WatchReading(text: "цена не указана"))
        state.target = "цена"
        state.url = watch.url
        #expect(!state.matches(watch))
        state.target = "версия"
        #expect(state.matches(watch))
    }

    @Test("Срок проверки с запасом на тик и при дате из будущего")
    func срок() {
        let now = Date()
        #expect(WatchSchedule.isDue(now: now, checkedAt: nil, interval: .hour))
        #expect(WatchSchedule.isDue(now: now, checkedAt: now.addingTimeInterval(-3_590), interval: .hour))
        #expect(!WatchSchedule.isDue(now: now, checkedAt: now.addingTimeInterval(-600), interval: .hour))
        #expect(WatchSchedule.isDue(now: now, checkedAt: now.addingTimeInterval(600), interval: .hour))
    }

    @Test("Адрес без схемы дополняется, мусор отвергается, имя — по хосту")
    func адрес() {
        #expect(SiteWatch(id: 0, url: "shop.ru/item/1", name: "", target: "цена").pageURL?.absoluteString
                == "https://shop.ru/item/1")
        #expect(SiteWatch(id: 0, url: "ftp://shop.ru", name: "", target: "").pageURL == nil)
        #expect(SiteWatch(id: 0, url: "просто текст", name: "", target: "").pageURL == nil)
        #expect(SiteWatch(id: 0, url: "https://www.shop.ru/a", name: "", target: "").displayName == "shop.ru")
        #expect(SiteWatch(id: 0, url: "https://www.shop.ru/a", name: "Наушники", target: "").displayName
                == "Наушники")
    }
}
