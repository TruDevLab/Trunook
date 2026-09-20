import Foundation
import Testing
@testable import Trunook

/// Выбор инструмента через «/»: когда список открыт, чем заполнен и что
/// уходит модели.
///
/// Правило разбора здесь одно на троих — вёрстку, контроллер и отправку, —
/// и разойдись оно, список показывался бы на одном, а выбор срабатывал бы
/// на другом.
@Suite("Выбор инструмента через «/»")
struct ToolSlashTests {
    private func settings(agent: Bool = true) -> Trunook.Settings {
        let store = Trunook.Settings(
            defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        )
        store.agentEnabled = agent
        return store
    }

    private func tool(_ title: String, tools: [AgentTool] = [.appHelp]) -> SlashTool {
        SlashTool(
            id: title.lowercased(), title: title, detail: "подпись",
            symbol: "gear", tint: .white, tools: tools
        )
    }

    // MARK: - Когда список открыт

    @Test("«/» в начале открывает список, «/» посреди фразы — нет")
    func когдаОткрыт() {
        #expect(SlashQuery.query(in: "/") == "")
        #expect(SlashQuery.query(in: "/наст") == "наст")
        // Косая черта попадается в датах, путях и адресах — и выбирать
        // инструмент посреди фразы незачем: он относится ко всему вопросу.
        #expect(SlashQuery.query(in: "что было 12/09?") == nil)
        #expect(SlashQuery.query(in: "открой ~/Documents") == nil)
        // Ярлык уже выбран, дальше идёт сам вопрос — список закрыт.
        #expect(SlashQuery.query(in: "/настройки как включить воду?") == nil)
        #expect(SlashQuery.query(in: "") == nil)
    }

    @Test("Длинный хвост запросом не считается")
    func длинныйХвост() {
        let long = "/" + String(repeating: "а", count: SlashQuery.maxLength + 1)
        #expect(SlashQuery.query(in: long) == nil)
    }

    // MARK: - Подстановка

