import Foundation
import Testing
@testable import Trunook

@Suite("Вызовы инструментов в потоке")
struct ToolCallStreamTests {
    /// Главная беда разметки OpenAI: вызов приходит не целиком.
    /// Имя — в первой посылке, аргументы — по нескольку символов
    /// в следующих. Склеить их надо в одну строку JSON.
    @Test("OpenAI склеивает вызов из обрывков")
    func обрывкиСкладываютсяВЦелое() throws {
        var stream = ToolCallStream()
        for line in [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"timer_start","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"minu"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tes\": 10}"}}]}}]}"#,
        ] {
            stream.eat(line, dialect: .openAI)
        }

        let calls = stream.calls()
        #expect(calls.count == 1)
        let call = try #require(calls.first)
        #expect(call.id == "call_a")
        #expect(call.name == "timer_start")
        #expect(call.integer("minutes") == 10)
    }

    /// Склейка по порядку прихода выглядит работающей ровно до второго
    /// инструмента в одном ответе: куски двух вызовов идут вперемешку,
    /// и аргументы одного дописались бы другому. Собирать надо по `index`.
    @Test("Два вызова разом не смешиваются")
    func дваВызоваРазбираютсяПоНомеру() throws {
        var stream = ToolCallStream()
        for line in [
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"timer_start","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"weather_now","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"minutes\":5}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{}"}}]}}]}"#,
        ] {
            stream.eat(line, dialect: .openAI)
        }

        let calls = stream.calls()
        #expect(calls.count == 2)
        #expect(calls.first?.name == "timer_start")
        #expect(calls.first?.integer("minutes") == 5)
        #expect(calls.last?.name == "weather_now")
        #expect(calls.last?.values.isEmpty == true)
    }

    /// Ollama отдаёт вызов целиком и аргументы объектом, а не строкой.
    /// Приводим к строке, чтобы дальше обе разметки разбирались одинаково.
    @Test("Ollama отдаёт вызов целиком")
    func ollamaЦеликом() throws {
        var stream = ToolCallStream()
        stream.eat(
            #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"calendar_day_agenda","arguments":{"date":"2026-09-12"}}}]},"done":false}"#,
            dialect: .ollama
        )

        let call = try #require(stream.calls().first)
        #expect(call.name == "calendar_day_agenda")
        #expect(call.string("date") == "2026-09-12")
        // Своего номера у Ollama нет — назначаем свой, иначе на результат
        // нечем сослаться.
        #expect(call.id == "call_1")
    }

    /// Строка с одним лишь куском ответа не должна заводить пустой вызов:
    /// пустой вызов без имени уехал бы в переписку и сервер отверг бы её.
    @Test("Обычный ответ вызовов не заводит")
    func текстБезВызововНичегоНеДобавляет() {
        var stream = ToolCallStream()
        stream.eat(#"data: {"choices":[{"delta":{"content":"Привет"}}]}"#, dialect: .openAI)
        stream.eat(#"{"message":{"role":"assistant","content":"Привет"},"done":false}"#, dialect: .ollama)
        stream.eat("data: [DONE]", dialect: .openAI)
        stream.eat("", dialect: .openAI)
        #expect(stream.isEmpty)
        #expect(stream.calls().isEmpty)
    }

    /// Модель шлёт `10` и `"10"` вперемешку, и разбирать это в каждом
    /// инструменте по-своему значило бы разойтись на первом же.
    @Test("Число и строка читаются одинаково")
    func числоИСтрокаОдноИТоЖе() {
        let asNumber = ToolCall(id: "1", name: "timer_start", arguments: #"{"minutes": 10}"#)
        let asText = ToolCall(id: "2", name: "timer_start", arguments: #"{"minutes": "10"}"#)
        #expect(asNumber.integer("minutes") == 10)
        #expect(asText.integer("minutes") == 10)
        #expect(asNumber.string("minutes") == "10")
    }

    /// Мусор вместо аргументов не должен валить разбор: инструмент ответит,
    /// что не понял, и у модели будет заход поправиться.
    @Test("Мусор в аргументах даёт пустой словарь")
    func мусорНеВалитРазбор() {
        let call = ToolCall(id: "1", name: "timer_start", arguments: "не JSON вовсе")
        #expect(call.values.isEmpty)
        #expect(call.integer("minutes") == nil)
    }
}

@Suite("Реплика на проводе: два диалекта расходятся")
struct ChatMessageWireTests {
    /// Обычная реплика обязана собираться ровно так же, как собиралась
    /// до всякого агента: лишний ключ в запросе строгий сервер отвергает.
    @Test("Обычная реплика — два ключа и ничего лишнего")
    func обычнаяРепликаНеИзменилась() {
        for dialect in [AIProvider.Dialect.openAI, .ollama] {
            let wire = ModelClient.wire(.user("Привет"), dialect: dialect)
            #expect(wire.count == 2, "лишний ключ у \(dialect)")
            #expect(wire["role"] as? String == "user")
            #expect(wire["content"] as? String == "Привет")
        }
    }

    /// Аргументы у OpenAI строка, у Ollama объект. Строка, попавшая Ollama
    /// на место объекта, её разборщиком не принимается — и выглядит это
    /// как «модель перестала звать инструменты».
    @Test("Аргументы: строка у одного, объект у другого")
    func аргументыРазнойФормы() throws {
        let call = ToolCall(id: "call_a", name: "timer_start", arguments: #"{"minutes":10}"#)
        let message = ModelClient.ChatMessage.calls([call])

        let openAI = ModelClient.wire(message, dialect: .openAI)
        let openAICall = try #require((openAI["tool_calls"] as? [[String: Any]])?.first)
        let openAIFunction = try #require(openAICall["function"] as? [String: Any])
        #expect(openAIFunction["arguments"] is String)
        #expect(openAICall["id"] as? String == "call_a")
        #expect(openAICall["type"] as? String == "function")

        let ollama = ModelClient.wire(message, dialect: .ollama)
        let ollamaCall = try #require((ollama["tool_calls"] as? [[String: Any]])?.first)
        let ollamaFunction = try #require(ollamaCall["function"] as? [String: Any])
        let arguments = try #require(ollamaFunction["arguments"] as? [String: Any])
        #expect(arguments["minutes"] as? Int == 10)
        // Своего номера у Ollama нет — и слать его ей незачем.
        #expect(ollamaCall["id"] == nil)
    }

    /// На результат OpenAI ссылается номером вызова, Ollama — именем
    /// инструмента. Перепутать значит остаться без ответа на вызов.
    @Test("Ответ инструмента ссылается по-разному")
    func ответИнструментаСсылаетсяПоРазному() {
        let message = ModelClient.ChatMessage.tool("Таймер пошёл", id: "call_a", name: "timer_start")

        let openAI = ModelClient.wire(message, dialect: .openAI)
        #expect(openAI["tool_call_id"] as? String == "call_a")
        #expect(openAI["tool_name"] == nil)

        let ollama = ModelClient.wire(message, dialect: .ollama)
        #expect(ollama["tool_name"] as? String == "timer_start")
        #expect(ollama["tool_call_id"] == nil)

        for wire in [openAI, ollama] {
            #expect(wire["role"] as? String == "tool")
            #expect(wire["content"] as? String == "Таймер пошёл")
        }
    }
}

@Suite("Описание инструмента на проводе")
struct ToolSchemaTests {
    /// Точку принимает Ollama и отвергает OpenAI: имя вида `calendar.create`
    /// жило бы на местной модели и молча падало у облачного провайдера.
    @Test("Имя годится для обоих провайдеров")
    func имяПоОбразцу() {
        #expect(ToolSchema.isValidName("calendar_create_event"))
        #expect(ToolSchema.isValidName("timer-stop"))
        #expect(!ToolSchema.isValidName("calendar.create"))
        #expect(!ToolSchema.isValidName("создать_встречу"))
        #expect(!ToolSchema.isValidName(""))
        #expect(!ToolSchema.isValidName(String(repeating: "a", count: 65)))
    }

    /// Голое `{"type":"object"}` без `properties` строгие серверы отвергают,
    /// а `required: []` понимают не все. Обе мелочи стоят отказа на запросе.
    @Test("Инструмент без параметров всё равно описан целиком")
    func безПараметровТожеОписан() throws {
        let schema = ToolSchema(name: "weather_now", description: "Погода", parameters: [])
        let function = try #require(schema.wire["function"] as? [String: Any])
        let shape = try #require(function["parameters"] as? [String: Any])
        #expect(shape["type"] as? String == "object")
        #expect((shape["properties"] as? [String: Any])?.isEmpty == true)
        #expect(shape["required"] == nil, "пустой required пишется как отсутствующий")
        #expect(schema.wire["type"] as? String == "function")
    }

    @Test("Обязательные параметры перечислены, необязательные — нет")
    func обязательныеПеречислены() throws {
        let schema = ToolSchema(
            name: "timer_start",
            description: "Поставить таймер",
            parameters: [
                .init(name: "minutes", kind: .integer, description: "Минут", isRequired: true),
                .init(name: "quiet", kind: .boolean, description: "Тихо", isRequired: false),
            ]
        )
        let function = try #require(schema.wire["function"] as? [String: Any])
        let shape = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(shape["properties"] as? [String: Any])
        #expect(properties.count == 2)
        #expect((shape["required"] as? [String]) == ["minutes"])
        let minutes = try #require(properties["minutes"] as? [String: Any])
        #expect(minutes["type"] as? String == "integer")
    }
}
