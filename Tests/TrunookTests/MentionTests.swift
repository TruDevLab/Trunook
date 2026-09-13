import Foundation
import Testing
@testable import Trunook

/// Указания через «@»: когда список открыт, чем он заполнен и что уходит
/// модели.
///
/// Правило разбора здесь одно на троих — вёрстку, контроллер и отправку, —
/// и разойдись оно, список показывался бы на одном, а подстановка
/// срабатывала бы на другом.
@Suite("Указания через «@»")
struct MentionTests {
    private func event(_ title: String, handle: String = "e1") -> Mention {
        Mention(
            kind: .event,
            handle: handle,
            target: "EV-\(handle)",
            start: Date(timeIntervalSince1970: 1_760_000_000),
            title: title,
            detail: "12 сент, пт, 10:00"
        )
    }

    private func note(_ title: String, handle: String = "n1") -> Mention {
        Mention(kind: .note, handle: handle, target: "7", start: nil, title: title, detail: "12 сент")
    }

    // MARK: - Когда список открыт

    @Test("Свежая собака открывает список целиком")
    func собакаОткрываетСписок() {
        #expect(MentionQuery.query(in: "@") == "")
        #expect(MentionQuery.query(in: "перенеси @") == "")
        #expect(MentionQuery.query(in: "перенеси @пла") == "пла")
    }

    /// Иначе список выскакивал бы на каждом почтовом адресе: там собака
    /// стоит в середине слова, и человек ничего не выбирает.
    @Test("Собака в середине слова запросом не считается")
    func адресНеЗапрос() {
        #expect(MentionQuery.query(in: "напиши на ivan@example.com") == nil)
        #expect(MentionQuery.query(in: "почта@") == nil)
    }

    /// Выбор сделан — список обязан закрыться. Название встречи почти всегда
    /// в два слова, и пробел после подстановки и есть признак готовности.
    @Test("После выбора список закрывается сам")
    func пробелЗакрываетСписок() {
        let text = MentionQuery.insert(event("Планёрка"), into: "перенеси @пла")
        #expect(text == "перенеси @Планёрка ")
        #expect(MentionQuery.query(in: text) == nil)
    }

    /// Длинный хвост — это уже не поиск, а обычный текст, в котором
    /// попалась собака.
    @Test("Слишком длинный запрос списка не держит")
    func длинныйХвостНеЗапрос() {
        let long = String(repeating: "я", count: MentionQuery.maxLength + 1)
        #expect(MentionQuery.query(in: "@" + long) == nil)
    }

    @Test("Без собаки списка нет вовсе")
    func безСобакиНичего() {
        #expect(MentionQuery.query(in: "перенеси планёрку") == nil)
        #expect(MentionQuery.query(in: "") == nil)
    }

    // MARK: - Подстановка

    /// Подставлять надо вместо набранного, а не рядом с ним: иначе в вопросе
    /// оставался бы огрызок «@пла@Планёрка».
    @Test("Подстановка съедает набранный запрос")
    func подстановкаСъедаетЗапрос() {
        #expect(MentionQuery.insert(event("Планёрка"), into: "@") == "@Планёрка ")
        #expect(
            MentionQuery.insert(note("Идеи"), into: "загляни в @ид")
                == "загляни в @Идеи "
        )
    }

    /// Выбрать можно и мышью, когда запроса в тексте уже нет, — тогда
    /// указание дописывается в конец, а не теряется.
    @Test("Без запроса указание дописывается в конец")
    func безЗапросаДописываем() {
        #expect(MentionQuery.insert(event("Планёрка"), into: "перенеси ") == "перенеси @Планёрка ")
    }

    // MARK: - Отбор

    /// Набирая «пла», человек метит в «Планёрку», а не в «Разбор плана».
    @Test("Совпадение с начала названия идёт первым")
    func началоВперёд() {
        let all = [event("Разбор плана", handle: "e1"), event("Планёрка", handle: "e2")]
        let found = MentionQuery.matches(all, query: "пла", limit: 10)
        #expect(found.map(\.handle) == ["e2", "e1"])
    }

    @Test("Регистр и буква ё не мешают найти")
    func регистрНеМешает() {
        let all = [event("Планёрка")]
        #expect(MentionQuery.matches(all, query: "ПЛАНЕ", limit: 10).count == 1)
        #expect(MentionQuery.matches(all, query: "планё", limit: 10).count == 1)
    }

    @Test("Пустой запрос показывает начало списка, и не длиннее потолка")
    func пустойЗапросПоказываетВсё() {
        let all = (1...10).map { event("Встреча \($0)", handle: "e\($0)") }
        #expect(MentionQuery.matches(all, query: "", limit: 4).count == 4)
        #expect(MentionQuery.matches(all, query: "", limit: 4).first?.handle == "e1")
    }

    @Test("Не нашлось — список пуст, а не полон случайного")
    func ничегоНеНашлось() {
        #expect(MentionQuery.matches([event("Планёрка")], query: "зубной", limit: 10).isEmpty)
    }

    // MARK: - Что уходит модели

    /// Стёртое упоминание не должно оставаться в поле зрения помощника:
    /// иначе он отменит встречу, о которой в вопросе уже ни слова.
    @Test("Стёртое из текста указание до модели не доходит")
    func стёртоеНеУходит() {
        let planning = event("Планёрка", handle: "e1")
        let dentist = event("Зубной", handle: "e2")
        let alive = MentionQuery.surviving([planning, dentist], in: "отмени @Зубной")
        #expect(alive.map(\.handle) == ["e2"])
        #expect(MentionQuery.surviving([planning], in: "отмени встречу").isEmpty)
    }

    @Test("В тексте указание видно словом")
    func указаниеВидноСловом() {
        #expect(event("Планёрка").token == "@Планёрка")
        #expect(note("Идеи").token == "@Идеи")
    }

    // MARK: - Перенос по дню

    /// «Перенеси на четверг» — это про день: часа человек не называл,
    /// и взять полночь значило бы переставить встречу на ночь.
    @Test("День без часа сохраняет час встречи")
    func деньБезЧасаХранитЧас() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let was = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10, minute: 30))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 9, day: 17))!

        let moved = AgentTime.keepingTime(of: was, onDayOf: target, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moved)
        #expect(parts.day == 17)
        #expect(parts.hour == 10)
        #expect(parts.minute == 30)
    }
}
