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

    @Test("Переключатель отвечает новым состоянием")
    func переключатель() {
        let guardian = WakeGuard()
        #expect(guardian.toggle())
        #expect(guardian.isOn)
        #expect(!guardian.toggle())
        #expect(!guardian.isOn)
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
