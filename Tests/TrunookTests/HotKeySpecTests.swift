import Foundation
import Testing
@testable import Trunook

@Suite("Сочетания клавиш")
struct HotKeySpecTests {
    @Test("Сочетание переживает запись в настройки и чтение обратно")
    func кодированиеТудаИОбратно() throws {
        for spec in [HotKeySpec.menu, .clipboard, .shelf] {
            let data = try JSONEncoder().encode(spec)
            let restored = try JSONDecoder().decode(HotKeySpec.self, from: data)
            #expect(restored == spec)
        }
    }

    @Test("У всех значений по умолчанию есть читаемая подпись")
    func подписьЧитается() {
        for spec in [HotKeySpec.menu, .clipboard, .shelf] {
            #expect(!spec.display.isEmpty)
        }
    }

    @Test("Сочетания по умолчанию не совпадают между собой")
    func безСтолкновений() {
        var seen = Set<String>()
        var specs: [HotKeySpec] = [.menu, .clipboard, .shelf]
        for index in 0..<QuickCommands.slotCount {
            if let slot = HotKeySpec.slot(index) { specs.append(slot) }
        }
        for spec in specs {
            let key = "\(spec.keyCode)-\(spec.modifiers)"
            #expect(seen.insert(key).inserted, "сочетание \(spec.display) назначено дважды")
        }
    }
}
