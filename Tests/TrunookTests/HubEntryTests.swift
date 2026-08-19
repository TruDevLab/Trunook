import Testing
@testable import Trunook

@Suite("Меню всех функций")
struct HubEntryTests {
    @Test("Длина списка не расходится с самим списком")
    func длинаСписка() {
        // Раньше число плиток было записано отдельной константой
        // в контроллере — и разошлось бы при первой правке состава.
        #expect(HubEntry.count == HubEntry.allCases.count)
        #expect(HubEntry.count > 0)
    }

    @Test("У каждой плитки есть название и значок")
    func плиткиЗаполнены() {
        for entry in HubEntry.allCases {
            #expect(!entry.title.isEmpty, "у \(entry.rawValue) нет названия")
            #expect(!entry.symbol.isEmpty, "у \(entry.rawValue) нет значка")
        }
    }

    @Test("Подсказка клавиш есть только там, где сочетание вообще бывает")
    func подсказкиТолькоГдеЕсть() {
        let settings = Settings.shared
        let withHotKey: Set<HubEntry> = [.commands, .clipboard, .shelf, .timer, .monitor]
        for entry in HubEntry.allCases where !withHotKey.contains(entry) {
            #expect(entry.hint(settings) == nil, "у \(entry.rawValue) взялась подсказка")
        }
    }

    @Test("Главный экран доступен всегда")
    func всегдаДоступные() {
        #expect(HubEntry.expanded.isEnabled(Settings.shared))
    }

    @Test("Настроек и знакомства среди плиток нет")
    func лишнихПлитокНет() {
        // Настройки открываются значком в правом крыле, а знакомство —
        // из меню строки состояния. Дублировать их плиткой значило бы
        // показывать две кнопки одного действия на одном экране.
        let titles = HubEntry.allCases.map(\.rawValue)
        #expect(!titles.contains("settings"))
        #expect(!titles.contains("welcome"))
    }
}
