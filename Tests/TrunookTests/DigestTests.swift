import AppKit
import Foundation
import Testing
@testable import Trunook

@Suite("Расписание сводки")
struct DigestScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // Сентябрь 2026: 13-е — воскресенье, 14-е — понедельник.
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test("В десять утра, если с прошлой сборки срок наступил")
    func вДесятьУтра() {
        let schedule = DigestSchedule()
        #expect(schedule.isDue(now: date(13, 10, 0), last: date(12, 10, 1), calendar: calendar))
        #expect(!schedule.isDue(now: date(13, 9, 59), last: date(12, 10, 1), calendar: calendar))
    }

    @Test("Собранная сегодня сводка до завтра не повторяется")
    func сегодняНеПовторяется() {
        let schedule = DigestSchedule()
        #expect(!schedule.isDue(now: date(13, 18), last: date(13, 10, 1), calendar: calendar))
    }

    /// Три дня сна — одна сводка при пробуждении, а не три.
    @Test("Пропущенные сроки догоняются одним разом")
    func догонОднимРазом() {
        let schedule = DigestSchedule()
        let woke = date(16, 8)
        #expect(schedule.isDue(now: woke, last: date(12, 10, 1), calendar: calendar))
        #expect(!schedule.isDue(now: woke.addingTimeInterval(60), last: woke, calendar: calendar))
    }

    @Test("Не выбранный день пропускается")
    func толькоВыбранныеДни() {
        var schedule = DigestSchedule()
        schedule.weekdays = [2]  // понедельник
        #expect(!schedule.isDue(now: date(13, 11), last: date(12, 11), calendar: calendar))
        #expect(schedule.isDue(now: date(14, 11), last: date(13, 11), calendar: calendar))
    }

    @Test("Без дней сводка не собирается никогда")
    func безДней() {
        var schedule = DigestSchedule()
        schedule.weekdays = []
        #expect(!schedule.isDue(now: date(14, 11), last: date(1, 11), calendar: calendar))
    }

    @Test("Отсчёт: без прошлой сборки и при дате из будущего — от «сейчас»")
    func отсчёт() {
        let now = date(13, 15)
        #expect(DigestSchedule.anchor(now: now, last: nil) == now)
        #expect(DigestSchedule.anchor(now: now, last: date(20, 10)) == now)
        #expect(DigestSchedule.anchor(now: now, last: date(12, 10)) == date(12, 10))
    }

    @Test("Период поиска — не меньше суток и не больше недели")
    func период() {
        let now = date(13, 10)
        let day: TimeInterval = 86_400
        #expect(DigestSchedule.since(now: now, last: nil) == now.addingTimeInterval(-day))
        #expect(DigestSchedule.since(now: now, last: date(13, 9)) == now.addingTimeInterval(-day))
        #expect(DigestSchedule.since(now: now, last: date(10, 10)) == date(10, 10))
        #expect(DigestSchedule.since(now: now, last: date(1, 10)) == now.addingTimeInterval(-7 * day))
    }
}

