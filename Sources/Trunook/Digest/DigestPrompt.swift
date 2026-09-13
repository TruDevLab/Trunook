import Foundation

/// Промты сводки и разбор ответов модели.
///
/// Чистые функции под тестом, по образцу `TranscriptSummary`: маленькая
/// модель отвечает то списком, то с пояснением сверху, то с точкой вместо
/// черты, и каждый случай ловится своим правилом.
enum DigestPrompt {
    static let maxEntries = 5
    static let maxQueries = 3

    // MARK: - Поисковые запросы из темы

    static func queriesPrompt(topic: String) -> String {
        """
        Человек хочет получать новости по теме: «\(topic)».
        Составь до \(maxQueries) коротких поисковых запросов для поиска новостей, \
        по два-четыре слова, на языке темы. Каждый запрос — с новой строки, \
        без нумерации, кавычек и пояснений.
        """
    }

    static func parseQueries(_ raw: String) -> [String] {
        cleanList(raw, limit: maxQueries, maxLength: 80, excluding: [])
    }

    /// Список строк из ответа: без нумерации, кавычек, пояснений «Вот темы:»
    /// и повторов — в том числе того, что уже есть.
    private static func cleanList(_ raw: String, limit: Int, maxLength: Int, excluding: [String]) -> [String] {
        var result: [String] = []
        for line in lines(of: raw) {
            var item = stripListMarker(line)
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: "\"«»“”'`*").union(.whitespaces))
            guard !item.isEmpty, item.count <= maxLength, !item.hasSuffix(":") else { continue }
            let taken = result + excluding
            guard !taken.contains(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) else { continue }
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Подсказка тем

    static let maxSuggestions = 8

    /// Модель предлагает темы, человек отмечает нужные.
    ///
    /// Названия заметок — только если модель местная (решает вызывающий):
    /// по ним видно, чем человек занят, а отдавать это чужому серверу ради
    /// подсказки не за что. Без них модель предлагает темы разных областей.
    static func suggestionsPrompt(existing: [String], noteTitles: [String], language: Language) -> String {
        // Промт подбирался на `qwen3:8b` без раздумий. Без образцов «хорошо»
        // и «плохо» модель уходила в крайности: то голые сферы («Наука»),
        // то заголовки событий («Повышение пенсионного возраста»), а пример
        // без запрета просачивался в ответ дословно. С названиями заметок
        // первым заходом выдала их же — вместе с номером задачи из трекера.
        var parts = ["""
            Предложи \(maxSuggestions) тем для ежедневной сводки новостей.

            Тема — постоянная область интереса, по которой новости выходят каждую неделю: \
            шире одного события, уже целой сферы, два-четыре слова.
            Хорошо: «кибербезопасность», «кинопремьеры», «электромобили».
            Плохо: «Наука» — слишком широко; «Повышение пенсионного возраста» — это одно событие, а не тема.
            Примеры выше не предлагай — придумай свои.
            """]
        if noteTitles.isEmpty {
            parts.append("Все темы — из разных сфер жизни: наука, культура, спорт, путешествия, "
                         + "здоровье, еда, природа, технологии и другие.")
        } else {
            parts.append("Названия заметок человека — только чтобы понять, чем он занимается:\n"
                         + noteTitles.map { "- \($0)" }.joined(separator: "\n"))
            parts.append("3 темы — про его профессию или отрасль, как о ней пишут в прессе, "
                         + "а не про его рабочие задачи и не слова из заметок. Остальные — из разных сфер "
                         + "жизни: наука, культура, спорт, путешествия, здоровье, еда, природа и другие.")
        }
        if !existing.isEmpty {
            parts.append("Уже выбраны, не повторяй: " + existing.joined(separator: "; "))
        }
        parts.append("Каждая тема — с новой строки, без нумерации, кавычек и пояснений. "
                     + "Язык тем — \(languageName(language)).")
        return parts.joined(separator: "\n\n")
    }

