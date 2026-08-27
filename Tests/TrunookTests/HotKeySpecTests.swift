import Foundation
import Testing
@testable import Trunook

@Suite("Сочетания клавиш")
struct HotKeySpecTests {
    @Test("Сочетание переживает запись в настройки и чтение обратно")
    func кодированиеТудаИОбратно() throws {
        for spec in [HotKeySpec.assistant, .clipboard, .shelf] {
            let data = try JSONEncoder().encode(spec)
            let restored = try JSONDecoder().decode(HotKeySpec.self, from: data)
            #expect(restored == spec)
        }
    }

    @Test("У всех значений по умолчанию есть читаемая подпись")
    func подписьЧитается() {
        for spec in [HotKeySpec.assistant, .clipboard, .shelf] {
            #expect(!spec.display.isEmpty)
        }
    }

    @Test("Сочетания по умолчанию не совпадают между собой")
    func безСтолкновений() {
        var seen = Set<String>()
        var specs: [HotKeySpec] = [.assistant, .clipboard, .shelf]
        // Столько сочетаний по цифрам приложение вообще умеет раздавать:
        // числа команд больше нет, а проверять надо весь ряд.
        for index in 0..<9 {
            if let slot = HotKeySpec.slot(index) { specs.append(slot) }
        }
        for spec in specs {
            let key = "\(spec.keyCode)-\(spec.modifiers)"
            #expect(seen.insert(key).inserted, "сочетание \(spec.display) назначено дважды")
        }
    }

    /// Номер строки истории достаётся из уже нажатого сочетания: обработчик
    /// слота команды должен уметь узнать, что нажали цифру, и какую.
    @Test("Цифра узнаётся по коду клавиши")
    func цифраУзнаётся() throws {
        for index in 0..<9 {
            let spec = try #require(HotKeySpec.ownDigit(index))
            #expect(HotKeySpec.digitIndex(spec.keyCode) == index)
        }
        #expect(HotKeySpec.ownDigit(9) == nil)
        #expect(HotKeySpec.digitIndex(HotKeySpec.assistant.keyCode) == nil)
    }

    /// Команды сидят на тех же цифрах, что и строки истории: развести
    /// их по регистрации нельзя, разводит только состояние экрана.
    @Test("Команда и строка буфера делят одну клавишу")
    func слотыДелятЦифру() {
        for index in 0..<9 {
            #expect(HotKeySpec.slot(index) == HotKeySpec.ownDigit(index))
        }
    }
}
