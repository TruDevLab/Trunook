import SwiftUI

/// Что позвали в вопрос по «@»: встреча из календаря или заметка.
///
/// Значение, а не ссылка на живой объект. Список встреч перечитывается
/// на каждое движение календаря, а заметка может уехать в Obsidian — но
/// вопрос, который человек уже набрал, обязан остаться про то, на что
/// он показал.
///
/// Ярлык (`handle`) — короткое латинское имя вроде `e1`: его и видит модель.
/// Настоящий идентификатор события в EventKit — строка в тридцать с лишним
/// знаков, и маленькая модель, переписывая её в аргумент, ошибается
/// на каждом втором вызове.
struct Mention: Identifiable, Equatable {
    enum Kind: Equatable {
        case event
        case note
    }

    let kind: Kind
    /// Как эта запись зовётся для модели: `e1`, `n2`.
    let handle: String
    /// Чем её найти на самом деле: идентификатор события или номер заметки.
    let target: String
    /// Когда вхождение начинается. Только у встречи и только для того,
    /// чтобы найти в хранилище **именно её**: у всех вхождений
    /// повторяющегося события один и тот же идентификатор.
    let start: Date?
    let title: String
    /// Вторая строка: «завтра, 10:00» у встречи, «12 сент» у заметки.
    let detail: String

    var id: String { handle }

    var symbol: String {
        switch kind {
        case .event: return "calendar"
        case .note: return "note.text"
        }
    }

    var tint: Color {
        switch kind {
        case .event: return Palette.calendar
        case .note: return Palette.notes
        }
    }

    /// Как запись зовут в тексте вопроса: «@Планёрка».
    var token: String { "@" + title }
}

/// Разбор «@» в наборе: где он, что после него и чем это заменить.
///
/// Отдельным типом и чистыми функциями: правило одно и то же нужно
/// и вёрстке (показывать ли список), и контроллеру (чем заменить набранное),
/// и проверке. Разойдись они — список показывался бы на одном, а подстановка
/// срабатывала бы на другом.
enum MentionQuery {
    /// Наибольшая длина запроса. Дальше это уже не поиск, а обычный текст,
    /// в котором просто попалась собака.
    static let maxLength = 40

    /// Что набрано после последней «@» — если это ещё запрос.
    ///
    /// Запросом считается только хвост набранного: список стоит под полем
    /// и отвечает на то, что печатают **сейчас**. Каретку от `NSTextView`
    /// сюда не тянем — она потребовала бы держать её в состоянии панели
    /// и обновлять на каждое нажатие стрелки.
    ///
    /// Три условия, и каждое отсекает свой ложный случай: «@» стоит
    /// в начале слова (иначе сработала бы всякая почта), после неё нет
    /// пробелов (иначе список висел бы над готовым «@Планёрка отмени»)
    /// и запрос короткий (иначе им становился бы любой длинный хвост).
    static func range(in text: String) -> Range<String.Index>? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at > text.startIndex {
            let before = text[text.index(before: at)]
            guard before.isWhitespace || before.isNewline else { return nil }
        }
        let query = text[text.index(after: at)...]
        guard query.count <= maxLength else { return nil }
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return at..<text.endIndex
    }

    /// Сам запрос, без «@». Пустая строка — «@» только что набрали:
    /// список показывается целиком, это и есть его открытие.
    static func query(in text: String) -> String? {
        guard let range = range(in: text) else { return nil }
        return String(text[text.index(after: range.lowerBound)..<range.upperBound])
    }

    /// Подставляет выбранное вместо набранного запроса.
    ///
    /// Пробел в конце обязателен: без него следующее слово прилипло бы
    /// к названию, а сам «@Планёрка» остался бы запросом — список висел бы
    /// над уже сделанным выбором.
    static func insert(_ mention: Mention, into text: String) -> String {
        let replacement = mention.token + " "
        guard let range = range(in: text) else { return text + replacement }
        return text.replacingCharacters(in: range, with: replacement)
    }

    /// Кого показать под запросом.
    ///
    /// Совпадение с начала названия — выше совпадения в середине: набирая
    /// «пл», человек метит в «Планёрку», а не в «Разбор плана». Регистр
    /// и буква ё не считаются: искать по названию, набранному кем-то другим,
    /// иначе не выйдет.
    static func matches(_ all: [Mention], query: String, limit: Int) -> [Mention] {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !needle.isEmpty else { return Array(all.prefix(limit)) }

        var leading: [Mention] = []
        var inside: [Mention] = []
        for mention in all {
            let hay = mention.title
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if hay.hasPrefix(needle) {
                leading.append(mention)
            } else if hay.contains(needle) {
                inside.append(mention)
            }
        }
        return Array((leading + inside).prefix(limit))
    }

    /// Кто из позванных ещё жив в тексте.
    ///
    /// Человек стирает набранное, а список позванных сам по себе не пустеет.
    /// Уходя модели, вопрос обязан нести ровно то, что в нём написано:
    /// иначе она отменит встречу, упоминание о которой стёрли.
    static func surviving(_ mentions: [Mention], in text: String) -> [Mention] {
        mentions.filter { text.contains($0.token) }
    }
}
