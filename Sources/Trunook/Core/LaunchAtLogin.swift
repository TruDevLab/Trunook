import TrunookXPC
import Foundation
import ServiceManagement

/// Автозапуск через `SMAppService`.
///
/// Источник истины ровно один — сама система: пользователь может отключить
/// автозапуск в Системных настройках, минуя наше окно. Поэтому значение
/// не дублируется в UserDefaults, а каждый раз читается из `SMAppService`.
///
/// Регистрация привязана к подписи приложения, поэтому переживает
/// пересборку — по той же причине, что и разрешения TCC.
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    private init() {}

    var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            apply(newValue)
        }
    }

    /// Система могла изменить состояние за нашей спиной — например,
    /// пользователь снял галочку в Системных настройках.
    func refresh() {
        objectWillChange.send()
    }

    private func apply(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                // Повторная регистрация уже включённой службы бросает ошибку.
                guard service.status != .enabled else { return }
                try service.register()
            } else {
                guard service.status == .enabled else { return }
                try service.unregister()
            }
        } catch {
            DebugLog.write("автозапуск: не удалось \(enabled ? "включить" : "выключить") — \(error.localizedDescription)")
        }
    }
}
