import Foundation

/// Что вышло у инструмента.
struct AgentToolResult: Equatable {
    /// Уходит модели ролью `tool`. Это служебный текст: расписание дня
    /// целым куском, погода числами.
    let text: String
    /// Видит человек строкой шага в ленте. Короткое и по-русски.
    let label: String
}

/// Что модель предлагает сделать.
///
/// Значение, а не замыкание: по нему рисуется карточка и считается высота
/// панели, а значит оно обязано быть `Equatable`. Готовая работа лежит
/// в `payload` — разбирать аргументы второй раз, уже после нажатия, значило бы
/// завести второе место, где живёт то же правило.
struct PendingAction: Equatable, Identifiable {
    /// Что именно заведут, уже разобранное и выверенное.
    enum Payload: Equatable {
        case event(EventDraft)
        case reminder(title: String, due: Date?, hasTime: Bool, list: String?)
        case note(title: String?, text: String)
    }

    let id: Int
    let tool: AgentTool
    let call: ToolCall
    let payload: Payload
    /// «Встреча «Созвон»»
    let title: String
    /// «12 сент, сб, 15:00 · 1 ч»
    let detail: String
    /// Подпись кнопки: «Создать», «Напомнить», «Записать».
    let confirm: String
}

/// Что делать с тем, о чём попросила модель.
enum AgentAction {
    /// Смотрит или делает обратимое — сразу, без спроса.
    case run(AgentTool, ToolCall)
    /// Пишет в чужое хранилище — сперва карточка.
    case confirm(PendingAction)
    /// Нельзя: инструмента нет, функция выключена, аргументы не разобраны.
    /// Не молчание, а ответ: модели нужен текст, чтобы внятно объясниться.
    case refuse(AgentToolResult)
}
