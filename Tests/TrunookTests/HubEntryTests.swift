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

    /// Меню заодно учит клавишам, и плитка без подсказки — это плитка,
    /// до которой без меню не добраться вовсе.
    @Test("У каждой плитки есть своё сочетание")
    func подсказкиУВсех() {
        let settings = Settings.shared
        for entry in HubEntry.allCases {
            #expect(entry.hint(settings) != nil, "у \(entry.rawValue) нет подсказки клавиш")
        }
    }

    /// Телесуфлер ничего не делает, пока окно закрыто: ни опросов, ни клавиш
    /// сверх своей, ни полосы под чёлкой. Выключателя у него поэтому нет,
    /// и плитка доступна всегда.
    @Test("Телесуфлер доступен всегда")
    func телесуфлерДоступен() {
        #expect(HubEntry.teleprompter.isEnabled(Settings.shared))
    }

    @Test("Настроек, знакомства и главного экрана среди плиток нет")
    func лишнихПлитокНет() {
        // Настройки открываются значком в правом крыле, знакомство — из меню
        // строки состояния, а главный экран лежит **под** самим меню, и возврат
        // к нему — крестик в правом крыле. Дублировать любое из них плиткой
        // значило бы показывать две кнопки одного действия на одном экране.
        let titles = HubEntry.allCases.map(\.rawValue)
        #expect(!titles.contains("settings"))
        #expect(!titles.contains("welcome"))
        #expect(!titles.contains("expanded"))
    }
}
