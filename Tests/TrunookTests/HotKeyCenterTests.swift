import Foundation
import Testing
@testable import Trunook

/// Отпускание своих сочетаний на время записи нового.
///
/// Проверка нужна потому, что беда была молчаливая: поле записи в настройках
/// не получало ⌃⌥1 вовсе — её забирала себе команда, сидящая на этой цифре,
/// — и выглядело это как «цифры не записываются».
@Suite("Горячие клавиши: отпускание на время записи", .serialized)
struct HotKeyCenterTests {
    private var center: HotKeyCenter { .shared }

    /// Общий на приложение объект: каждая проба убирает за собой, иначе
    /// следующая считала бы чужие сочетания.
    private func withCenter(_ body: (HotKeyCenter) -> Void) {
        center.unregisterAll()
        defer { center.unregisterAll() }
        body(center)
    }

    @Test("Отпущенные сочетания не сняты насовсем — список цел")
    func списокЦел() {
        withCenter { center in
            center.register(HotKeySpec.slot(0)!, name: "проба 1") {}
            center.register(HotKeySpec.slot(1)!, name: "проба 2") {}
            #expect(center.count == 2)

            center.suspend()
            // Ни одно не стоит: именно поэтому поле записи их и увидит.
            #expect(center.liveCount == 0)
            #expect(center.count == 2)

            center.resume()
            #expect(center.count == 2)
        }
    }

    @Test("Повторное отпускание и возврат ничего не ломают")
    func повторныеВызовы() {
        withCenter { center in
            center.register(HotKeySpec.assistant, name: "проба") {}
            center.suspend()
            center.suspend()
            #expect(center.liveCount == 0)
            center.resume()
            center.resume()
            #expect(center.count == 1)
        }
    }

    @Test("Возврат без отпускания не трогает ничего")
    func возвратБезОтпускания() {
        withCenter { center in
            center.register(HotKeySpec.assistant, name: "проба") {}
            let before = center.liveCount
            center.resume()
            #expect(center.liveCount == before)
        }
    }

    @Test("Назначенное во время записи не ставится до возврата")
    func назначенноеВоВремяЗаписи() {
        // Запись сочетания перестраивает весь набор: поле записи отдаёт
        // новое сочетание в настройки, а те зовут перерегистрацию. Пока
        // клавиши отпущены, новый набор только запоминается — иначе он
        // тут же снова перехватил бы нажатия у самого поля.
        withCenter { center in
            center.suspend()
            center.unregisterAll()
            center.register(HotKeySpec.slot(2)!, name: "новая") {}
            #expect(center.count == 1)
            #expect(center.liveCount == 0)

            center.resume()
            #expect(center.count == 1)
        }
    }

    @Test("Снятие всех очищает и список, и регистрации")
    func снятиеВсех() {
        withCenter { center in
            center.register(HotKeySpec.assistant, name: "проба") {}
            center.unregisterAll()
            #expect(center.count == 0)
            #expect(center.liveCount == 0)
        }
    }
}
