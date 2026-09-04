import Foundation

/// Описание одного выпуска — то, что человек читает на странице релиза.
///
/// Отдельно от `GitHubRelease`, хотя приходят они из одного места. Причина
/// в требованиях: `GitHubRelease` отбрасывает выпуск без образа `.dmg`,
/// потому что ставить оттуда нечего. Описанию образ не нужен вовсе —
/// выпуск без него всё равно рассказывает, что изменилось. Один тип на двоих
/// значил бы, что одна из двух задач молча теряет часть своих данных.
struct ReleaseNote: Equatable, Identifiable {
    /// Имя тега как есть, с ведущей «v». Оно же опознаёт выпуск в списке.
    let tag: String
    let version: AppVersion
    /// Заголовок выпуска. У наших он совпадает с тегом, но GitHub позволяет
    /// свой — берём его, когда он есть.
    let title: String
    let publishedAt: Date?
    /// Описание в Markdown, как оно написано на странице выпуска.
    let body: String
    let pageURL: URL?

    var id: String { tag }

    /// Разбирает ответ `/repos/:owner/:repo/releases`.
    ///
    /// Разбор отделён от сети нарочно — тем же приёмом, что у `GitHubRelease`
    /// и `WeatherService`: его проверяет тест на записанном ответе, а не
    /// живой запрос.
    ///
    /// Порядок GitHub обещает по дате, но опираться на чужое обещание там,
    /// где от порядка зависит выбор по умолчанию, незачем: сортируем сами
    /// по версии, от новых к старым.
    static func parseList(_ data: Data) -> [ReleaseNote] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return root.compactMap(parse(object:)).sorted { $0.version > $1.version }
    }

    static func parse(object: [String: Any]) -> ReleaseNote? {
        guard let tag = object["tag_name"] as? String,
              let version = AppVersion(tag)
        else { return nil }
        // Черновик человеку не показывают: он ещё не выпуск. Предрелиз тоже —
        // приложение их не ставит, и описание к неустановимому только путает.
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true { return nil }

        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReleaseNote(
            tag: tag,
            version: version,
            title: (name?.isEmpty == false ? name : nil) ?? tag,
            publishedAt: (object["published_at"] as? String).flatMap(date(from:)),
            body: (object["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: (object["html_url"] as? String).flatMap(URL.init(string:))
        )
    }

    /// «2026-08-31T12:04:11Z». Свой разборщик, а не `ISO8601DateFormatter()`
    /// по месту: тот дорог в создании, а список выпусков разбирается целиком
    /// за один заход.
    private static let isoFormatter = ISO8601DateFormatter()

    private static func date(from text: String) -> Date? {
        isoFormatter.date(from: text)
    }
}
