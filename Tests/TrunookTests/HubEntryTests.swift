import Testing
@testable import Trunook

@Suite("Меню всех функций")
struct HubEntryTests {
    @Test("Длина списка не расходится с самим списком")
    func длинаСписка() {
        // Раньше число плиток было записано отдельной константой
        // в контроллере — и разошлось бы при первой правке состава.
        #expect(HubEntry.count == HubEntry.panelCases.count)
        #expect(HubEntry.count > 0)
        // Списков стало два: меню держится в два ряда, а кольцо ничем
        // не ограничено и показывает всё. Расходиться им можно только
        // длиной — состав один, и кольцо обязано вмещать меню целиком.
        #expect(HubEntry.ringCases.count == HubEntry.allCases.count)
        #expect(HubEntry.panelCases.allSatisfy(HubEntry.ringCases.contains))
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
    ///
    /// Чашка — исключение, и названное: сочетания у неё нет, но есть своя
    /// кнопка в левом крыле раскрытой панели, то есть путь помимо кольца.
    /// Отнимать ради неё ещё одну клавишу у чужих приложений не за что.
    @Test("У каждой плитки есть своё сочетание")
    func подсказкиУВсех() {
        let settings = Settings.shared
        for entry in HubEntry.allCases where entry != .caffeine {
            #expect(entry.hint(settings) != nil, "у \(entry.rawValue) нет подсказки клавиш")
        }
        #expect(HubEntry.caffeine.hint(settings) == nil)
    }

    /// Телесуфлер ничего не делает, пока окно закрыто: ни опросов, ни клавиш
    /// сверх своей, ни полосы под чёлкой. Выключателя у него поэтому нет,
    /// и плитка доступна всегда.
    @Test("Телесуфлер доступен всегда")
    func телесуфлерДоступен() {
        #expect(HubEntry.teleprompter.isEnabled(Settings.shared))
    }

    /// Сетка в четыре колонки и два ряда. Третий ряд панель себе позволить
    /// не может: она вызывается правой кнопкой поверх чужих окон, и лишние
    /// семьдесят четыре точки закрывают то, ради чего её и открыли.
    ///
    /// Ограничение — на **меню**, а не на состав вообще: кольцу третий ряд
    /// ничего не стоит, оно веер. Проверять здесь `allCases` значило бы
    /// запретить кольцу расти вместе с приложением.
    @Test("Меню укладывается в два ряда сетки")
    func дваРяда() {
        #expect(HubEntry.panelCases.count <= HubPanel.columns * 2)
    }

    /// Заметки стоят сразу за командами: спросить и записать — соседние
    /// половины одного дела.
    @Test("Заметки идут следом за командами")
    func заметкиРядомСКомандами() {
        let order = HubEntry.allCases.map(\.rawValue)
        let commands = order.firstIndex(of: "assistant")
        let notes = order.firstIndex(of: "notes")
        #expect(notes == commands.map { $0 + 1 })
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
