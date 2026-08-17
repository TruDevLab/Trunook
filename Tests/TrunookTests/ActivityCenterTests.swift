import Testing
@testable import Trunook

@Suite("Плашки событий")
struct ActivityCenterTests {
    @Test("Менее важное событие не вытесняет более важное")
    func приоритетВытеснения() {
        let center = ActivityCenter()
        center.present(.command(text: "идёт", state: .running))
        center.present(.trackChanged)
        // Смена трека — приоритет 1, отклик на команду — 5.
        if case .command = center.current?.kind {} else {
            Issue.record("плашку команды вытеснила смена трека")
        }
    }

    @Test("Равное по важности заменяет показанное")
    func равноеЗаменяет() {
        let center = ActivityCenter()
        center.present(.lowBattery(percentage: 20))
        center.present(.clipboard(text: "текст", kind: .text))
        if case .clipboard = center.current?.kind {} else {
            Issue.record("плашка буфера не заменила равную по важности")
        }
    }

    @Test("Плашка полки висит без срока, остальные — со сроком")
    func срокПлашки() {
        #expect(Activity(kind: .shelf(count: 2)).duration.isInfinite)
        #expect(Activity(kind: .trackChanged).duration.isFinite)
    }

    @Test("По плашкам буфера и полки можно нажать, по прочим нельзя")
    func интерактивность() {
        #expect(Activity(kind: .shelf(count: 1)).isInteractive)
        #expect(Activity(kind: .clipboard(text: "т", kind: .text)).isInteractive)
        #expect(!Activity(kind: .trackChanged).isInteractive)
    }

    @Test("Досрочное снятие очищает плашку")
    func снятие() {
        let center = ActivityCenter()
        center.present(.trackChanged)
        center.dismiss()
        #expect(center.current == nil)
    }
}
