import TrunookXPC
import Foundation

/// Сведения о сборке и перенос настроек с прежнего имени приложения.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Trunook"
    }

    /// Версия для показа пользователю, например «0.1.0 (2608111447)».
    ///
    /// Разбирать эту строку обратно нельзя — она склеена для глаз. Для сравнения
    /// с выпуском есть `current`.
    static var version: String {
        "\(shortVersion) (\(build))"
    }

    /// Только маркетинговый номер: «0.11.1». По нему и сравниваются выпуски.
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Номер сборки из даты, например «2608301645».
    ///
    /// В сравнении версий не участвует: он про машину сборки, а не про выпуск.
    /// Нужен, чтобы две сборки одного номера различались в журнале.
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// Своя версия в сравнимом виде. `nil` — в бандле её нет, а значит
    /// обновляться не от чего: сравнивать не с чем.
    static var current: AppVersion? {
        AppVersion(shortVersion)
    }

    /// Прежний идентификатор приложения — до переименования в Trunook.
    private static let previousBundleID = "com.nook.Nook"

    /// Переносит настройки со старого имени.
    ///
    /// Переименование меняет домен UserDefaults, и без переноса пользователь
    /// нашёл бы пустые настройки и потерял бы заполненные слоты команд.
    /// Выполняется один раз: отметка о переносе живёт в новом домене.
    static func migrateSettingsIfNeeded(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "didMigrateFromNook") else { return }
        defer { defaults.set(true, forKey: "didMigrateFromNook") }

        guard let old = UserDefaults(suiteName: previousBundleID),
              let values = old.persistentDomain(forName: previousBundleID),
              !values.isEmpty
        else { return }

        var moved = 0
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            moved += 1
        }
        DebugLog.write("перенос настроек с прежнего имени: ключей — \(moved)")
    }
}