    static func parseSuggestions(_ raw: String, existing: [String], noteTitles: [String] = []) -> [String] {
        // С заглавной: модель пишет то так, то эдак, а в списке тем разнобой
        // читается небрежностью.
        cleanList(raw, limit: maxSuggestions, maxLength: 50, excluding: existing + noteTitles)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    // MARK: - Отбор новостей

    /// Модель выбирает новости **по номерам**, а ссылку берёт приложение.
    /// Попроси её написать ссылку — маленькая модель однажды её выдумает,
    /// и человек уйдёт по несуществующему адресу из сводки, которой доверял.
    ///
    /// Номера в квадратных скобках, а пример — с номером не из начала списка.
    /// Проверено на `qwen3:8b` без раздумий. С номерами «1.» модель либо
    /// нумеровала ответ по порядку («1. 2 | …», и ссылка съезжала на соседнюю
    /// новость), либо переписывала заголовок вместо пересказа. Скобки она
    /// копирует как метку, а просьба «другими словами, чем в заголовке»
    /// с примером даёт настоящее предложение.
    static func selectionPrompt(topic: String, candidates: [NewsItem], language: Language) -> String {
        let list = candidates.enumerated().map { index, item in
            "[\(index + 1)] \(item.title) (\(item.source))"
        }.joined(separator: "\n")
        return """
            Тема: «\(topic)».
            Заголовки новостей, у каждого свой номер в квадратных скобках:
            \(list)

            Задание: выбери до \(maxEntries) самых важных новостей по теме (одно событие — одна новость) \
            и для каждой объясни своими словами, почему это важно для человека, который следит за темой. \
            Самое важное — первым. Пиши только то, что следует из заголовка.

            Формат — только строки вида:
            [номер заголовка из списка] | объяснение в 10–20 слов, другими словами, чем в заголовке

            Номер копируй из списка как есть, не нумеруй по порядку. Пример для заголовка \
            «[12] В городе открылась новая линия метро»:
            [12] | Дорога из спальных районов в центр станет короче, а наземный транспорт разгрузится.

            Объяснения — \(languageName(language)). Если по теме ничего нет — ответь НЕТ.
            """
    }

    /// Выбор модели: номер кандидата (с нуля) и её предложение.
    struct Pick: Equatable {
        let index: Int
        let summary: String
    }

    /// Пересказ, который просто повторяет заголовок, не нужен: заголовок
    /// и так стоит строкой выше. Маленькая модель так делает, если её
    /// не остановить, — и пересказ под новостью читался бы эхом.
    static func dropsEcho(_ pick: Pick, title: String) -> Pick {
        let summary = NewsCandidates.normalized(pick.summary)
        let heading = NewsCandidates.normalized(title)
        guard !heading.isEmpty, summary.hasPrefix(heading) else { return pick }
        return Pick(index: pick.index, summary: "")
    }

    static func parseSelection(_ raw: String, count: Int) -> [Pick] {
        var picks: [Pick] = []
        var used = Set<Int>()
        for line in lines(of: raw) {
            guard let pick = pick(from: line, count: count), used.insert(pick.index).inserted else { continue }
            picks.append(pick)
            if picks.count == maxEntries { break }
        }
        return picks
    }

    /// «3 | текст», «3. текст», «3) текст», «[3] текст», «- 3 — текст».
    private static func pick(from line: String, count: Int) -> Pick? {
        var rest = Substring(stripBullet(line))
        if rest.hasPrefix("[") { rest = rest.dropFirst() }
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, var number = Int(digits) else { return nil }
        rest = rest.dropFirst(digits.count)
        if rest.hasPrefix("]") { rest = rest.dropFirst() }
        // Разделитель обязателен: без него «2025 год стал…» читалось бы
        // как новость под номером 2025.
        let separators: Set<Character> = ["|", ".", ")", ":", "-", "—", "–"]
        let trimmed = rest.drop(while: { $0 == " " })
        guard let first = trimmed.first, separators.contains(first) else { return nil }
        var summary = trimmed.dropFirst()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "|—–-")))
        // «1. 2 | текст»: модель пронумеровала строки по порядку и только
        // потом назвала номер заголовка. Номер перед чертой главнее — иначе
        // ссылка первой новости списка встала бы под пересказ второй.
        let inner = summary.prefix(while: \.isNumber)
        if !inner.isEmpty, inner.count <= 3, let second = Int(inner) {
            let after = summary.dropFirst(inner.count).drop(while: { $0 == " " })
            if after.first == "|" {
                number = second
                summary = after.dropFirst().trimmingCharacters(in: .whitespaces)
            }
        }
        let index = number - 1
        guard (0..<count).contains(index) else { return nil }
        return Pick(index: index, summary: summary)
    }

    // MARK: - Общее

    /// Строки ответа без рассуждений. Раздумья обычно приходят отдельным
    /// полем, но модель, которой их не выключили, пишет `<think>` прямо
    /// в текст — а номера внутри раздумий за выбор считать нельзя.
    static func lines(of raw: String) -> [String] {
        var text = raw
        while let open = text.range(of: "<think>") {
            if let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                text.removeSubrange(open.lowerBound..<text.endIndex)
            }
        }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        while let first = text.first, "-*•".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text.replacingOccurrences(of: "**", with: "")
    }

    /// Снимает маркер списка вместе с номером — для запросов, где номер
    /// не нужен.
    private static func stripListMarker(_ line: String) -> String {
        let text = stripBullet(line)
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return text }
        let rest = text.dropFirst(digits.count)
        guard let first = rest.first, ".)".contains(first) else { return text }
        return rest.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    static func languageName(_ language: Language) -> String {
        switch language {
        case .en: return "по-английски"
        case .zh: return "по-китайски"
        case .ru, .system: return "по-русски"
        }
    }
}
