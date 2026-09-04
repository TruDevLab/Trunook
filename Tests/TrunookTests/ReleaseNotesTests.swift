import Foundation
import Testing
@testable import Trunook

@Suite("Описания выпусков")
struct ReleaseNoteTests {
    /// Ответ GitHub, обрезанный до того, что читает разбор.
    private let answer = """
    [
      {
        "tag_name": "v0.13.0",
        "name": "Trunook 0.13.0",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-08-31T09:12:44Z",
        "html_url": "https://github.com/TruDevLab/Trunook/releases/tag/v0.13.0",
        "body": "## Стекло\\n\\nПанели стали стеклянными."
      },
      {
        "tag_name": "v0.9.0",
        "name": "",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-07-02T11:00:00Z",
        "html_url": "https://github.com/TruDevLab/Trunook/releases/tag/v0.9.0",
        "body": "Заметки."
      },
      {
        "tag_name": "v0.12.0",
        "draft": false,
        "prerelease": false,
        "published_at": "2026-08-10T11:00:00Z",
        "body": "Автообновление."
      }
    ]
    """

    private func parsed() -> [ReleaseNote] {
        ReleaseNote.parseList(Data(answer.utf8))
    }

    /// Порядок GitHub обещает, но выбор по умолчанию на чужом обещании
    /// строить незачем: 0.9.0 в ответе стоит выше 0.12.0.
    @Test("Выпуски выстраиваются от новых к старым")
    func порядок() {
        #expect(parsed().map(\.version.text) == ["0.13.0", "0.12.0", "0.9.0"])
    }

    @Test("Заголовок берётся у выпуска, а пустой — у тега")
    func заголовок() throws {
        let notes = parsed()
        #expect(notes[0].title == "Trunook 0.13.0")
        // Пустое имя и отсутствующее — одно и то же: показывать пустую строку
        // заголовком нельзя.
        #expect(notes[1].title == "v0.12.0")
        #expect(notes[2].title == "v0.9.0")
    }

    @Test("Описание и ссылка на страницу доходят целиком")
    func описание() throws {
        let note = try #require(parsed().first)
        #expect(note.body.contains("Панели стали стеклянными"))
        #expect(note.pageURL?.absoluteString.hasSuffix("v0.13.0") == true)
        #expect(note.publishedAt != nil)
    }

    /// Черновик — ещё не выпуск, предрелиз приложение не ставит. Показывать
    /// описание к неустановимому значит обещать то, чего нет.
    @Test("Черновик и предрелиз в список не попадают")
    func черновики() {
        let text = """
        [
          {"tag_name": "v1.0.0", "draft": true, "body": "черновик"},
          {"tag_name": "v0.14.0", "prerelease": true, "body": "бета"},
          {"tag_name": "v0.13.0", "body": "выпуск"}
        ]
        """
        #expect(ReleaseNote.parseList(Data(text.utf8)).map(\.tag) == ["v0.13.0"])
    }

    /// Сеть приносит что угодно, и разбор обязан не падать на том, чего не ждал.
    @Test("Мусор и одиночный объект дают пустой список")
    func мусор() {
        #expect(ReleaseNote.parseList(Data()).isEmpty)
        #expect(ReleaseNote.parseList(Data("не json".utf8)).isEmpty)
        // `/releases/latest` отдаёт объект, а не список: перепутанный адрес
        // должен кончиться пустотой, а не разбором наугад.
        #expect(ReleaseNote.parseList(Data(#"{"tag_name": "v0.13.0"}"#.utf8)).isEmpty)
        #expect(ReleaseNote.parseList(Data(#"[{"body": "без тега"}]"#.utf8)).isEmpty)
    }
}

@Suite("Разбор Markdown для окна")
struct WelcomeMarkdownTests {
    private func blocks(_ text: String) -> [WelcomeMarkdown.Block] {
        WelcomeMarkdown.blocks(from: text)
    }

