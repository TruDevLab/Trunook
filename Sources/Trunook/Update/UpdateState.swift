import Foundation

/// Чем занято обновление прямо сейчас.
///
/// Состояние нигде не сохраняется: оно целиком выводится из настроек и того,
/// что лежит в папке обновления. Хранить его значило бы завести второй источник
/// правды, который однажды разойдётся с первым.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    /// Версия найдена, загрузка ещё не началась. Живёт мгновения: загрузка
    /// начинается сама.
    case found(GitHubRelease)
    case downloading(GitHubRelease, progress: Double)
    /// Скачано, сумма сошлась, подпись проверена. Путь — к готовому бандлу.
    case ready(GitHubRelease, staged: URL)
    case installing
    case failed(UpdateFailure)
}

/// Почему не вышло.
///
/// Отдельным перечислением, а не строкой: причина нужна не только человеку,
/// но и коду — от неё зависит, можно ли пробовать снова и что предлагать.
enum UpdateFailure: Equatable {
    case network
    /// Лимит GitHub исчерпан. Отдельно от сети: это не поломка, а «позже».
    case rateLimited
    case badResponse
    case checksumMismatch
    case unsigned
    /// Подписано другим сертификатом. Однажды случится законно — когда
    /// сертификат перевыпустят, — и тогда обновляться придётся руками.
    case wrongCertificate
    case damaged
    case notWritable
    /// Приложение работает не из папки программ, а с образа или из карантина
    /// переноса. Подменять там нечего.
    case notInstalled
    case noSpace
    case installFailed

    var message: String {
        switch self {
        case .network: return t("Не удалось связаться с GitHub")
        case .rateLimited: return t("Слишком много проверок, попробуйте позже")
        case .badResponse: return t("Ответ GitHub не разобран")
        case .checksumMismatch: return t("Контрольная сумма не сошлась")
        case .unsigned: return t("Скачанное приложение не подписано")
        case .wrongCertificate: return t("Обновление подписано другим сертификатом")
        case .damaged: return t("Скачанное приложение повреждено")
        case .notWritable: return t("Нет прав на запись в папку приложения")
        case .notInstalled: return t("Перетащите Trunook в «Программы»")
        case .noSpace: return t("Не хватает места на диске")
        case .installFailed: return t("Установка не удалась")
        }
    }
}

/// Строка состояния и кнопка рядом с ней в настройках.
struct UpdateStatusLine: Equatable {
    enum Action: Equatable {
        case check
        case install
        /// Кнопка на месте, но выключена: идёт работа.
        case busy
    }

    let text: String
    let action: Action
}

/// Что показать в настройках при каждом состоянии.
///
/// Одной функцией, потому что текст и подпись кнопки обязаны сходиться:
/// «Готово к установке» с кнопкой «Проверить» — это не опечатка, а обещание,
/// которого приложение не выполнит.
enum UpdateStatusText {
    static func line(for state: UpdateState) -> UpdateStatusLine {
        switch state {
        case .idle:
            return UpdateStatusLine(text: "", action: .check)
        case .checking, .found:
            return UpdateStatusLine(text: t("Проверяем…"), action: .busy)
        case .upToDate:
            return UpdateStatusLine(text: t("Версия последняя"), action: .check)
        case let .downloading(_, progress):
            let percent = Int((progress * 100).rounded())
            return UpdateStatusLine(text: tf("Загрузка %d %%", percent), action: .busy)
        case let .ready(release, _):
            return UpdateStatusLine(
                text: tf("Готово к установке %@", release.version.text),
                action: .install
            )
        case .installing:
            return UpdateStatusLine(text: t("Устанавливаем…"), action: .busy)
        case let .failed(reason):
            return UpdateStatusLine(text: reason.message, action: .check)
        }
    }
}
