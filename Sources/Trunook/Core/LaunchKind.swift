import Foundation

/// Чем оказался этот запуск: первым вообще, первым после обновления
/// или обычным.
///
/// Отдельным типом и чистой функцией, а не парой проверок в `AppDelegate`:
/// от ответа зависит и конфетти, и то, чем откроется окно знакомства, —
/// а проверить руками «поставь старую версию, обнови, посмотри» стоит
/// целого прогона установки.
enum LaunchKind: Equatable {
    /// Приложение запускают впервые. Знакомство откроется само, конфетти нет:
    /// человеку ещё нечего праздновать, он даже не видел, что обновилось.
    case firstEver
    /// Версия сменилась на большую. Строка — прежний номер; `nil` значит,
    /// что прежняя версия его не записала.
    case afterUpdate(from: String?)
    case ordinary

    /// `hasSeenWelcome` нужен ради одного случая, который случится ровно раз
    /// у каждого: версия, поставившая это приложение, номер запуска ещё
    /// не записывала. Пустая запись у человека, знакомство уже прошедшего, —
    /// это не первый запуск, а обновление с той самой версии.
    static func resolve(
        current: String,
        lastRun: String?,
        hasSeenWelcome: Bool
    ) -> LaunchKind {
        guard let lastRun, !lastRun.isEmpty else {
            return hasSeenWelcome ? .afterUpdate(from: nil) : .firstEver
        }
        if lastRun == current { return .ordinary }
        // Откат на прежнюю версию — не повод для конфетти: нового в ней нет.
        // Неразобранный номер туда же: гадать, обновление это или порча
        // настроек, дешевле отказом.
        guard let now = AppVersion(current),
              let before = AppVersion(lastRun),
              before < now
        else { return .ordinary }
        return .afterUpdate(from: lastRun)
    }
}
