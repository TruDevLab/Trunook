import Foundation

/// Что модель вынесла из разговора.
struct RecordingSummary: Equatable {
    /// Название заметки. `nil` — модель его не дала, останется запасное.
    var title: String?
    var summary: String
    var tasks: [String]

    var isEmpty: Bool { title == nil && summary.isEmpty && tasks.isEmpty }
}

/// Промты к модели и разбор её ответа.
///
/// Чистые функции, все под тестом. Причина та же, что у `SyncPlan`: живую
/// модель в тест не позвать, а ошибиться здесь легко — маленькая модель
/// отвечает то списком, то абзацем, то с пояснением сверху, и каждый
/// из этих случаев ловится своим правилом.
enum TranscriptSummary {
    // MARK: - Нарезка

    /// Сколько знаков уходит в один заход к модели.
    ///
    /// Час разговора — около шестидесяти тысяч знаков, в одно окно это
    /// не влезает. Двенадцать тысяч проходят даже у маленькой местной
    /// модели и оставляют ей место на ответ.
    static let chunkLimit = 12_000

    /// Режет длинную расшифровку на куски по границам предложений.
    ///
    /// По предложениям, а не по знакам ровно: разрезанная посреди фразы
    /// мысль теряется в обеих половинах, и пересказ выходит про другое.
    ///
    /// Предложение длиннее предела — редкость (расшифровка без знаков
    /// препинания), но она возможна, и тогда кусок выходит длиннее предела.
    /// Это лучше, чем потерять его вовсе.
    static func chunks(of text: String, limit: Int = chunkLimit) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > limit else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences(of: trimmed) {
            if current.isEmpty {
                current = sentence
            } else if current.count + 1 + sentence.count <= limit {
                current += " " + sentence
            } else {
                chunks.append(current)
                current = sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Разбивает текст на предложения.
    ///
    /// Точка, вопрос, восклицание и перевод строки. Многоточие при этом
    /// не даёт трёх пустых предложений: пустые куски отбрасываются.
    private static func sentences(of text: String) -> [String] {
        var result: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            let isBreak = character == "." || character == "!" || character == "?"
                || character.isNewline
            if isBreak {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { result.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    // MARK: - Промты

    /// Что записывали.
    ///
    /// Разница не в оформлении, а в том, кто говорил. Первый живой пересказ
    /// аудиозаметки вышел так: «Мы решили купить хлеб. И договорились пойти
    /// в парк». Ни «мы», ни «договорились» там не было — человек наговорил
    /// себе список дел, а модель добросовестно достроила собеседников,
    /// потому что промт обещал ей «разговор».
    enum Kind {
        /// Встреча: писались две дорожки, собеседники слышны.
        case conversation
        /// Аудиозаметка: один микрофон, один голос.
        case dictation

        /// Как назвать записанное в промте.
        var source: String {
            switch self {
            case .conversation: return "расшифровка разговора"
            case .dictation: return "расшифровка того, что человек наговорил сам себе"
            }
        }

        /// Чего просить в пересказе.
        var ask: String {
            switch self {
            case .conversation: return "два-четыре предложения о том, что обсудили"
            case .dictation: return "два-четыре предложения о том, что человек записал"
            }
        }

        /// Оговорка, без которой модель достраивает недостающее.
        var caution: String {
            switch self {
            case .conversation:
                return "Опирайся только на сказанное, ничего не додумывай."
            case .dictation:
                return "Говорит один человек, собеседников нет. Не пиши «мы» "
                    + "и «договорились», не выдумывай второго участника. "
                    + "Опирайся только на сказанное."
            }
        }
    }

    /// Промт на один кусок записи.
    ///
    /// Формат ответа задан жёстко и тремя метками: разбирать вольный ответ
    /// маленькой модели надёжно не выходит, а три метки она держит.
    static func prompt(for chunk: String, kind: Kind) -> String {
        """
        Ниже \(kind.source). Ответь строго в таком виде, на языке записи:

        НАЗВАНИЕ: короткое название, не больше шести слов
        ПЕРЕСКАЗ: \(kind.ask)
        ЗАДАЧИ:
        - каждая задача с новой строки, начиная с дефиса
        - если задач нет, напиши «нет»

        \(kind.caution)
        Ничего не добавляй сверх этого.

        Расшифровка:
        \(chunk)
        """
    }

    /// Промт на сведение пересказов длинного разговора.
    ///
    /// Второй заход нужен там, где кусков больше одного: пять отдельных
    /// пересказов — это не пересказ встречи, а пять обрывков, и задачи
    /// в них повторяются.
    static func mergePrompt(for parts: [String], kind: Kind) -> String {
        let joined = parts.enumerated()
            .map { "Часть \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")
        let whole = kind == .conversation ? "всей встречи" : "всей записи"
        return """
            Ниже пересказы частей одной записи. Сведи их в один. \
            Ответь строго в таком виде, на языке записи:

            НАЗВАНИЕ: короткое название \(whole), не больше шести слов
            ПЕРЕСКАЗ: три-шесть предложений обо всём вместе
            ЗАДАЧИ:
            - каждая задача с новой строки, начиная с дефиса
            - повторы объедини, если задач нет — напиши «нет»

            \(kind.caution)
            Ничего не добавляй сверх этого.

            \(joined)
            """
    }

    // MARK: - Разбор ответа

    /// Метки разделов. По-русски и по-английски: модель отвечает на языке
    /// разговора, и английский разговор она разметит по-своему.
    private static let titleKeys = ["название", "заголовок", "title", "heading"]
    private static let summaryKeys = ["пересказ", "краткое содержание", "summary", "overview"]
    private static let taskKeys = ["задачи", "задача", "tasks", "action items", "to-do", "todo"]

    /// Слова, которыми модель говорит «задач нет».
    private static let noTasks = ["нет", "нет задач", "none", "no tasks", "—", "-", "无"]

    /// Знаки, которыми модель обрамляет строки.
    private static let trash = CharacterSet(charactersIn: "\"'«»„“”‘’`*#•").union(.whitespaces)

    private enum Key { case title, summary, tasks }

    /// Разбирает ответ модели.
    ///
    /// Возвращает `nil`, когда не нашлось ничего: тогда заметка соберётся
    /// из одной расшифровки, а имя останется запасным. Пустой пересказ
    /// и пустой список задач — законный ответ, и притворяться, что модель
    /// что-то сказала, хуже, чем показать одну расшифровку.
    static func parse(_ raw: String) -> RecordingSummary? {
        enum Section { case none, title, summary, tasks }

        var section = Section.none
        var title: String?
        var summary: [String] = []
        var tasks: [String] = []

        // Резать только по `Character.isNewline`: ответ модели приходит
        // и с `\r\n`, а он — один символ, и `split(separator: "\n")`
        // оставил бы `\r` в хвосте каждой строки. Та же ловушка, что
        // на описаниях выпусков и на файлах хранилища.
        for rawLine in normalized(raw).split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let (key, rest) = header(of: line) {
                switch key {
                case .title:
                    section = .title
                    if !rest.isEmpty { title = clean(rest) }
                case .summary:
                    section = .summary
                    if !rest.isEmpty { summary.append(clean(rest)) }
                case .tasks:
                    section = .tasks
                    tasks.append(contentsOf: splitTasks(rest))
                }
                continue
            }

            switch section {
            case .title where title == nil:
                title = clean(line)
            case .summary:
                summary.append(clean(line))
            case .tasks:
                tasks.append(contentsOf: splitTasks(line))
            case .none, .title:
                continue
            }
        }

        // Название чистится тем же правилом, что и у обычной заметки:
        // модель кричит заглавными одинаково в обоих случаях.
        let name = title.map(NoteTitler.deshouted)
        let result = RecordingSummary(
            title: (name?.isEmpty == false) ? name : nil,
            summary: summary.joined(separator: " ").trimmingCharacters(in: .whitespaces),
            tasks: tasks
        )
        return result.isEmpty ? nil : result
    }

    /// Метка раздела и то, что стоит за ней в той же строке.
    ///
    /// Меткой строка считается, только если она **начинается** с ключевого
    /// слова и выполняется одно из трёх: за словом двоеточие, слово написано
    /// заглавными или на нём строка кончается. Все три — то, как метку пишет
    /// сама модель, повторяя формат из промта.
    ///
    /// Без этой тройки правил «Задачи обсудили в конце встречи…» из пересказа
    /// сошло бы за метку и оборвало его на середине. Прежняя защита —
    /// «голова строки не длиннее двадцати четырёх знаков» — держалась только
    /// пока модель ставила двоеточие, и рассыпалась на ответе одной строкой.
    private static func header(of line: String) -> (Key, String)? {
        let lower = line.lowercased()
        let groups: [(Key, [String])] = [
            (.title, titleKeys), (.summary, summaryKeys), (.tasks, taskKeys),
        ]

        for (key, words) in groups {
            for word in words where lower.hasPrefix(word) {
                let after = line.dropFirst(word.count)
                // Граница слова: «задачами» не метка.
                if let next = after.first, next.isLetter || next.isNumber { continue }

                let head = String(line.prefix(word.count))
                let tail = after.drop(while: { $0 == " " })
                let looksLikeHeader = tail.first == ":"
                    || head == head.uppercased()
                    || tail.isEmpty
                guard looksLikeHeader else { continue }

                let rest = tail.drop(while: { $0 == ":" || $0 == " " })
                return (key, String(rest))
            }
        }
        return nil
    }

    /// Расставляет переносы перед метками, съехавшими в середину строки.
    ///
    /// Так и приехал первый живой ответ: модель написала всё одним абзацем —
    /// «Надо купить хлеб… ЗАДАЧИ - купить хлеб - сходить в парк», — и разбор
    /// по строкам увидел один пересказ, внутри которого лежали и метка,
    /// и обе задачи. Просить модель ставить переносы бесполезно: маленькая
    /// модель формат держит через раз, а разбор обязан работать всегда.
    ///
    /// Перенос ставится только перед настоящей меткой: словом на границе
    /// слова, за которым двоеточие, либо написанным заглавными. «Задачи
    /// на квартал» посреди пересказа под это не подходит.
    static func normalized(_ raw: String) -> String {
        var text = raw
        for key in titleKeys + summaryKeys + taskKeys {
            text = breaking(before: key, in: text)
        }
        return text
    }

    private static func breaking(before key: String, in text: String) -> String {
        var result = ""
        var rest = Substring(text)

        while let range = rest.range(of: key, options: [.caseInsensitive]) {
            let head = rest[..<range.lowerBound]
            let match = rest[range]
            let after = rest[range.upperBound...]

            // Слева и справа должна быть граница слова, иначе это часть
            // другого слова — «задачами», «titles».
            let leftBoundary = (head.last ?? result.last).map { !$0.isLetter && !$0.isNumber } ?? true
            let rightBoundary = after.first.map { !$0.isLetter && !$0.isNumber } ?? true

            let tail = after.drop(while: { $0 == " " })
            let isHeader = tail.first == ":" || match == match.uppercased()
            // Уже с новой строки — вставлять нечего.
            let atLineStart = (head.last ?? result.last).map(\.isNewline) ?? true

            result += head
            if leftBoundary, rightBoundary, isHeader, !atLineStart {
                result += "\n"
            }
            result += match
            rest = after
        }

        return result + rest
    }

    /// Задачи из одной строки.
    ///
    /// Ответив абзацем, модель ставит все задачи подряд через дефис:
    /// «- купить хлеб - сходить в парк». Разрезаем по маркеру с пробелами
    /// вокруг — тире внутри самой задачи так уцелеет чаще, чем нет.
    private static func splitTasks(_ line: String) -> [String] {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var pieces = [line]
        for marker in [" - ", " – ", " — "] {
            pieces = pieces.flatMap { $0.components(separatedBy: marker) }
        }
        return pieces.compactMap { task(from: $0) }
    }

    /// Строка задачи без маркера списка. `nil` — это «задач нет».
    private static func task(from line: String) -> String? {
        var text = line.trimmingCharacters(in: trash)

        // Маркер списка. Дефис нельзя срезать заодно с кавычками: он
        // встречается и внутри задачи — «Позвонить в банк по счёту 12-45», —
        // и общая чистка съела бы его с конца строки. Поэтому только
        // в начале и только вместе с пробелом за ним.
        for marker in ["- ", "– ", "— ", "+ "] where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        // Нумерованный список: «1. Позвонить». Цифра с точкой — маркер,
        // а не текст задачи, и в заметке он оказался бы вторым по счёту.
        if let dot = text.firstIndex(of: "."),
           !text[..<dot].isEmpty, text[..<dot].allSatisfy(\.isNumber) {
            text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        // Чек-бокс, если модель решила разметить сама.
        for marker in ["[ ]", "[x]", "[X]"] where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, !noTasks.contains(text.lowercased()) else { return nil }
        return text
    }

    private static func clean(_ line: String) -> String {
        line.trimmingCharacters(in: trash)
    }
}
