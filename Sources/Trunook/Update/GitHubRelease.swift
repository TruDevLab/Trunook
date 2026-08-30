import Foundation

/// Выпуск, найденный на странице релизов GitHub.
///
/// Разбор отделён от сети нарочно: так его проверяет тест на записанном ответе,
/// а не живой запрос. Тот же приём, что у `WeatherService.parse`
/// и `WeatherPlaceSearch.parse`.
struct GitHubRelease: Equatable {
    /// Имя тега как есть, с ведущей «v»: оно нужно для ссылки на страницу.
    let tag: String
    let version: AppVersion
    let assetName: String
    let assetURL: URL
    /// Размер образа в байтах: по нему считается доля загрузки, когда сервер
    /// не прислал `Content-Length`, и проверяется место на диске.
    let assetSize: Int
    /// Контрольная сумма из описания выпуска. `nil` — её там не оказалось,
    /// и это не повод отказываться: сумму переносит рукой человек.
    let checksum: String?
    let pageURL: URL?
    /// Описание выпуска. Показывается не в вырезе, а на странице релиза,
    /// но донести его дешевле, чем ходить за ним второй раз.
    let notes: String

    /// Разбирает ответ `/repos/:owner/:repo/releases/latest`.
    ///
    /// Ассет выбирается по расширению `.dmg`, а не по номеру: порядок ассетов
    /// GitHub не обещает. Образа нет — выпуск негодный, и это не то же самое,
    /// что «выпуска нет».
    static func parse(_ data: Data) -> GitHubRelease? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String,
              let version = AppVersion(tag)
        else { return nil }

        // `/releases/latest` черновики и предрелизы не отдаёт, но проверка стоит
        // две строки, а ошибка здесь означала бы раздачу недоделанного.
        if root["draft"] as? Bool == true || root["prerelease"] as? Bool == true { return nil }

        guard let assets = root["assets"] as? [[String: Any]],
              let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
              let name = asset["name"] as? String,
              let address = asset["browser_download_url"] as? String,
              let url = URL(string: address)
        else { return nil }

        let notes = root["body"] as? String ?? ""
        return GitHubRelease(
            tag: tag,
            version: version,
            assetName: name,
            assetURL: url,
            assetSize: asset["size"] as? Int ?? 0,
            checksum: checksum(inBody: notes),
            pageURL: (root["html_url"] as? String).flatMap(URL.init(string:)),
            notes: notes
        )
    }

    /// Вынимает sha256 из описания выпуска.
    ///
    /// Ищется первое отдельно стоящее слово из 64 шестнадцатеричных знаков,
    /// а не строка `` `shasum -a 256`: ``. Разметка описания живёт в `RELEASE.md`
    /// и однажды изменится, а 64 шестнадцатеричных знака подряд в связном
    /// тексте случайно не встречаются.
    static func checksum(inBody body: String) -> String? {
        body.split(whereSeparator: { !$0.isHexDigit })
            .first { $0.count == 64 }
            .map { $0.lowercased() }
    }
}
