import Testing
@testable import Trunook

@Suite("Состав кольца быстрого доступа")
struct HubEntryTests {
    /// Кольцо — единственное меню всех функций, и в нём всё, что есть.
    @Test("Кольцо показывает все функции")
    func кольцоПолное() {
        #expect(HubEntry.ringCases == HubEntry.allCases)
        #expect(!HubEntry.ringCases.isEmpty)
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

    /// Заметки стоят сразу за командами: спросить и записать — соседние
    /// половины одного дела.
    @Test("Заметки идут следом за командами")
    func заметкиРядомСКомандами() {
        let order = HubEntry.allCases.map(\.rawValue)
        let commands = order.firstIndex(of: "assistant")
        let notes = order.firstIndex(of: "notes")
        #expect(notes == commands.map { $0 + 1 })
    }

    @Test("Настроек, знакомства и главного экрана среди кружков нет")
    func лишнихПлитокНет() {
        // Настройки открываются значком в правом крыле, знакомство — из меню
        // строки состояния, а главный экран — то место, откуда кольцо и открыли:
        // щелчок мимо кружков к нему возвращает. Дублировать любое из них
        // кружком значило бы дать два пути к одному и тому же.
        let titles = HubEntry.allCases.map(\.rawValue)
        #expect(!titles.contains("settings"))
        #expect(!titles.contains("welcome"))
        #expect(!titles.contains("expanded"))
    }
}
