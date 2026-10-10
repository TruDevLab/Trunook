import Foundation
import Testing
@testable import Trunook

@Suite("Что помощник умеет")
struct AgentToolTests {
    private func fresh() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "trunook.tests." + UUID().uuidString)!)
    }

    /// Точку принимает Ollama и отвергает OpenAI: имя с точкой жило бы
    /// на местной модели и молча падало у облачного провайдера — то есть
    /// проверить его дома было бы нечем.
    @Test("Имена годятся для обоих провайдеров и не повторяются")
    func именаПоОбразцу() {
        var seen: Set<String> = []
        for tool in AgentTool.allCases {
            #expect(ToolSchema.isValidName(tool.name), "негодное имя: \(tool.name)")
            #expect(seen.insert(tool.name).inserted, "имя повторяется: \(tool.name)")
            #expect(AgentTool.named(tool.name) == tool)
        }
        #expect(AgentTool.named("такого_нет") == nil)
    }

    /// Инструмент без описания модель не выберет никогда, а параметр без
    /// описания заполнит выдумкой. Пустая строка здесь — молчаливая
    /// поломка: ошибки не будет, просто перестанет работать.
    @Test("У всякого инструмента и параметра есть описание")
    func всёОписано() {
        for tool in AgentTool.allCases {
            #expect(!tool.summary.isEmpty, "нет описания: \(tool.name)")
            #expect(!tool.title.isEmpty, "нет подписи: \(tool.name)")
            #expect(!tool.symbol.isEmpty, "нет значка: \(tool.name)")
            for parameter in tool.parameters {
                #expect(!parameter.description.isEmpty, "\(tool.name): параметр \(parameter.name) без описания")
                #expect(ToolSchema.isValidName(parameter.name), "\(tool.name): негодное имя параметра \(parameter.name)")
            }
        }
    }

    /// Подтверждения просит ровно то, что пишет в чужое хранилище. Таймер
    /// в этот список не входит: его видно в чёлке и гасят одним нажатием.
    @Test("Подтверждения просит только пишущее")
    func подтверждаетсяТолькоЗапись() {
        #expect(AgentTool.createEvent.needsConfirmation)
        #expect(AgentTool.createReminder.needsConfirmation)
        #expect(AgentTool.createNote.needsConfirmation)

        #expect(!AgentTool.startTimer.needsConfirmation)
        #expect(!AgentTool.stopTimer.needsConfirmation)
        #expect(!AgentTool.startStopwatch.needsConfirmation)
        #expect(!AgentTool.upcoming.needsConfirmation)
        #expect(!AgentTool.dayAgenda.needsConfirmation)
        #expect(!AgentTool.weatherNow.needsConfirmation)

        for tool in AgentTool.allCases {
            #expect(
                tool.needsConfirmation == (tool.kind == .write),
                "разошлись разряд и подтверждение у \(tool.name)"
            )
        }
    }

    /// Инструмент, ушедший модели при выключенной функции, — это обещание,
    /// которого приложение не сдержит: модель его позовёт и получит отказ.
    @Test("Выключенная функция уносит свой инструмент")
    func инструментИдётЗаСвоейФункцией() {
        let settings = fresh()
        settings.agentEnabled = true
        settings.calendarEnabled = true
        settings.timerEnabled = true
        settings.remindersEnabled = false
        settings.weatherEnabled = false
        settings.notesEnabled = false

        let available = AgentTool.available(for: settings)
        #expect(available.contains(.createEvent))
        #expect(available.contains(.startTimer))
        #expect(!available.contains(.createReminder))
        #expect(!available.contains(.weatherNow))
        #expect(!available.contains(.createNote))
    }

    /// Пустой список означает «агента нет вовсе»: тогда `ModelClient`
    /// не кладёт поле `tools`, и запрос остаётся ровно таким, каким был
    /// до всей этой затеи. Это и есть защита от того, что агент сломает
    /// обычный разговор.
    @Test("С выключенным помощником инструментов нет ни одного")
    func безПомощникаИнструментовНет() {
        let settings = fresh()
        settings.calendarEnabled = true
        settings.timerEnabled = true
        settings.agentEnabled = false

        #expect(AgentTool.available(for: settings).isEmpty)
        #expect(AgentTool.wire(for: settings).isEmpty)
    }

    /// Погасшая строка с причиной учит, а исчезнувшая читается как
    /// «функцию убрали совсем». То же правило, что и у плиток меню.
    @Test("У выключенного инструмента названа причина")
    func причинаНазвана() {
        let settings = fresh()
        settings.agentEnabled = false
        #expect(AgentTool.createEvent.blockedReason(settings) != nil)

        settings.agentEnabled = true
        settings.calendarEnabled = false
        let reason = AgentTool.createEvent.blockedReason(settings)
        #expect(reason != nil)
        #expect(reason != AgentTool.createEvent.blockedReason(Settings(
            defaults: UserDefaults(suiteName: "trunook.tests." + UUID().uuidString)!
        )), "причина «помощник выключен» не должна подменять «календарь выключен»")

        settings.calendarEnabled = true
        #expect(AgentTool.createEvent.blockedReason(settings) == nil)
    }

    /// Модель не знает, какое сегодня число: она считает от даты своего
    /// обучения. Без этого указания встречи уезжают на два года назад.
    @Test("Указание называет сегодняшний день и формат времени")
    func указаниеНесётДатуИФормат() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 7))!

        let text = AgentTool.instruction(now: now, calendar: calendar)
        #expect(text.contains("2026"))
        #expect(text.contains(AgentTime.format))
    }

    @Test("Описание каждого инструмента собирается в годную разметку")
    func разметкаСобирается() throws {
        let settings = fresh()
        settings.agentEnabled = true
        settings.calendarEnabled = true
        settings.remindersEnabled = true
        settings.timerEnabled = true
        settings.weatherEnabled = true
        settings.notesEnabled = true

        let wire = AgentTool.wire(for: settings)
        #expect(wire.count == AgentTool.allCases.count)

        for item in wire {
            #expect(item["type"] as? String == "function")
            let function = try #require(item["function"] as? [String: Any])
            #expect((function["name"] as? String)?.isEmpty == false)
            #expect((function["description"] as? String)?.isEmpty == false)
            let shape = try #require(function["parameters"] as? [String: Any])
            #expect(shape["properties"] != nil, "properties обязан стоять даже пустым")
        }
    }

    /// Кнопка «Найти в заметках» делает то же, чем занят `notes_search`.
    /// Пока инструмент жив, она лишняя, и заметки ушли бы модели дважды:
    /// простынёй в первой реплике и инструментом следом. А там, где
    /// инструмента нет, она остаётся единственным путём к заметкам.
    @Test("Ручной поиск по заметкам стоит там, где нет инструмента")
    func ручнойПоискТолькоБезИнструмента() {
        let settings = fresh()
        settings.notesEnabled = true

        settings.agentEnabled = true
        #expect(AgentTool.searchNotes.isEnabled(settings))
        #expect(!AssistantPanel.showsNotesSearch(
            notesEnabled: true,
            agentSearchesNotes: AgentTool.searchNotes.isEnabled(settings)
        ))

        settings.agentEnabled = false
        #expect(!AgentTool.searchNotes.isEnabled(settings))
        #expect(AssistantPanel.showsNotesSearch(
            notesEnabled: true,
            agentSearchesNotes: AgentTool.searchNotes.isEnabled(settings)
        ))

        // Заметки выключены целиком — искать негде ни тем ни другим.
        #expect(!AssistantPanel.showsNotesSearch(notesEnabled: false, agentSearchesNotes: false))
    }
}

