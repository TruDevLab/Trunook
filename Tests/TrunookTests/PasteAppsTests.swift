import Foundation
import Testing
@testable import Trunook

/// Выбор приложения для вставки.
@Suite("Куда вставлять: приложение")
struct PasteAppsTests {
    @Test("Перебор идёт по кругу")
    func переборПоКругу() {
        // По кругу, а не до упора: список чужой и длинный, и упереться
        // в его конец значило бы заставить человека считать нажатия.
        let list: [pid_t] = [10, 20, 30]
        #expect(PasteApps.next(after: pid_t(10), in: list) == 20)
        #expect(PasteApps.next(after: pid_t(30), in: list) == 10)
    }

    @Test("Неизвестная цель ставит перебор на начало")
    func неизвестнаяЦель() {
        // Приложение, откуда пришли, могли закрыть, пока панель была
        // открыта: перебор тогда начинается сначала, а не проваливается.
        #expect(PasteApps.next(after: pid_t(99), in: [10, 20]) == 10)
        #expect(PasteApps.next(after: pid_t?.none, in: [10, 20]) == 10)
    }

    @Test("Пустой список не даёт цели")
    func пустойСписок() {
        #expect(PasteApps.next(after: pid_t(10), in: [pid_t]()) == nil)
        #expect(PasteApps.next(after: pid_t?.none, in: [pid_t]()) == nil)
    }

    @Test("Одно приложение остаётся на месте")
    func одноПриложение() {
        #expect(PasteApps.next(after: pid_t(10), in: [10]) == 10)
    }

    @Test("Подпись кнопки называет приложение")
    func подписьКнопки() {
        #expect(AssistantSession.AnswerAction.paste.title(pasteTo: "Заметки") == "Вставить в Заметки")
        // Без имени — прежняя подпись: приложения может и не быть.
        #expect(AssistantSession.AnswerAction.paste.title(pasteTo: nil)
                    == AssistantSession.AnswerAction.paste.title)
        #expect(AssistantSession.AnswerAction.paste.title(pasteTo: "") 
                    == AssistantSession.AnswerAction.paste.title)
        // Остальные действия имени не берут: вставляет только вставка.
        #expect(AssistantSession.AnswerAction.copy.title(pasteTo: "Заметки")
                    == AssistantSession.AnswerAction.copy.title)
    }
}
