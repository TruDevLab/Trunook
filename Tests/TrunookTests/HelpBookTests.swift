import Foundation
import Testing
@testable import Trunook

@Suite("Справка о приложении")
struct HelpBookTests {
    private func find(_ query: String) -> [String] {
        HelpSearch.find(query, in: HelpBook.topics).map(\.id)
    }

    // MARK: - Поиск

    /// Оба вопроса из задачи: сперва «что вообще умеет», потом «как настроить».
    @Test("«Какие функции есть в приложении» ведёт к обзору")
    func обзор() {
        #expect(find("какие функции есть в приложении").first == "overview")
        #expect(find("что умеет приложение").first == "overview")
    }

    @Test("«Как настроить новостную сводку» ведёт к сводкам")
    func сводка() {
        #expect(find("а как настроить новостную сводку?").first == "digest")
        #expect(find("новости").first == "digest")
    }

    /// Склонения: справочник знает «сводка», спрашивают «сводку».
    @Test("Слово в другом падеже находит ту же тему")
    func падежи() {
        #expect(find("настрой сводку новостей").first == "digest")
        #expect(find("хочу заметки в обсидиане").contains("obsidian"))
        #expect(find("как работает полка").first == "shelf")
    }

    /// Поймано живой проверкой: вопрос уходил в тему сводок — там нашлось
    /// слово «включите», а «воде» и «вода» расходились на четвёртой букве.
    @Test("«Как включить уведомления о воде» ведёт к перерывам, а не к сводкам")
    func вода() {
        #expect(find("как включить уведомления о воде?").first == "breaks")
        #expect(find("сколько воды я выпил").first == "breaks")
    }

    @Test("Склонение слова не меняет темы")
    func корниСлов() {
        #expect(HelpSearch.stem("воде") == HelpSearch.stem("вода"))
        #expect(HelpSearch.stem("сводку") == HelpSearch.stem("сводка"))
        #expect(HelpSearch.stem("уведомления") == HelpSearch.stem("уведомление"))
        // Корень короче трёх букв не остаётся: «дела» — это «дел», а не «де».
        #expect(HelpSearch.stem("дела") == "дел")
        // Разные слова не сходятся.
        #expect(HelpSearch.stem("код") != HelpSearch.stem("команда"))
    }

    @Test("Вопрос про частое слово не сбивает выбор темы")
    func частыеСлова() {
        // «Настройках» и «приложения» стоят чуть ли не в каждой теме —
        // и не должны перевешивать одно точное слово.
        #expect(find("в каких настройках приложения включается телесуфлер").first == "teleprompter")
    }

    @Test("Вопрос не о приложении не находит ничего")
    func мимо() {
        #expect(find("сколько лететь до Марса").isEmpty)
        #expect(find("").isEmpty)
    }

    @Test("Ответ называет раздел настроек, а без раздела — не выдумывает его")
    func разделВОтвете() {
        let digest = HelpBook.topic(id: "digest")
        #expect(digest?.answer.contains(SettingsSelection.Tab.feeds.title) == true)

        // У блокировки клавиатуры настройки нет вовсе — и в ответе её быть
        // не должно: человек пошёл бы искать несуществующий переключатель.
        let lock = HelpBook.topic(id: "keyboardLock")
        #expect(lock?.tab == nil)
        #expect(lock?.answer.contains("Раздел настроек") == false)
    }

    // MARK: - Сам справочник

    @Test("Темы не повторяются и заполнены целиком")
    func целостность() {
        let topics = HelpBook.topics
        #expect(topics.count >= 25)
        #expect(Set(topics.map(\.id)).count == topics.count)
        for topic in topics {
            #expect(!topic.title.isEmpty)
            #expect(topic.text.count > 40)
            #expect(!topic.keywords.isEmpty)
        }
    }

    @Test("Оглавление перечисляет темы и начинается с обзора")
    func оглавление() {
        let contents = HelpBook.contents()
        #expect(contents.contains(HelpBook.topic(id: "digest")?.title ?? "—"))
        #expect(contents.contains(HelpBook.topic(id: "shelf")?.title ?? "—"))
        #expect(contents.hasPrefix(HelpBook.topic(id: "overview")?.text ?? "—"))
    }

    // MARK: - Инструмент помощника

    @Test("Инструмент справки только смотрит и не требует подтверждения")
    func инструмент() {
        #expect(AgentTool.appHelp.kind == .read)
        #expect(!AgentTool.appHelp.needsConfirmation)
        #expect(AgentTool.named("app_help") == .appHelp)
    }

    /// Справка не зависит ни от одной функции приложения: про выключенную
    /// спрашивают как раз тогда, когда не могут её найти.
    @Test("Справка доступна при включённом помощнике и любых выключенных функциях")
    func доступность() {
        let settings = Trunook.Settings(
            defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        )
        settings.agentEnabled = true
        settings.calendarEnabled = false
        settings.notesEnabled = false
        settings.weatherEnabled = false
        #expect(AgentTool.appHelp.isEnabled(settings))
        #expect(AgentTool.appHelp.blockedReason(settings) == nil)

        settings.agentEnabled = false
        #expect(!AgentTool.appHelp.isEnabled(settings))
        #expect(AgentTool.appHelp.blockedReason(settings) != nil)
    }

    @Test("Описание инструмента просит один параметр — сам вопрос")
    func параметры() {
        let parameters = AgentTool.appHelp.parameters
        #expect(parameters.map(\.name) == ["query"])
        #expect(parameters.first?.isRequired == true)
    }
}