    /// Таблиц в README две, и порознь их ячейки — это набор абзацев с палками
    /// посередине.
    @Test("Таблица собирается целиком, разделитель в неё не попадает")
    func таблица() throws {
        let source = """
        | Сочетание | Что открывает |
        |---|---|
        | ⌃⌥V | История буфера |
        | ⌃⌥S | Полка |
        """
        let result = blocks(source)
        #expect(result.count == 1)
        guard case let .table(_, header, rows) = try #require(result.first) else {
            Issue.record("ожидалась таблица")
            return
        }
        #expect(header == ["Сочетание", "Что открывает"])
        #expect(rows.count == 2)
        #expect(rows[1] == ["⌃⌥S", "Полка"])
    }

    @Test("Текст вокруг таблицы остаётся текстом")
    func текстВокруг() {
        let result = blocks("До\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nПосле")
        let tables = result.filter { if case .table = $0 { return true } else { return false } }
        #expect(tables.count == 1)
        let words = result.compactMap { block -> String? in
            if case let .line(line) = block, !line.plain.isEmpty { return line.plain }
            return nil
        }
        #expect(words == ["До", "После"])
    }

    /// Одна строка с палками — это строка с палками, а не таблица: собранная
    /// из неё шапка без содержимого соврала бы глазу.
    @Test("Одинокая строка с палками таблицей не становится")
    func одинокаяСтрока() {
        let result = blocks("| просто | текст |")
        #expect(result.count == 1)
        if case .table = result[0] { Issue.record("таблицы быть не должно") }
    }

    /// Снимки README лежат в `docs/`, в бандл не едут, и показывать по такой
    /// ссылке нечего.
    @Test("Картинки убираются, подписи вокруг остаются")
    func картинки() {
        #expect(WelcomeMarkdown.stripImages("до ![Жесты](docs/gestures.png) после")
                == "до  после")
        #expect(WelcomeMarkdown.stripImages("![один](a.png)\n![два](b.png)") == "\n")
        // Незакрытая разметка не должна ни съедать текст, ни зацикливать разбор.
        #expect(WelcomeMarkdown.stripImages("![недописанная") == "![недописанная")
        #expect(WelcomeMarkdown.stripImages("![подпись] без ссылки")
                == "![подпись] без ссылки")
    }

    /// Один невидимый знак в хвосте строки разъезжал всю страницу: пустая
    /// строка переставала быть пустой, таблица — таблицей, черта — чертой.
    @Test("Возврат каретки от GitHub не ломает разбор")
    func возвратКаретки() {
        #expect(WelcomeMarkdown.newlines("а\r\nб\rв") == "а\nб\nв")
        // Уже нормальный текст не переписывается.
        #expect(WelcomeMarkdown.newlines("а\nб") == "а\nб")

        let source = "## Шапка\r\n\r\n| a | b |\r\n|---|---|\r\n| 1 | 2 |\r\n"
        let result = blocks(source)
        // Заголовок и таблица — и ни одного пустого абзаца между ними.
        #expect(result.count == 2)
        guard case let .table(_, header, rows) = result[1] else {
            Issue.record("ожидалась таблица")
            return
        }
        #expect(header == ["a", "b"])
        #expect(rows == [["1", "2"]])
    }

    /// Перенос по ширине — это разметка исходника, а не разрыв абзаца.
    @Test("Перенесённые строки склеиваются в один абзац и один пункт")
    func склейка() {
        let result = blocks("Первая строка\nвторая строка\n\nНовый абзац")
        let texts = result.compactMap { block -> String? in
            if case let .line(line) = block { return line.plain }
            return nil
        }
        #expect(texts == ["Первая строка вторая строка", "Новый абзац"])

        let list = blocks("- Пункт, который\n  не влез в строку\n- Второй")
        let items = list.compactMap { block -> String? in
            if case let .line(line) = block, case .item = line.kind { return line.plain }
            return nil
        }
        #expect(items == ["Пункт, который не влез в строку", "Второй"])
    }

    @Test("Разделитель узнаётся с выравниванием и без")
    func разделитель() {
        #expect(WelcomeMarkdown.isSeparator(["---", ":---:", "---:"]))
        #expect(!WelcomeMarkdown.isSeparator(["---", "текст"]))
        #expect(!WelcomeMarkdown.isSeparator([":", "---"]))
    }
}