    @Test("Выбор встаёт в начало вопроса словом и с пробелом")
    func подстановка() {
        let chosen = tool("Настройки")
        #expect(SlashQuery.insert(chosen, into: "/наст") == "/настройки ")
        // Пробел обязателен: без него вопрос прилип бы к ярлыку, а сам ярлык
        // остался бы запросом — список висел бы над готовым выбором.
        #expect(SlashQuery.insert(chosen, into: "/") == "/настройки ")
        // Набранный вопрос не теряется: ярлык встаёт перед ним.
        #expect(SlashQuery.insert(chosen, into: "как включить воду?")
            == "/настройки как включить воду?")
    }

    @Test("Ищется по началу названия, потом по середине")
    func поиск() {
        let all = [tool("Настройки"), tool("Календарь"), tool("Заметки")]
        #expect(SlashQuery.matches(all, query: "", limit: 9).count == 3)
        #expect(SlashQuery.matches(all, query: "нас", limit: 9).map(\.title) == ["Настройки"])
        #expect(SlashQuery.matches(all, query: "мет", limit: 9).map(\.title) == ["Заметки"])
        #expect(SlashQuery.matches(all, query: "ЗАМ", limit: 9).map(\.title) == ["Заметки"])
        #expect(SlashQuery.matches(all, query: "щщщ", limit: 9).isEmpty)
    }

    // MARK: - Что уходит модели

    /// Пример из задачи слово в слово.
    @Test("«/настройки как включить уведомления о воде?» — группа и чистый вопрос")
    func разборВопроса() {
        let all = [tool("Настройки"), tool("Календарь", tools: [.upcoming])]
        let chosen = SlashQuery.chosen(in: "/настройки как включить уведомления о воде?", from: all)
        #expect(chosen?.tool.title == "Настройки")
        // Ярлык из вопроса убран: это указание приложению, а не часть
        // вопроса — модели он сказал бы только то, что человек нажал «/».
        #expect(chosen?.question == "как включить уведомления о воде?")
        #expect(chosen?.tool.tools == [.appHelp])
    }

    /// Человек стирает набранное, и уходить модели должно ровно то, что
    /// написано, — то же правило, что у «@».
    @Test("Стёртый ярлык — значит выбора не было")
    func стёртыйЯрлык() {
        let all = [tool("Настройки")]
        #expect(SlashQuery.chosen(in: "как включить воду?", from: all) == nil)
        // Незнакомый ярлык не выбирает ничего: это обычный текст.
        #expect(SlashQuery.chosen(in: "/погода как там?", from: all) == nil)
    }

    @Test("Регистр ярлыка не важен")
    func регистр() {
        let all = [tool("Настройки")]
        #expect(SlashQuery.chosen(in: "/Настройки где вода?", from: all)?.tool.title == "Настройки")
    }

    @Test("Вопрос из одного ярлыка оставляет вопрос пустым")
    func толькоЯрлык() {
        let all = [tool("Настройки")]
        #expect(SlashQuery.chosen(in: "/настройки", from: all)?.question == "")
    }

    // MARK: - Список групп

    @Test("Группы собираются из включённых функций")
    func составСписка() {
        let store = settings()
        store.calendarEnabled = true
        store.notesEnabled = true
        store.weatherEnabled = false
        store.timerEnabled = false
        store.remindersEnabled = false

        let ids = SlashCatalogue.all(for: store).map(\.id)
        // Настройки первыми: до них модель сама доходит хуже всего.
        #expect(ids.first == "settings")
        #expect(ids.contains("calendar"))
        #expect(ids.contains("notes"))
        // Выключенную функцию предлагать нельзя: человек выбрал бы её
        // и получил в ответ отказ вместо ответа.
        #expect(!ids.contains("weather"))
        #expect(!ids.contains("timer"))
        #expect(!ids.contains("reminders"))
    }

    @Test("С выключенным помощником выбирать нечего")
    func безПомощника() {
        let store = settings(agent: false)
        store.calendarEnabled = true
        store.notesEnabled = true
        #expect(SlashCatalogue.all(for: store).isEmpty)
    }

    @Test("Ярлык группы — одно слово со строчной буквы")
    func ярлыки() {
        let store = settings()
        store.calendarEnabled = true
        store.notesEnabled = true
        store.weatherEnabled = true
        store.timerEnabled = true
        store.remindersEnabled = true

        for group in SlashCatalogue.all(for: store) {
            #expect(group.token.hasPrefix("/"))
            // Пробел в ярлыке разорвал бы и разбор, и сам вопрос.
            #expect(!group.token.contains(" "))
            #expect(group.token == group.token.lowercased())
            #expect(!group.tools.isEmpty)
            #expect(!group.detail.isEmpty)
        }
    }

    @Test("Указание модели называет выбранную группу")
    func указание() {
        #expect(SlashQuery.instruction(for: tool("Настройки")).contains("Настройки"))
    }

    // MARK: - Модель разговора

    /// Ловушка, из-за которой список «/» не выходил у пользователя вовсе.
    ///
    /// Модель Ollama жила в ключе `ollamaModel`, пока провайдер был один.
    /// С разъездом провайдеров она переехала в `apiModel.<провайдер>`,
    /// а старый ключ остался лежать со старым значением. Проверка «умеет ли
    /// модель инструменты» читала именно его — и отвечала про модель,
    /// к которой запрос давно не уходит.
    @Test("Модель по умолчанию берётся из ключа провайдера, а не из старого")
    func модельПоУмолчанию() {
        let store = settings()
        store.aiProvider = .ollama
        store.setAPIModel("qwen3:8b", for: .ollama)
        store.ollamaModel = "gemma3:4b"

        #expect(store.defaultModel.name == "qwen3:8b")
        #expect(store.defaultModel.stored == "ollama|qwen3:8b")
    }

    // MARK: - Подсказка в поле

    @Test("Подсказка обещает только то, что сейчас работает")
    func подсказка() {
        let store = settings()
        store.calendarEnabled = true
        store.notesEnabled = true
        let both = NotchView.pickerHint(store)
        #expect(both?.contains("/") == true)
        #expect(both?.contains("@") == true)

        // Без помощника «/» не сделает ничего — и обещать его нельзя.
        store.agentEnabled = false
        #expect(NotchView.pickerHint(store)?.contains("/") == false)
        #expect(NotchView.pickerHint(store)?.contains("@") == true)

        // Без календаря и заметок звать через «@» некого.
        store.calendarEnabled = false
        store.notesEnabled = false
        #expect(NotchView.pickerHint(store) == nil)
    }

    @Test("Подсказка зовёт «@» событием или заметкой, но не записью")
    func подсказкаСобаки() {
        let store = settings()
        store.agentEnabled = false

        // Место в строке одно, и названо одно: пока календарь включён —
        // событие, и заметки остаются списку, который откроет сама «@».
        store.calendarEnabled = true
        store.notesEnabled = true
        #expect(NotchView.pickerHint(store) == "@ — событие")

        store.calendarEnabled = false
        #expect(NotchView.pickerHint(store) == "@ — заметка")

        // Записью в приложении зовётся звук разговора, и «@» достаёт
        // не её: слово читалось бы как обещание звуковых заметок.
        store.calendarEnabled = true
        store.agentEnabled = true
        #expect(NotchView.pickerHint(store)?.contains("запис") == false)
    }

    @Test("Подсказка дописывается к приглашению, а не заменяет его")
    func приглашение() {
        let plain = AssistantPanel.placeholder(asksNotes: false, pickers: nil)
        let hinted = AssistantPanel.placeholder(asksNotes: false, pickers: "/ — инструмент")
        #expect(hinted.hasPrefix(plain))
        #expect(hinted.contains("/"))
        // В режиме поиска по заметкам приглашение своё, а подсказка та же.
        #expect(AssistantPanel.placeholder(asksNotes: true, pickers: nil) != plain)
    }
}
