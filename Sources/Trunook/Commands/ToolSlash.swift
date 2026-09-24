import SwiftUI

/// Инструмент, выбранный человеком через «/».
///
/// Не сам `AgentTool`, а группа: инструментов тринадцать, и выбирать из них
/// «создать встречу», «перенести встречу», «отменить встречу» человеку
/// незачем — он знает, о чём спрашивает, а не каким вызовом это делается.
/// Группы названы по функциям приложения: «Календарь», «Заметки»,
/// «Настройки».
struct SlashTool: PickerRow {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    /// Что достанется модели, когда выбрана эта группа. Остального она
    /// не увидит вовсе — в этом весь смысл выбора.
    let tools: [AgentTool]

    /// Подпись читается фразой слева направо, а не датой: резать её надо
    /// с конца.
    var truncatesDetailFromHead: Bool { false }

    /// Как группа зовётся в тексте вопроса: «/настройки».
    ///
    /// Строчными и одним словом: слово с пробелом разорвало бы и разбор,
    /// и сам вопрос. Поэтому названия групп короткие — «Календарь»,
    /// а не «Календарь и задачи».
    var token: String { "/" + title.lowercased() }
}

/// Какие группы доступны прямо сейчас.
enum SlashCatalogue {
    /// Порядок — от того, о чём спрашивают чаще, к редкому.
    ///
    /// Настройки первыми: это единственная группа, которая отвечает
    /// о самом приложении, и до неё модель сама доходит хуже всего —
    /// про Trunook она охотно отвечает из головы.
    static func all(for settings: Settings) -> [SlashTool] {
        let groups: [SlashTool] = [
            SlashTool(
                id: "settings",
                title: t("Настройки"),
                detail: t("о приложении и настройках"),
                symbol: "questionmark.circle",
                tint: Palette.neutral,
                tools: [.appHelp]
            ),
            SlashTool(
                id: "calendar",
                title: t("Календарь"),
                detail: t("встречи и дела дня"),
                symbol: "calendar",
                tint: Palette.calendar,
                tools: [.upcoming, .dayAgenda, .createEvent, .moveEvent, .cancelEvent]
            ),
            SlashTool(
                id: "mail",
                title: t("Почта"),
                detail: t("письма в Trudaybook"),
                symbol: "envelope",
                tint: Palette.blue,
                tools: AgentTool.mail
            ),
            SlashTool(
                id: "notes",
                title: t("Заметки"),
                detail: t("поиск и новая заметка"),
                symbol: "note.text",
                tint: Palette.notes,
                tools: [.searchNotes, .createNote]
            ),
            SlashTool(
                id: "reminders",
                title: t("Напоминания"),
                detail: t("завести напоминание"),
                symbol: "checklist",
                tint: Palette.calendar,
                tools: [.createReminder]
            ),
            SlashTool(
                id: "timer",
                title: t("Таймер"),
                detail: t("таймер и секундомер"),
                symbol: "timer",
                tint: Palette.timer,
                tools: [.startTimer, .stopTimer, .startStopwatch]
            ),
            SlashTool(
                id: "weather",
                title: t("Погода"),
                detail: t("что за окном"),
                symbol: "cloud.sun",
                tint: Palette.weather,
                tools: [.weatherNow]
            ),
        ]

        // Группа жива, пока жив хоть один её инструмент. Выключенную функцию
        // предлагать нельзя: человек выбрал бы её и получил в ответ
        // «календарь выключен в настройках» — то есть отказ вместо ответа.
        return groups.compactMap { group in
            let alive = group.tools.filter { $0.isEnabled(settings) }
            guard !alive.isEmpty else { return nil }
            return SlashTool(
                id: group.id, title: group.title, detail: group.detail,
                symbol: group.symbol, tint: group.tint, tools: alive
            )
        }
    }
}

/// Разбор «/» в наборе: где он, что после него и чем это заменить.
///
/// Устроено по образцу `MentionQuery` и с той же целью: правило одно
/// и то же нужно вёрстке, контроллеру и отправке. Разойдись они — список
/// показывался бы на одном, а выбор срабатывал бы на другом.
///
/// Разница с «@» одна, и она важная: «/» считается за начало выбора
/// **только в самом начале вопроса**. Косая черта попадается и в датах,
/// и в путях, и в адресах, а выбирать инструмент посреди фразы незачем —
/// он относится ко всему вопросу целиком.
enum SlashQuery {
    /// Наибольшая длина запроса. Дальше это уже не поиск, а обычный текст,
    /// начавшийся с косой черты.
    static let maxLength = 24

    /// Что набрано после «/» — если это ещё запрос.
    static func range(in text: String) -> Range<String.Index>? {
        guard text.hasPrefix("/") else { return nil }
        let query = text.dropFirst()
        guard query.count <= maxLength else { return nil }
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return text.startIndex..<text.endIndex
    }

    /// Сам запрос, без «/». Пустая строка — «/» только что набрали:
    /// список показывается целиком, это и есть его открытие.
    static func query(in text: String) -> String? {
        guard let range = range(in: text) else { return nil }
        return String(text[text.index(after: range.lowerBound)..<range.upperBound])
    }

    /// Подставляет выбранное вместо набранного запроса.
    ///
    /// Пробел в конце обязателен: без него вопрос прилип бы к названию,
    /// а сам «/настройки» остался бы запросом — список висел бы над уже
    /// сделанным выбором.
    static func insert(_ tool: SlashTool, into text: String) -> String {
        let replacement = tool.token + " "
        guard let range = range(in: text) else { return replacement + text }
        return text.replacingCharacters(in: range, with: replacement)
    }

    /// Кого показать под запросом. Совпадение с начала названия — выше
    /// совпадения в середине, как и у «@».
    static func matches(_ all: [SlashTool], query: String, limit: Int) -> [SlashTool] {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !needle.isEmpty else { return Array(all.prefix(limit)) }

        var leading: [SlashTool] = []
        var inside: [SlashTool] = []
        for tool in all {
            let hay = tool.title
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if hay.hasPrefix(needle) {
                leading.append(tool)
            } else if hay.contains(needle) {
                inside.append(tool)
            }
        }
        return Array((leading + inside).prefix(limit))
    }

    /// Что выбрано в уже набранном вопросе и что от вопроса осталось.
    ///
    /// Разбирается сам текст, а не запомненный выбор, — по той же причине,
    /// по какой «@» пересматривается перед отправкой: человек стирает
    /// набранное, и уходить модели должно ровно то, что написано. Стёр
    /// «/настройки» — значит, никакого выбора и не было.
    ///
    /// Сам ярлык из вопроса убирается: это указание приложению, а не часть
    /// вопроса, и модели он сказал бы только то, что человек набрал косую
    /// черту.
    static func chosen(in text: String, from all: [SlashTool]) -> (tool: SlashTool, question: String)? {
        guard text.hasPrefix("/") else { return nil }
        let head = text.prefix { !$0.isWhitespace && !$0.isNewline }.lowercased()
        guard let tool = all.first(where: { $0.token == head }) else { return nil }
        let rest = text.dropFirst(head.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return (tool, rest)
    }

    /// Что модель узнает о выборе.
    ///
    /// Инструментов ей и так достанется ровно столько, сколько в группе, —
    /// но сказать словами всё равно нужно: с одним инструментом в списке
    /// маленькая модель нет-нет да и отвечает из головы, не позвав его.
    static func instruction(for tool: SlashTool) -> String {
        tf("Человек выбрал: %@. Ответь, взяв для этого инструмент из доступных, а не из собственной памяти.",
           tool.title)
    }
}