@Suite("Чем встретить запуск")
struct LaunchKindTests {
    @Test("Первый запуск вообще — знакомство, а не поздравление")
    func первыйЗапуск() {
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: nil, hasSeenWelcome: false)
                == .firstEver)
    }

    /// Случится ровно раз у каждого: версия, поставившая приложение, номер
    /// запуска ещё не записывала.
    @Test("Пустая запись у прошедшего знакомство — это обновление")
    func пустаяЗаписьПослеЗнакомства() {
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: nil, hasSeenWelcome: true)
                == .afterUpdate(from: nil))
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: "", hasSeenWelcome: true)
                == .afterUpdate(from: nil))
    }

    @Test("Та же версия — обычный запуск")
    func обычныйЗапуск() {
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: "0.14.0", hasSeenWelcome: true)
                == .ordinary)
    }

    @Test("Версия выросла — конфетти и описание")
    func обновление() {
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: "0.13.0", hasSeenWelcome: true)
                == .afterUpdate(from: "0.13.0"))
        // Сравнение числами, а не строками: «0.9.0» строкой больше «0.10.0».
        #expect(LaunchKind.resolve(current: "0.10.0", lastRun: "0.9.0", hasSeenWelcome: true)
                == .afterUpdate(from: "0.9.0"))
    }

    /// Откат на прежнюю версию — не повод для конфетти: нового в ней нет.
    @Test("Откат назад празднику не повод")
    func откат() {
        #expect(LaunchKind.resolve(current: "0.13.0", lastRun: "0.14.0", hasSeenWelcome: true)
                == .ordinary)
    }

    @Test("Испорченная запись не роняет запуск в праздник")
    func мусорВЗаписи() {
        #expect(LaunchKind.resolve(current: "0.14.0", lastRun: "мусор", hasSeenWelcome: true)
                == .ordinary)
    }
}

@Suite("Конфетти")
struct ConfettiTests {
    private let pieces = Confetti.pieces(seed: 42)

    @Test("Бумажки летят в обе стороны и ни одна не выходит из веера")
    func веер() {
        #expect(pieces.count == Confetti.count)
        // Веер раскрыт вниз: угол от нуля до π, то есть без единой бумажки,
        // ушедшей вверх — там кромка экрана, лететь некуда.
        #expect(pieces.allSatisfy { $0.angle > 0 && $0.angle < .pi })
        let spots = pieces.compactMap { Confetti.state(of: $0, elapsed: 0.5)?.offset.x }
        #expect(spots.contains { $0 < -40 })
        #expect(spots.contains { $0 > 40 })
    }

    /// Задержка вылета: без неё все бумажки выходят одним диском, и залп
    /// читается кольцом.
    @Test("До своего срока бумажка не вылетает")
    func задержка() {
        let piece = ConfettiPiece(
            angle: .pi / 2, speed: 300,
            size: CGSize(width: 6, height: 10),
            spin: 1, colorIndex: 0, delay: 0.2
        )
        #expect(Confetti.state(of: piece, elapsed: 0.1) == nil)
        #expect(Confetti.state(of: piece, elapsed: 0.3) != nil)
    }

    /// Пара секунд — и всё. Незакрывшийся залп означал бы окно во весь экран,
    /// висящее поверх работы неизвестно сколько.
    @Test("Залп заканчивается в срок и гаснет перед концом")
    func срок() throws {
        let piece = try #require(pieces.first)
        #expect(Confetti.state(of: piece, elapsed: Confetti.duration) == nil)
        #expect(Confetti.state(of: piece, elapsed: Confetti.duration + 1) == nil)
        let fading = try #require(Confetti.state(of: piece, elapsed: Confetti.duration - 0.2))
        let full = try #require(Confetti.state(of: piece, elapsed: 0.5))
        #expect(fading.opacity < full.opacity)
    }

    @Test("Бумажка падает: вниз она уходит быстрее, чем летит вбок")
    func падение() {
        let piece = ConfettiPiece(
            angle: .pi / 2, speed: 300,
            size: CGSize(width: 6, height: 10),
            spin: 0, colorIndex: 0, delay: 0
        )
        let early = Confetti.state(of: piece, elapsed: 0.3)?.offset.y ?? 0
        let late = Confetti.state(of: piece, elapsed: 0.9)?.offset.y ?? 0
        #expect(late > early * 3)
    }

    /// Тот же залп при том же зерне: иначе проверять было бы нечего.
    @Test("Зерно повторяет залп")
    func зерно() {
        #expect(Confetti.pieces(seed: 7) == Confetti.pieces(seed: 7))
        #expect(Confetti.pieces(seed: 7) != Confetti.pieces(seed: 8))
    }
}
