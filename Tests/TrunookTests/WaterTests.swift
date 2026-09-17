import Foundation
import Testing
@testable import Trunook

@Suite("Вода")
struct WaterTests {
    private var calendar: Calendar {
        var made = Calendar(identifier: .gregorian)
        made.timeZone = TimeZone(identifier: "UTC") ?? .current
        return made
    }

    private func at(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour)) ?? Date()
    }

    /// Свои настройки на каждую пробу: журнал человека трогать нельзя.
    ///
    /// Замыканием, а не «верни настройки»: `UserDefaults(suiteName:)` кладёт
    /// файл в `~/Library/Preferences`, и проба, не убравшая его за собой,
    /// оставляет мусор на машине человека — по файлу на каждый прогон.
    /// Поймано тем, что после пяти прогонов их накопилось сорок.
    ///
    /// Имя своё у каждой пробы: сьюты идут разом, и общее имя они бы делили.
    private func withProbe(_ body: (Settings) -> Void) {
        let name = "trunook-water-probe-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defer {
            defaults.removePersistentDomain(forName: name)
            UserDefaults.standard.removeSuite(named: name)
            // Снятия домена мало: файл остаётся пустым, на сорок два байта.
            // За сотню прогонов их набирается сотня, и лежат они
            // в `~/Library/Preferences` человека, а не в папке сборки.
            try? FileManager.default.removeItem(
                at: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Preferences/\(name).plist")
            )
        }
        body(Settings(defaults: defaults))
    }

    // MARK: - Шкала

    @Test("Ползунок не выходит за границы и встаёт по делениям")
    func делениеШкалы() {
        #expect(WaterVolume.snap(0) == WaterVolume.minimum)
        #expect(WaterVolume.snap(5000) == WaterVolume.maximum)
        #expect(WaterVolume.snap(274) == 250)
        #expect(WaterVolume.snap(275) == 300)
    }

    @Test("Шаг делит шкалу нацело — максимум достижим")
    func максимумДостижим() {
        // Ползунок, у которого шаг не делит границы нацело, не встаёт
        // на свой максимум вовсе, и узнать об этом можно только тем,
        // что однажды не получилось записать литр.
        #expect((WaterVolume.maximum - WaterVolume.minimum) % WaterVolume.step == 0)
        #expect(WaterVolume.ticks.first == WaterVolume.minimum)
        #expect(WaterVolume.ticks.last == WaterVolume.maximum)
        #expect(WaterVolume.volume(atFraction: 1) == WaterVolume.maximum)
        #expect(WaterVolume.volume(atFraction: 0) == WaterVolume.minimum)
    }

    @Test("Доля и объём — обратные друг другу")
    func доляИОбъём() {
        for volume in WaterVolume.ticks {
            #expect(WaterVolume.volume(atFraction: WaterVolume.fraction(of: volume)) == volume)
        }
        #expect(WaterVolume.fraction(of: WaterVolume.minimum) == 0)
        #expect(WaterVolume.fraction(of: WaterVolume.maximum) == 1)
        // За границами доля не уезжает: ползунок тянут и мимо дорожки.
        #expect(WaterVolume.fraction(of: 5000) == 1)
        #expect(WaterVolume.volume(atFraction: 4) == WaterVolume.maximum)
        #expect(WaterVolume.volume(atFraction: -3) == WaterVolume.minimum)
    }

    @Test("Подписанные деления стоят на настоящих делениях шкалы")
    func подписанныеДеления() {
        // Подпись под риской, которой нет, читается как деление между
        // делениями.
        #expect(WaterVolume.marks.allSatisfy { WaterVolume.ticks.contains($0) })
    }

    @Test("До литра — миллилитры, дальше литры")
    func подписьОбъёма() {
        #expect(WaterVolume.label(350) == "350 мл")
        #expect(WaterVolume.label(950) == "950 мл")
        let litres = WaterVolume.label(1200)
        #expect(litres.hasSuffix(" л"))
        #expect(litres.contains("1"))
        #expect(litres.contains("2"))
    }

    // MARK: - Посуда

    @Test("Границы посуды идут по возрастанию и покрывают шкалу целиком")
    func границыПосуды() {
        // Объём, не попавший никуда, остался бы без значка молча.
        let bounds = WaterVessel.allCases.map(\.upperBound)
        #expect(bounds == bounds.sorted())
        #expect(Set(bounds).count == bounds.count)
        #expect(bounds.last == WaterVolume.maximum)
        #expect(WaterVolume.ticks.allSatisfy { WaterVessel.of($0).upperBound >= $0 })
    }

    @Test("Знакомые объёмы названы привычной посудой")
    func названияПосуды() {
        // Границы привычные, а не ровные доли шкалы: 250 — стакан,
        // 500 — бутылка, и двигать их ради красивой арифметики значило бы
        // врать про обе.
        #expect(WaterVessel.of(50) == .shot)
        #expect(WaterVessel.of(150) == .cup)
        #expect(WaterVessel.of(250) == .glass)
        #expect(WaterVessel.of(300) == .mug)
        #expect(WaterVessel.of(500) == .bottle)
        #expect(WaterVessel.of(1000) == .bigBottle)
    }

    @Test("Посуда не меняется в пределах своей полосы и меняется на границе")
    func полосаПосуды() {
        #expect(WaterVessel.of(200) == WaterVessel.of(250))
        #expect(WaterVessel.of(250) != WaterVessel.of(300))
    }

    @Test("У каждой посуды есть имя и значок")
    func значкиПосуды() {
        #expect(WaterVessel.allCases.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    // MARK: - День

    @Test("Заходы складываются в итог дня")
    func итогДня() {
        var day = WaterDay.empty(on: at(16), calendar: calendar)
        day.portions = [250, 300, 500]
        #expect(day.total == 1050)
        #expect(day.count == 3)
    }

    @Test("Новый день начинает счёт с нуля")
    func сменаДня() {
        // Проверяется при чтении, а не таймером в полночь: машина полночь
        // проспит, и таймер, который должен был сработать во сне,
        // не срабатывает вовсе.
        var day = WaterDay.empty(on: at(16), calendar: calendar)
        day.portions = [250]
        #expect(day.rolled(to: at(16, 23), calendar: calendar) == day)
        let next = day.rolled(to: at(17, 1), calendar: calendar)
        #expect(next.portions.isEmpty)
        #expect(next.total == 0)
    }

    // MARK: - Журнал

    @Test("Записанное переживает перезапуск")
    func записьХранится() {
        withProbe { store in
            let log = WaterLog(settings: store, calendar: calendar, now: at(16))
            log.setDraft(300)
            log.record(now: at(16))
            #expect(log.day.total == 300)

            // Новый объект — то же, что новый запуск приложения.
            let again = WaterLog(settings: store, calendar: calendar, now: at(16))
            #expect(again.day.total == 300)
            // И ползунок открывается на прошлом заходе: пьют из одной кружки.
            #expect(again.draft == 300)
        }
    }

    @Test("Вчерашнее не считается за сегодня")
    func вчерашнееНеСчитается() {
        withProbe { store in
            let yesterday = WaterLog(settings: store, calendar: calendar, now: at(16))
            yesterday.record(now: at(16))

            let today = WaterLog(settings: store, calendar: calendar, now: at(17))
            #expect(today.day.total == 0)
            #expect(today.day.portions.isEmpty)
        }
    }

    @Test("Отмена убирает последний заход, а на пустом ничего не ломает")
    func отменаЗахода() {
        withProbe { store in
            let log = WaterLog(settings: store, calendar: calendar, now: at(16))
            log.setDraft(250)
            log.record(now: at(16))
            log.setDraft(500)
            log.record(now: at(16))
            #expect(log.day.total == 750)

            log.undoLast()
            #expect(log.day.portions == [250])
            log.undoLast()
            log.undoLast()
            #expect(log.day.portions.isEmpty)
            #expect(log.day.total == 0)
        }
    }

    @Test("Ползунок записывает только деления")
    func записьПоДелениям() {
        withProbe { store in
            let log = WaterLog(settings: store, calendar: calendar, now: at(16))
            log.setDraft(273)
            #expect(log.draft == 250)
            log.record(now: at(16))
            #expect(log.day.portions == [250])
        }
    }

    @Test("Полночь между открытием панели и записью не смешивает дни")
    func полночьМеждуЗаходами() {
        withProbe { store in
            let log = WaterLog(settings: store, calendar: calendar, now: at(16, 23))
            log.setDraft(200)
            log.record(now: at(16, 23))
            #expect(log.day.total == 200)

            // Панель осталась открытой до следующего дня.
            log.setDraft(300)
            log.record(now: at(17, 1))
            #expect(log.day.portions == [300])
            #expect(log.day.total == 300)
        }
    }

    // MARK: - Подписи

    @Test("Пустой день говорит об этом словом")
    func подписьПустогоДня() {
        let empty = WaterDay.empty(on: at(16), calendar: calendar)
        #expect(WaterPanel.dayText(empty) == t("Сегодня ещё не пили"))
        #expect(WaterWidget.countText(empty) == t("нажмите, чтобы записать"))

        var full = empty
        full.portions = [250, 250]
        #expect(WaterPanel.dayText(full).contains("500"))
        #expect(WaterWidget.countText(full).contains("2"))
    }

    @Test("У плитки воды есть вёрстка под каждый свой размер")
    func размерыПлитки() {
        let sizes = HomeWidgetKind.water.allowedSizes
        #expect(!sizes.isEmpty)
        #expect(sizes.contains(.small))
        #expect(sizes.allSatisfy { $0.rows == 1 })
        #expect(HomeWidgetKind.water.defaultSize == sizes[0])
    }
}