@Suite("Лента новостей")
struct NewsFeedTests {
    private let sample = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Google Новости</title>
        <item><title>В городе открылась новая линия метро - URA.RU</title>
        <link>https://news.google.com/rss/articles/one?oc=5</link>
        <pubDate>Sun, 13 Sep 2026 04:42:00 GMT</pubDate>
        <description>&lt;a href="x"&gt;…&lt;/a&gt;</description>
        <source url="https://ura.news">URA.RU</source></item>
        <item><title>Спартак - Зенит: кто сильнее - bbc.com</title>
        <link>https://news.google.com/rss/articles/two?oc=5</link>
        <pubDate>Sat, 12 Sep 2026 23:52:15 GMT</pubDate>
        <source url="https://www.bbc.com">bbc.com</source></item>
        <item><title>Без даты</title><link>https://example.com</link></item>
        </channel></rss>
        """

    @Test("Разбирает заголовок, источник, ссылку и время")
    func разбор() throws {
        let items = NewsFeedParser.parse(Data(sample.utf8))
        #expect(items.count == 2)
        let first = try #require(items.first)
        #expect(first.title == "В городе открылась новая линия метро")
        #expect(first.source == "URA.RU")
        #expect(first.link.absoluteString == "https://news.google.com/rss/articles/one?oc=5")
        #expect(first.published == NewsFeedParser.date("Sun, 13 Sep 2026 04:42:00 GMT"))
    }

    /// Дефис внутри заголовка — часть заголовка, снимается только хвост
    /// с именем источника.
    @Test("Снимается только хвост с источником")
    func хвостИсточника() {
        #expect(NewsFeedParser.cleanTitle("Спартак - Зенит: кто сильнее - bbc.com", source: "bbc.com")
                == "Спартак - Зенит: кто сильнее")
        #expect(NewsFeedParser.cleanTitle("Спартак - Зенит", source: "bbc.com") == "Спартак - Зенит")
        #expect(NewsFeedParser.cleanTitle("Сезон дождей - NEWSru.co.il - NEWSru.co.il", source: "NEWSru.co.il")
                == "Сезон дождей")
    }

    @Test("Кандидаты: свежие, без повторов, новые первыми, не больше предела")
    func кандидаты() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        func item(_ title: String, _ hours: Double) -> NewsItem {
            NewsItem(title: title, source: "s", link: URL(string: "https://e.com/\(hours)")!,
                     published: base.addingTimeInterval(hours * 3600))
        }
        let items = [item("Старое", -30), item("Первое", 1), item("ПЕРВОЕ!", 2), item("Второе", 3)]
        let prepared = NewsCandidates.prepare(items, since: base.addingTimeInterval(-24 * 3600))
        #expect(prepared.map(\.title) == ["Второе", "ПЕРВОЕ!"])
        #expect(NewsCandidates.prepare(items, since: .distantPast, limit: 1).count == 1)
    }

    @Test("Издание по буквам запроса, без них — по интерфейсу")
    func издание() {
        #expect(NewsFeed.edition(for: "ставка по вкладам", interface: .en) == NewsFeed.russian)
        #expect(NewsFeed.edition(for: "人工智能", interface: .ru) == NewsFeed.chinese)
        #expect(NewsFeed.edition(for: "NASA", interface: .ru) == NewsFeed.russian)
        #expect(NewsFeed.edition(for: "NASA", interface: .en) == NewsFeed.english)
    }

    @Test("Адрес поиска несёт период в днях")
    func адрес() throws {
        let now = Date()
        let url = try #require(NewsFeed.url(
            query: "кино", since: now.addingTimeInterval(-36 * 3600), now: now, edition: NewsFeed.russian
        ))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "q" }?.value == "кино when:2d")
        #expect(items.first { $0.name == "hl" }?.value == "ru")
    }
}

@Suite("Ответ модели в сводке")
struct DigestPromptTests {
    @Test("Номера с разными разделителями")
    func разделители() {
        let raw = """
            Вот самые важные:
            3 | Первое событие.
            1. Второе событие.
            **2)** Третье.
            - [4] — Четвёртое
            """
        let picks = DigestPrompt.parseSelection(raw, count: 5)
        #expect(picks.map(\.index) == [2, 0, 1, 3])
        #expect(picks.first?.summary == "Первое событие.")
        #expect(picks.last?.summary == "Четвёртое")
    }

    /// Пойман на живой сводке: `qwen3:8b` ответил «1. 2 | заголовок (источник)»,
    /// и под пересказом второй новости встала ссылка первой.
    @Test("Порядковый номер перед номером заголовка не путает выбор")
    func двойнойНомер() {
        let raw = "1. 2 | Театр объявил новый сезон (Афиша)\n2. 17 | Запуск ракеты перенесли"
        #expect(DigestPrompt.parseSelection(raw, count: 20).map(\.index) == [1, 16])
        #expect(DigestPrompt.parseSelection(raw, count: 20).last?.summary == "Запуск ракеты перенесли")
    }

    @Test("Пересказ, повторяющий заголовок, отбрасывается")
    func эхоЗаголовка() {
        let pick = DigestPrompt.Pick(index: 0, summary: "В городе открылась новая линия метро (URA.RU)")
        #expect(DigestPrompt.dropsEcho(pick, title: "В городе открылась новая линия метро").summary.isEmpty)
        let real = DigestPrompt.Pick(index: 0, summary: "Дорога в центр станет короче.")
        #expect(DigestPrompt.dropsEcho(real, title: "В городе открылась новая линия").summary == real.summary)
    }

    @Test("Номер вне списка, повтор и год без разделителя отбрасываются")
    func мусор() {
        let raw = "9 | нет такого\n2 | есть\n2 | повтор\n2025 год стал рекордным"
        #expect(DigestPrompt.parseSelection(raw, count: 3) == [DigestPrompt.Pick(index: 1, summary: "есть")])
    }

    @Test("Больше пяти обрезается, «НЕТ» даёт пустую тему")
    func пределИНет() {
        let many = (1...8).map { "\($0) | новость" }.joined(separator: "\n")
        #expect(DigestPrompt.parseSelection(many, count: 8).count == 5)
        #expect(DigestPrompt.parseSelection("НЕТ", count: 8).isEmpty)
    }

    @Test("Номера внутри раздумий за выбор не считаются")
    func раздумья() {
        let raw = "<think>\n1 | может это\n</think>\n2 | вот это"
        #expect(DigestPrompt.parseSelection(raw, count: 3).map(\.index) == [1])
    }

    @Test("Запросы: без нумерации, кавычек, повторов и пояснений")
    func запросы() {
        let raw = "Запросы:\n1. «космические запуски»\n- новости космонавтики\nНовости космонавтики\n\"NASA\"\nлишний"
        #expect(DigestPrompt.parseQueries(raw) == ["космические запуски", "новости космонавтики", "NASA"])
    }

    @Test("Подсказки тем: без пояснений, повторов и уже выбранного, не больше восьми")
    func подсказкиТем() {
        let raw = "Вот темы:\n1. Космические запуски\n- «Новинки кино»\nкосмические запуски\nПогода\n"
            + (1...10).map { "Тема \($0)" }.joined(separator: "\n")
        let parsed = DigestPrompt.parseSuggestions(raw, existing: ["погода"])
        #expect(Array(parsed.prefix(2)) == ["Космические запуски", "Новинки кино"])
        #expect(!parsed.contains("Погода"))
        #expect(parsed.count == DigestPrompt.maxSuggestions)
        // Модель однажды вернула названия заметок как темы.
        let echoed = DigestPrompt.parseSuggestions("TASK-101: ремонт кухни\nГородские события",
                                                   existing: [], noteTitles: ["TASK-101: ремонт кухни"])
        #expect(echoed == ["Городские события"])
    }

    @Test("Названия заметок попадают в подсказку, только когда их передали")
    func заметкиВПодсказке() {
        let with = DigestPrompt.suggestionsPrompt(existing: [], noteTitles: ["Ремонт кухни"], language: .ru)
        let without = DigestPrompt.suggestionsPrompt(existing: [], noteTitles: [], language: .ru)
        #expect(with.contains("Ремонт кухни"))
        #expect(!without.contains("заметок"))
    }

    @Test("Без переписанных запросов ищется само название")
    func запросПоНазванию() {
        #expect(DigestTopic(id: 0, title: "Кино").searchQueries == ["Кино"])
        #expect(DigestTopic(id: 0, title: "Кино", queries: [" ", "кинопремьеры"]).searchQueries == ["кинопремьеры"])
    }
}

@Suite("Сводка в Markdown и заметке")
struct DigestExportTests {
    private let digest = Digest(
        createdAt: Date(timeIntervalSince1970: 1_789_300_000),
        since: Date(timeIntervalSince1970: 1_789_213_600),
        sections: [
            DigestSection(id: 0, title: "Кино", entries: [
                DigestEntry(title: "Модель [beta] вышла", source: "bbc.com",
                            link: URL(string: "https://e.com/a")!,
                            published: Date(timeIntervalSince1970: 1_789_290_000),
                            summary: "Важно."),
            ]),
            DigestSection(id: 1, title: "Рынок", entries: []),
            DigestSection(id: 2, title: "Погода", entries: [], failed: true),
        ]
    )

    @Test("Темы заголовками, новости ссылками, скобки экранированы")
    func разметка() {
        let text = DigestExport.markdown(for: digest)
        #expect(text.contains("## Кино"))
        #expect(text.contains("- [Модель \\[beta\\] вышла](https://e.com/a) — bbc.com"))
        #expect(text.contains("  Важно."))
        #expect(text.contains("## Рынок\n_"))
        #expect(text.hasSuffix("\n"))
    }

    @Test("В заметке ссылка лежит атрибутом, а тема — крупным кеглем")
    func заметка() {
        let note = DigestExport.attributed(for: digest)
        let string = note.string as NSString
        let link = string.range(of: "Модель [beta] вышла")
        #expect(note.attribute(.link, at: link.location, effectiveRange: nil) as? URL
                == URL(string: "https://e.com/a"))
        let font = note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == Note.headingFontSize)
    }

    @Test("Имя файла начинается с даты")
    func имяФайла() {
        #expect(DigestExport.fileName(for: digest).hasSuffix(".md"))
        #expect(DigestExport.fileName(for: digest).hasPrefix("2026-"))
    }
}
