import Foundation

/// Страница вместо содержимого показала отказ.
///
/// Магазины прячутся от роботов, и отказ приходит не ошибкой, а обычной
/// страницей с кодом 200. Без этой проверки модель честно искала бы цену
/// на странице «Похоже, нет соединения» — и сообщала, что цена пропала.
enum PageBlock {
    private static let markers = [
        "captcha", "капча", "не робот", "not a robot", "are you a robot",
        "доступ ограничен", "access denied", "нет соединения", "выключите vpn",
        "checking your browser", "attention required", "just a moment",
        "проверка браузера", "подозрительн", "enable javascript",
    ]

    /// Меньше этого на странице товара не бывает: там хотя бы название,
    /// цена и кнопка.
    static let minimumText = 120

    static func detect(title: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minimumText { return true }
        // Метки ищутся в начале: слово «капча» в отзыве на пятой тысяче
        // знаков страницу отказом не делает.
        let head = (title + "\n" + trimmed.prefix(1_500)).lowercased()
        return markers.contains { head.contains($0) }
    }
}

/// Число из значения: «12 990 ₽», «11 490,50», «$1,299.99», «4,5 из 5».
enum WatchNumber {
    /// Отдельные числа в тексте. Разряды через пробел, запятую или точку —
    /// одно число; всё прочее между цифрами их разделяет.
    static func values(in text: String) -> [Double] {
        let joiners: Set<Character> = [" ", "\u{00A0}", "\u{2009}", "\u{202F}", ",", "."]
        var pieces: [String] = []
        var current = ""
        var pendingJoin = false
        for character in text {
            if character.isASCII, character.isNumber {
                current.append(character)
                pendingJoin = false
            } else if !current.isEmpty, joiners.contains(character), !pendingJoin {
                current.append(character)
                pendingJoin = true
            } else if !current.isEmpty {
                pieces.append(current)
                current = ""
                pendingJoin = false
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces.compactMap(parse)
    }

    static func parse(_ text: String) -> Double? {
        // Пробелы всех видов: магазины разделяют разряды неразрывным
        // и узким неразрывным пробелом, и «12 990» иначе стало бы «12».
        let spaces: Set<Character> = [" ", "\u{00A0}", "\u{2009}", "\u{202F}"]
        let compact = text.filter { !spaces.contains($0) }

        var digits = ""
        var started = false
        for character in compact {
            if character.isASCII, character.isNumber || character == "," || character == "." {
                digits.append(character)
                started = true
            } else if character == "-", !started {
                digits.append(character)
            } else if started {
                break
            }
        }
        digits = digits.trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        guard digits.contains(where: \.isNumber) else { return nil }

        // Номер версии — не число: «0.18.0» по правилу разрядов читалось
        // как 180, и «1.0.0» (100) выходила меньше «0.19.0» (190).
        for separator in [Character(","), Character(".")] {
            let parts = digits.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count > 2, parts.dropFirst().contains(where: { $0.filter(\.isNumber).count != 3 }) {
                return nil
            }
        }

        let lastComma = digits.lastIndex(of: ",")
        let lastDot = digits.lastIndex(of: ".")
        let decimal: Character?
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            decimal = comma > dot ? "," : "."
        case let (comma?, nil):
            decimal = isThousands(digits, separator: ",", last: comma) ? nil : ","
        case let (nil, dot?):
            decimal = isThousands(digits, separator: ".", last: dot) ? nil : "."
        default:
            decimal = nil
        }

        var normalized = ""
        for (index, character) in zip(digits.indices, digits) {
            if character == "," || character == "." {
                if character == decimal, index == (character == "," ? lastComma : lastDot) {
                    normalized.append(".")
                }
            } else {
                normalized.append(character)
            }
        }
        return Double(normalized)
    }

    /// «1,299» и «12.990» — разряды, «4,5» и «12.50» — дробь. Решает число
    /// цифр после знака и то, встречается ли знак больше одного раза.
    private static func isThousands(_ digits: String, separator: Character, last: String.Index) -> Bool {
        if digits.filter({ $0 == separator }).count > 1 { return true }
        return digits[digits.index(after: last)...].count == 3
    }
}

/// Промт на поиск значения и разбор ответа.
enum WatchExtract {
    /// Сколько текста страницы уходит модели. Цена и наличие стоят в начале
    /// страницы товара; хвост — отзывы и «с этим покупают».
    static let pageLimit = 8_000

    static func prompt(target: String, title: String, text: String) -> String {
        """
        Страница: «\(title)».
        Найди на ней: \(target).

        Ответь строго двумя строками:
        ЗНАЧЕНИЕ: как написано на странице
        ЧИСЛО: только число, без пробелов и валюты, или «-», если это не число

        Если на странице этого нет, ответь одним словом: НЕТ.

        Текст страницы:
        \(text.prefix(pageLimit))
        """
    }

