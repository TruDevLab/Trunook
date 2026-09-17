import Foundation
import Testing
@testable import Trunook

/// Номера реплик при вставке в середину переписки.
///
/// Проверка нужна потому, что беда была молчаливая и видел её только человек:
/// команда прячет свой промт нулевой репликой, а перед ним вставляется
/// указание помощнику — промт уезжает на первую, спрятанной остаётся пустота,
/// и захваченный абзац появляется в ленте вторым экземпляром. Он уже стоит
/// плашкой сверху.
@Suite("Номера реплик в переписке")
struct AssistantMarksTests {
    @Test("Вставка в начало сдвигает скрытую реплику")
    func скрытаяРепликаПереезжает() {
        #expect(AssistantSession.shifted([0], insertedAt: 0) == [1])
        #expect(AssistantSession.shifted([0, 3], insertedAt: 0) == [1, 4])
    }

    @Test("Вставка после отметки её не трогает")
    func вставкаПосле() {
        #expect(AssistantSession.shifted([0], insertedAt: 1) == [0])
        #expect(AssistantSession.shifted([0, 2], insertedAt: 2) == [0, 3])
    }

    @Test("Пустой набор остаётся пустым")
    func пустойНабор() {
        #expect(AssistantSession.shifted(Set<Int>(), insertedAt: 0).isEmpty)
    }

    @Test("Подписи шагов переезжают вместе со своими репликами")
    func подписиШагов() {
        // Подпись, оставшаяся на прежнем номере, встала бы к чужой реплике:
        // «Посмотрел календарь» у ответа про погоду.
        let labels = [1: "погода", 3: "календарь"]
        #expect(AssistantSession.shifted(labels, insertedAt: 0) == [2: "погода", 4: "календарь"])
        #expect(AssistantSession.shifted(labels, insertedAt: 2) == [1: "погода", 4: "календарь"])
    }

    @Test("Снятая реплика уводит номера обратно")
    func снятиеРеплики() {
        // Указание помощнику снимается, когда сервер отказался брать
        // инструменты: без обратного переноса спрятанный промт уехал бы
        // в ленту тем же способом, что и при вставке.
        #expect(AssistantSession.shifted([1], removedAt: 0) == [0])
        #expect(AssistantSession.shifted([0, 2], removedAt: 1) == [0, 1])
    }

    @Test("Отметка на самой снятой реплике пропадает")
    func отметкаСнятойРеплики() {
        #expect(AssistantSession.shifted([0], removedAt: 0).isEmpty)
        #expect(AssistantSession.shifted([0: "а", 1: "б"], removedAt: 0) == [0: "б"])
    }

    @Test("Вставка и снятие возвращают номера на место")
    func тудаИОбратно() {
        let hidden: Set<Int> = [0, 4]
        #expect(AssistantSession.shifted(AssistantSession.shifted(hidden, insertedAt: 0), removedAt: 0) == hidden)
        let labels = [2: "погода", 5: "календарь"]
        #expect(AssistantSession.shifted(AssistantSession.shifted(labels, insertedAt: 1), removedAt: 1) == labels)
    }

    @Test("Отказ узнаётся по словам сервера, а не по коду ответа")
    func отказПоСловам() {
        // 400 Ollama отвечает и на переросший контекст, и на незнакомую
        // модель: переспрашивать без инструментов стоит ровно в одном
        // из этих случаев.
        struct Failure: LocalizedError {
            let text: String
            var errorDescription: String? { text }
        }
        #expect(AssistantSession.refusesTools(
            Failure(text: #"Сервер модели ответил 400: {"error":"gemma3:4b does not support tools"}"#)
        ))
        #expect(!AssistantSession.refusesTools(Failure(text: "Сервер модели ответил 400: context too long")))
        #expect(!AssistantSession.refusesTools(Failure(text: "Нет связи с сервером модели")))
    }

    @Test("Имя модели отделяется от провайдера")
    func имяМодели() {
        // Список умений знает модель по имени, а в разговоре она лежит
        // вместе с хозяином: `ollama|gemma3:4b`.
        #expect(AssistantSession.modelName(of: "ollama|gemma3:4b") == "gemma3:4b")
        #expect(AssistantSession.modelName(of: "gemma3:4b") == "gemma3:4b")
        #expect(AssistantSession.modelName(of: "openai|gpt-4o") == "gpt-4o")
    }

    @Test("Ни одна подпись не теряется и не сливается с соседней")
    func подписиНеТеряются() {
        let labels = [0: "а", 1: "б", 2: "в"]
        let moved = AssistantSession.shifted(labels, insertedAt: 0)
        #expect(moved.count == labels.count)
        #expect(Set(moved.values) == Set(labels.values))
    }
}