@Suite("Карточка помощника в панели")
struct AgentCardSizingTests {
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    /// Карточка прибавляет ровно себя и один просвет. Разойдись этот расчёт
    /// с вёрсткой — панель либо обрежет карточку, либо оставит под ней
    /// пустую полосу.
    @Test("Карточка прибавляет свою высоту и просвет")
    func карточкаПрибавляетСебя() {
        let without = AssistantPanel.height(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth,
            hasPending: false
        )
        let with = AssistantPanel.height(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth,
            hasPending: true
        )
        #expect(with - without == AgentCard.height + NotchStyle.gridSpacing)
    }

    /// По `tallest` считается потолок окна, а содержимое выше окна
    /// **обрезается** — и видно это только на снимке. Забыть карточку здесь
    /// легче всего: высоту она прибавляет в одном месте, а потолок берётся
    /// в другом.
    @Test("Потолок окна вмещает карточку")
    func потолокВмещаетКарточку() {
        let tallest = AssistantPanel.tallest(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth
        )
        let withCard = AssistantPanel.height(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth,
            question: String(repeating: "\n", count: GrowingTextField.maxLines),
            hasCapture: true,
            captureExpanded: true,
            commandRows: QuickCommands.visibleRows,
            hasPending: true
        )
        #expect(tallest >= withCard)
    }

    /// Пустой список инструментов — это не «помощник молчит», это «запрос
    /// уходит ровно таким, каким уходил всегда». Правило последнего круга
    /// держится на этом.
    @Test("На последнем круге инструментов не дают")
    func последнийКругБезИнструментов() {
        let all: [[String: Any]] = [["type": "function"]]
        for round in 0..<(AgentLoop.maxRounds - 1) {
            #expect(AgentLoop.tools(all, round: round).count == 1, "круг \(round) остался без инструментов")
        }
        #expect(
            AgentLoop.tools(all, round: AgentLoop.maxRounds - 1).isEmpty,
            "на последнем круге модель обязана ответить словами"
        )
    }
}
