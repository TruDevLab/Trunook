import Foundation

/// Когда пора спрашивать GitHub о новой версии.
///
/// Вынесено из службы отдельной чистой функцией: расписание — это ровно то,
/// что ломается тихо и надолго, а проверить его живьём можно только прождав
/// сутки.
enum UpdateSchedule {
    /// Раз в сутки. Чаще незачем: выпуски выходят не ежечасно, а лимит
    /// GitHub без ключа — 60 запросов в час на адрес.
    static let interval: TimeInterval = 24 * 60 * 60

    /// Пора ли идти в сеть.
    ///
    /// - Parameters:
    ///   - manual: человек нажал «Проверить». Такая проверка идёт всегда,
    ///     в том числе при выключенной автопроверке: иначе у кнопки нет смысла.
    static func shouldCheck(now: Date, last: Date?, enabled: Bool, manual: Bool) -> Bool {
        if manual { return true }
        guard enabled else { return false }
        guard let last else { return true }
        // Дата из будущего означает, что часы перевели назад или сменили пояс.
        // Без этой ветки проверка залипла бы до тех пор, пока будущее
        // не наступит, — то есть на месяцы.
        if last > now { return true }
        return now.timeIntervalSince(last) >= interval
    }
}
