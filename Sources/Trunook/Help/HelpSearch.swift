import Foundation

/// Поиск темы справки по вопросу человека.
///
/// Без списка стоп-слов: «как», «что», «настроить» и их двойники в двух
/// других языках пришлось бы держать тремя списками и пополнять руками.
/// Вместо этого слово, встречающееся в трети тем, само перестаёт что-либо
/// значить — это считается прямо по справочнику и работает на любом языке.
///
/// Склонения снимаются грубо — отсечением окончания: «сводку», «сводки»
/// и «сводка» сходятся на «сводк». Настоящего разбора морфологии тут нет
/// и не нужно: справочник маленький, а промах стоит одной лишней темы
/// в ответе, а не неверного действия.
enum HelpSearch {
    /// Слова вопроса: строчными, без знаков препинания, короткие отброшены.
    static func tokens(of text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 }
    }

    /// Чем слово склоняется: гласные, мягкий и твёрдый знаки, «й».
    /// Латинская «s» — множественное число в английском окне: «notes»
    /// сходится с «note».
    private static let endings: Set<Character> = [
        "а", "я", "ы", "и", "у", "ю", "е", "ё", "о", "ь", "й", "ъ", "s",
    ]

    /// Слово без окончания: «воде», «вода» и «воду» сходятся на «вод».
    ///
    /// Сравнение по первым пяти буквам, стоявшее здесь раньше, на коротких
    /// словах врало: «воде» и «вода» расходятся уже на четвёртой, и вопрос
    /// «как включить уведомления о воде» ушёл в тему сводок — там нашлось
    /// слово «включите». Поймано живой проверкой, а не тестом.
    ///
    /// Снимается не больше двух букв и никогда — если от слова осталось бы
    /// меньше трёх: «уведомления» → «уведомлен», «дела» → «дел».
    static func stem(_ word: String) -> String {
        var result = Substring(word)
        for _ in 0..<2 {
            guard result.count > 3, let last = result.last, endings.contains(last) else { break }
            result = result.dropLast()
        }
        return String(result)
    }

    /// Есть ли слово в тексте — по корню, а не целиком.
    ///
    /// Короткие корни сверяются целиком: «код» не должен ловить «кодировку»,
    /// а вот «сводк» обязано ловить «сводках».
    static func contains(_ token: String, in text: String) -> Bool {
        let needle = stem(token)
        return tokens(of: text).contains { word in
            let hay = stem(word)
            guard needle.count >= 4, hay.count >= 4 else { return hay == needle }
            return hay.hasPrefix(needle) || needle.hasPrefix(hay)
        }
    }

    /// Темы, подходящие под вопрос, — самые близкие первыми.
    ///
    /// Заголовок весит больше слов поиска, а те — больше текста: тема, чьё
    /// имя человек назвал прямо, обязана обойти ту, где это слово мелькнуло
    /// в описании.
    static func find(_ query: String, in topics: [HelpTopic], limit: Int = 3) -> [HelpTopic] {
        let asked = tokens(of: query)
        guard !asked.isEmpty else { return [] }

        // Слово, попавшее в треть тем и больше, ничего не различает: так
        // отсеиваются «настройки», «приложение» и «как» — без списка слов.
        let commonLimit = max(2, topics.count / 3)
        let rare = asked.filter { token in
            topics.filter { contains(token, in: $0.text) }.count <= commonLimit
        }

        // Счёт собирается шагами, а не одной цепочкой `map`–`filter`–`sorted`:
        // вывод типов на такой цепочке с кортежем не укладывается в отведённое
        // компилятору время и валит сборку целиком.
        var scored: [(order: Int, topic: HelpTopic, score: Int)] = []
        for (order, topic) in topics.enumerated() {
            var score = 0
            for token in asked {
                if contains(token, in: topic.title) { score += 3 }
                if contains(token, in: topic.keywords) { score += 2 }
                if rare.contains(token), contains(token, in: topic.text) { score += 1 }
            }
            // Одного совпадения в описании мало: «сколько» из вопроса
            // «сколько лететь до Марса» стоит и в рассказе про буфер обмена,
            // и тема ушла бы модели как ответ. Заголовок и слова поиска
            // весят больше и проходят сами.
            if score > 1 { scored.append((order, topic, score)) }
        }

        // По убыванию веса, а при равном — в порядке справочника: он и есть
        // «от главного к мелочам».
        scored.sort { left, right in
            left.score == right.score ? left.order < right.order : left.score > right.score
        }
        return scored.prefix(limit).map(\.topic)
    }
}
