import CoreGraphics
import Foundation
import Testing
@testable import Trunook

/// Поддельный перехватчик: настоящий заглушил бы клавиатуру тестовому
/// процессу, а без Универсального доступа не встал бы вовсе.
private final class FakeTap: KeyboardTap {
    var allowed = true
    var starts = 0
    var stops = 0
    func start() -> Bool {
        guard allowed else { return false }
        starts += 1
        return true
    }
    func stop() { stops += 1 }
}

@Suite("Блокировка клавиатуры")
struct KeyboardLockTests {
    @Test("Сроки — 30, 60 и 90 секунд")
    func сроки() {
        #expect(KeyboardLock.durations == [30, 60, 90])
    }

    @Test("Блокировка ставит перехватчик и срок, снятие убирает")
    func блокировкаИСнятие() {
        let tap = FakeTap()
        let lock = KeyboardLock(tap: tap)
        #expect(!lock.isOn)
        #expect(lock.lock(seconds: 30))
        #expect(lock.isOn)
        #expect(lock.activeSeconds == 30)
        #expect(tap.starts == 1)
        lock.unlock()
        #expect(!lock.isOn)
        #expect(tap.stops >= 1)
    }

    /// Перестановка срока у заглушённой клавиатуры не ставит второй
    /// перехватчик: первый тогда остался бы висеть без хозяина.
    @Test("Смена срока не ставит второй перехватчик")
    func сменаСрока() {
        let tap = FakeTap()
        let lock = KeyboardLock(tap: tap)
        lock.lock(seconds: 30)
        lock.lock(seconds: 90)
        #expect(tap.starts == 1)
        #expect(lock.activeSeconds == 90)
        lock.unlock()
    }

    @Test("Без доступа блокировка не включается и говорит об этом")
    func безДоступа() {
        let tap = FakeTap()
        tap.allowed = false
        let lock = KeyboardLock(tap: tap)
        #expect(!lock.lock(seconds: 60))
        #expect(!lock.isOn)
        #expect(lock.failed)
    }

    @Test("Истечение срока снимает блокировку и сообщает")
    func истечение() {
        let tap = FakeTap()
        let lock = KeyboardLock(tap: tap)
        var expired = false
        lock.onExpired = { expired = true }
        lock.lock(seconds: 60)
        lock.debugExpireNow()
        #expect(!lock.isOn)
        #expect(expired)
    }

    @Test("Остаток показывается минутами и секундами")
    func остаток() {
        let now = Date()
        #expect(KeyboardLock.clock(until: now.addingTimeInterval(90), now: now) == "1:30")
        #expect(KeyboardLock.clock(until: now.addingTimeInterval(41.2), now: now) == "0:42")
        #expect(KeyboardLock.clock(until: now.addingTimeInterval(-5), now: now) == "0:00")
    }

    /// Мышь глушить нельзя: ею блокировку и снимают.
    @Test("Глотаются клавиши, но не мышь")
    func фильтр() {
        #expect(KeyboardLock.swallows(type: CGEventType.keyDown.rawValue, subtype: nil))
        #expect(KeyboardLock.swallows(type: CGEventType.keyUp.rawValue, subtype: nil))
        #expect(KeyboardLock.swallows(type: CGEventType.flagsChanged.rawValue, subtype: nil))
        #expect(KeyboardLock.swallows(type: KeyboardLock.systemDefined, subtype: 8))
        #expect(!KeyboardLock.swallows(type: KeyboardLock.systemDefined, subtype: 7))
        #expect(!KeyboardLock.swallows(type: CGEventType.leftMouseDown.rawValue, subtype: nil))
        #expect(!KeyboardLock.swallows(type: CGEventType.scrollWheel.rawValue, subtype: nil))
    }
}
