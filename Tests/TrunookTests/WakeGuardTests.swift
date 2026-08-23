import Foundation
import Testing
@testable import Trunook

@Suite("Удержание экрана")
struct WakeGuardTests {
    /// Ассерция настоящая: тест создаёт и тут же отпускает её. Подделывать
    /// здесь нечего — вся суть службы в том, дошла ли просьба до системы.
    @Test("Включение и выключение меняют состояние")
    func включениеВыключение() {
        let guardian = WakeGuard()
        #expect(!guardian.isOn)
        guardian.enable()
        #expect(guardian.isOn, "система не приняла просьбу удержать экран")
        guardian.disable()
        #expect(!guardian.isOn)
    }

    /// Срок теперь выбирают прямо в вырезе, и выбор обязан включить чашку,
    /// если она погашена: отдельного «включить» в панели нет — есть сроки.
    @Test("Выбор срока включает погашенную чашку")
    func выборВключает() {
        let guardian = WakeGuard()
        #expect(!guardian.isOn)
        guardian.setLimit(minutes: 30)
        #expect(guardian.isOn)
        #expect(guardian.activeLimitMinutes == 30)
        #expect(guardian.endsAt != nil, "со сроком должен быть виден и его конец")
        guardian.disable()
        #expect(!guardian.isOn)
        #expect(guardian.endsAt == nil)
    }

    /// Панель выбора открывают и при горящей чашке — чтобы продлить или
    /// укоротить. Перестановка срока не должна отпускать экран посередине.
    @Test("Перестановка срока не выключает удержание")
    func перестановкаНеВыключает() {
        let guardian = WakeGuard()
        guardian.setLimit(minutes: 30)
        let first = guardian.endsAt
        guardian.setLimit(minutes: 120)
        #expect(guardian.isOn, "перестановка срока отпустила экран")
        #expect(guardian.activeLimitMinutes == 120)
        #expect(guardian.endsAt != first, "конец срока не сдвинулся")
        guardian.disable()
    }

    /// Ноль — «без срока»: удержание есть, а конца у него нет.
    @Test("Без срока конца не назначается")
    func безСрокаНетКонца() {
        let guardian = WakeGuard()
        guardian.setLimit(minutes: 0)
        #expect(guardian.isOn)
        #expect(guardian.activeLimitMinutes == 0)
        #expect(guardian.endsAt == nil)
        guardian.disable()
    }

    /// Подписи кнопок в панели: круглые часы подписаны часами, остальное —
    /// минутами, ноль — словами. Повторов быть не должно, иначе две кнопки
    /// в ряду выглядят одинаково.
    @Test("У каждого срока своя подпись")
    func подписиСроков() {
        let titles = Settings.caffeineLimits.map(CaffeinePanel.title(minutes:))
        #expect(Set(titles).count == titles.count, "подписи повторяются: \(titles)")
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(CaffeinePanel.title(minutes: 120) == CaffeinePanel.title(minutes: 120))
    }

    /// Повторное включение не должно заводить вторую ассерцию: первая тогда
    /// осталась бы висеть навсегда, и экран не гас бы после выключения.
    @Test("Повторное включение не плодит ассерций")
    func повторноеВключение() {
        let guardian = WakeGuard()
        guardian.enable()
        guardian.enable()
        guardian.disable()
        #expect(!guardian.isOn)
    }

    @Test("Выключение выключенного ничего не ломает")
    func выключениеВыключенного() {
        let guardian = WakeGuard()
        guardian.disable()
        #expect(!guardian.isOn)
    }

    /// Срок читается из настроек в момент включения: поменянный при горящей
    /// чашке он не должен обрывать нынешнее удержание на полпути.
    @Test("Срок берётся из настроек")
    func срокИзНастроек() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        let guardian = WakeGuard(settings: settings)
        #expect(guardian.limitMinutes == 0, "по умолчанию ограничения быть не должно")
        settings.caffeineLimitMinutes = 90
        #expect(guardian.limitMinutes == 90)
    }

    /// Срок со сроком не отменяет самого удержания: будильник только заводится.
    @Test("Со сроком экран всё равно удерживается")
    func соСрокомУдерживается() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.caffeineLimitMinutes = 30
        let guardian = WakeGuard(settings: settings)
        guardian.enable()
        #expect(guardian.isOn)
        guardian.disable()
        #expect(!guardian.isOn)
    }

    /// Истёкший срок снимает удержание и сообщает об этом. Молчание здесь
    /// оставило бы человека гадать, почему экран вдруг снова гаснет.
    @Test("Истёкший срок отпускает экран и сообщает")
    func срокОтпускает() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.caffeineLimitMinutes = 30
        let guardian = WakeGuard(settings: settings)
        var told = false
        guardian.onExpired = { told = true }
        guardian.enable()
        guardian.debugExpireNow()
        #expect(!guardian.isOn)
        #expect(told, "об истёкшем сроке не сообщили")
    }

    @Test("Среди сроков есть и «без ограничения», и все названные")
    func срокиНаВыбор() {
        #expect(Settings.caffeineLimits.contains(0), "нет варианта «без ограничения»")
        for minutes in [30, 90, 120] {
            #expect(Settings.caffeineLimits.contains(minutes), "нет срока \(minutes) мин")
        }
    }

    /// Три случая — три разных текста. Истёкший срок нельзя показывать так же,
    /// как выключение рукой: человек его не нажимал.
    @Test("У всех трёх случаев свой текст")
    func триТекста() {
        let texts = [
            CaffeineChange.on(minutes: 0),
            .on(minutes: 90),
            .off,
            .expired,
        ].map { ActivityView.text(for: .caffeine(change: $0), track: nil) }
        #expect(Set(texts).count == texts.count, "тексты повторяются: \(texts)")
        #expect(texts.allSatisfy { !$0.isEmpty })
    }

    /// Плашка должна уйти сама: она сообщает о свершившемся, а не висит
    /// признаком состояния — признак живёт подложкой под чашкой.
    @Test("Плашка о переключении не вечная и с текстом")
    func плашкаСрочная() {
        for change in [CaffeineChange.on(minutes: 0), .off, .expired] {
            let activity = Activity(kind: .caffeine(change: change))
            #expect(activity.duration.isFinite)
            #expect(!ActivityView.text(for: activity.kind, track: nil).isEmpty)
        }
    }
}
