import AppKit
import Foundation
import Testing
@testable import Trunook

@Suite("Телесуфлер")
struct TeleprompterTests {
    private func store() -> TeleprompterStore {
        // Свои настройки, а не общие: тест не должен переписывать скорость,
        // выбранную человеком.
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        return TeleprompterStore(settings: Settings(defaults: defaults))
    }

    /// Ползунок отдаёт дробное значение, а слишком медленная прокрутка
    /// неотличима от неподвижности — потолки нужны с обеих сторон.
    @Test("Скорость не выходит за пределы")
    func скоростьВПределах() {
        let store = store()
        store.speed = 10_000
        #expect(store.speed == TeleprompterStore.maxSpeed)
        store.speed = -5
        #expect(store.speed == TeleprompterStore.minSpeed)
    }

    @Test("Скорость переживает запись и чтение")
    func скоростьХранится() {
        let store = store()
        store.speed = 75
        #expect(store.speed == 75)
    }

    /// Пока поле не привязано, прокручивать нечего: таймер, пущенный
    /// в пустоту, крутился бы шестьдесят раз в секунду без всякого толку.
    @Test("Без поля прокрутка не пускается")
    func безПоляНеКрутим() {
        let store = store()
        store.startScrolling()
        #expect(!store.isScrolling)
    }

    /// Телесуфлер — единственная накладка, которую не убирает ни уход
    /// курсора, ни нажатие мимо: пока читают вслух, в чужом окне работают.
    @Test("Телесуфлер не закрывается сам")
    func неЗакрываетсяСам() {
        #expect(!NotchState.Overlay.teleprompter.closesOnCursorExit)
        #expect(!NotchState.Overlay.teleprompter.closesOnClickOutside)
    }

    @Test("Остальные накладки закрываются нажатием мимо")
    func остальныеЗакрываются() {
        for overlay in NotchState.Overlay.allCases where overlay != .teleprompter {
            #expect(overlay.closesOnClickOutside, "\(overlay) перестала закрываться мимо")
        }
    }

    /// Зона нажатий обязана совпадать с нарисованным — иначе панель видно,
    /// а нажать по ней нельзя.
    @Test("Панель телесуфлера имеет свой размер")
    func размерПанели() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let size = NotchInputs(overlay: .teleprompter).resolve().size(metrics: metrics)
        #expect(size.width == TeleprompterPanel.width)
        #expect(size.height == TeleprompterPanel.height(notchHeight: metrics.notchHeight))
    }

    /// Панель выше и шире прочих, и окно обязано её вместить: переросшее
    /// окно обрезает содержимое молча.
    @Test("Окно вмещает панель телесуфлера")
    func окноВмещает() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        #expect(metrics.windowSize.width >= TeleprompterPanel.width)
        #expect(metrics.windowSize.height >= TeleprompterPanel.height(notchHeight: 32))
    }
}