    static func parse(_ raw: String) -> WatchReading? {
        let lines = DigestPrompt.lines(of: raw).map { $0.replacingOccurrences(of: "**", with: "") }
        guard let first = lines.first else { return nil }
        let head = first.uppercased()
        if head.hasPrefix("НЕТ") || head.hasPrefix("NONE") || head.hasPrefix("NOT FOUND") { return nil }

        var text: String?
        var number: Double?
        for line in lines {
            if let value = value(of: line, keys: ["ЗНАЧЕНИЕ", "VALUE"]) {
                text = value
            } else if let value = value(of: line, keys: ["ЧИСЛО", "NUMBER"]) {
                number = value == "-" ? nil : WatchNumber.parse(value)
            }
        }
        guard let text, !text.isEmpty, !isRefusal(text) else { return nil }
        let values = WatchNumber.values(in: text)
        // Цифры в значении есть, а числа из них не вышло — это версия
        // или код. Число, которое модель при этом назовёт («0.18»), —
        // её догадка, а не значение со страницы.
        if values.isEmpty, text.contains(where: { $0.isASCII && $0.isNumber }) {
            return WatchReading(text: text, number: nil)
        }
        guard values.count > 1 else {
            return WatchReading(text: text, number: number ?? values.first)
        }
        // Чисел в значении несколько — «80x28x202 cm», «4,5 из 5». Число
        // модели берётся, только если оно одно из них: на размерах полки
        // она склеила все три в 8028202, и порог сравнивал бы бессмыслицу.
        return WatchReading(text: text, number: number.flatMap { values.contains($0) ? $0 : nil })
    }

    /// Отказ, записанный в поле значения: «цена не указана», «не найдено».
    ///
    /// Пойман живьём: на странице релизов GitHub модель на цель «цена»
    /// ответила «ЗНАЧЕНИЕ: цена не указана», и это легло в слежку значением —
    /// следующее «не указана» сравнивалось бы с ним как с ценой.
    static func isRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower == "нет" || lower == "-" || lower == "—" { return true }
        let markers = ["не указан", "не найден", "не обнаружен", "нет данных",
                       "нет информации", "не удалось", "not found", "not specified", "n/a"]
        return markers.contains { lower.contains($0) }
    }

    private static func value(of line: String, keys: [String]) -> String? {
        let upper = line.uppercased()
        for key in keys where upper.hasPrefix(key) {
            let rest = line.dropFirst(key.count).drop(while: { $0 == ":" || $0 == " " })
            return rest.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Похожа ли цель на цену. Тогда цена из разметки страницы берётся
    /// без модели: магазины кладут её для поисковиков точно. Это сокращение
    /// пути, а не граница функции — любая другая цель идёт через модель.
    static func wantsPrice(_ target: String) -> Bool {
        let lower = target.lowercased()
        return ["цен", "стоим", "price", "cost", "价"].contains { lower.contains($0) }
    }
}

struct WatchChange: Equatable {
    let old: WatchReading?
    let new: WatchReading

    /// «12 990 ₽ → 11 490 ₽».
    var text: String {
        guard let old else { return new.text }
        return "\(old.text) → \(new.text)"
    }
}

/// Стоит ли сообщать.
enum WatchRule {
    static func evaluate(
        previous: WatchReading?, current: WatchReading,
        condition: WatchCondition, threshold: Double?
    ) -> WatchChange? {
        guard let previous else {
            // Первая проверка ставит точку отсчёта и молчит — кроме порога:
            // цена, уже ниже заданного, — ровно то, чего ждали.
            if let threshold, let number = current.number,
               (condition == .below && number < threshold) || (condition == .above && number > threshold) {
                return WatchChange(old: nil, new: current)
            }
            return nil
        }
        let change = WatchChange(old: previous, new: current)
        switch condition {
        case .anyChange:
            if let old = previous.number, let new = current.number { return old != new ? change : nil }
            return normalized(previous.text) != normalized(current.text) ? change : nil
        case .decrease:
            guard let old = previous.number, let new = current.number else { return nil }
            return new < old ? change : nil
        case .increase:
            guard let old = previous.number, let new = current.number else { return nil }
            return new > old ? change : nil
        case .below:
            // Сообщаем, когда цена **пересекла** порог, а не на каждой
            // проверке, пока она ниже: иначе уведомление приходило бы
            // каждые пятнадцать минут.
            guard let threshold, let new = current.number, new < threshold else { return nil }
            guard let old = previous.number else { return change }
            return old >= threshold ? change : nil
        case .above:
            guard let threshold, let new = current.number, new > threshold else { return nil }
            guard let old = previous.number else { return change }
            return old <= threshold ? change : nil
        }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}

enum WatchSchedule {
    /// Минутный тик приходит не ровно в срок, и без запаса проверка
    /// «раз в час» съезжала бы на минуту каждый час.
    static let slack: TimeInterval = 45

    static func isDue(now: Date, checkedAt: Date?, interval: WatchInterval) -> Bool {
        guard let checkedAt else { return true }
        if checkedAt > now { return true }
        return now.timeIntervalSince(checkedAt) >= interval.seconds - slack
    }
}
