import TrunookXPC
import Foundation

/// Сведения о сборке и перенос настроек с прежнего имени приложения.
enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Trunook"
    }

    /// Версия для показа пользователю, например «0.1.0 (2608111447)».
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
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
