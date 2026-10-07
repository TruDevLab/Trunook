import TrunookXPC
import Foundation

/// Сон по закрытой крышке — `pmset disablesleep`.
///
/// Ассерции IOKit, которыми держит экран `WakeGuard`, крышку не отменяют:
/// закрыли — Mac засыпает, что бы ни просило приложение. Исключение —
/// режим закрытой крышки с внешним монитором и зарядкой, его macOS держит
/// сама. Без монитора остаётся только `pmset -a disablesleep 1`, а это
/// системная настройка: её меняют с паролем администратора, и спрашивает
/// его сама macOS своим окном — пароль приложение не видит.
///
/// Включение и выключение спрашивают пароль каждый раз, нарочно: постоянное
/// правило «без пароля» — это навсегда открытая дверь к системной настройке.
/// Что включили мы, помнит `armedKey`: упал Trunook с выключенным сном —
/// при следующем запуске он вернёт его.
enum LidSleep {
    static let armedKey = "caffeineLidArmed"

    /// Выключен ли сейчас сон (`SleepDisabled 1` в `pmset -g`).
    static func isDisabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseDisabled(String(decoding: data, as: UTF8.self))
    }

    /// Строка `SleepDisabled\t\t1` из вывода `pmset -g`.
    static func parseDisabled(_ output: String) -> Bool {
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return false
    }

    /// Команда для `do shell script` — только две, без подстановок.
    static func script(disabled: Bool) -> String {
        "do shell script \"/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)\" with administrator privileges"
    }

    /// Поменять, спросив пароль. Окно пароля держит поток, поэтому — не на
    /// главном; ответ — на главном. `false` — отказались или не вышло.
    static func set(_ disabled: Bool, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = run(disabled: disabled)
            DispatchQueue.main.async { completion(ok) }
        }
    }

    /// То же, но дожидаясь: при выходе из приложения ждать ответа некому.
    @discardableResult
    static func setNow(_ disabled: Bool) -> Bool { run(disabled: disabled) }

    private static func run(disabled: Bool) -> Bool {
        var error: NSDictionary?
        _ = NSAppleScript(source: script(disabled: disabled))?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("крышка: pmset disablesleep \(disabled ? 1 : 0) — отказ: \(error[NSAppleScript.errorMessage] ?? "?")")
            return false
        }
        DebugLog.write("крышка: pmset disablesleep \(disabled ? 1 : 0)")
        UserDefaults.standard.set(disabled, forKey: armedKey)
        return true
    }

    /// После падения: сон выключили мы и не вернули — вернуть.
    static func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: armedKey) else { return }
        DispatchQueue.global(qos: .utility).async {
            guard isDisabled() else {
                UserDefaults.standard.set(false, forKey: armedKey)
                return
            }
            DebugLog.write("крышка: сон остался выключенным после прошлого запуска — возвращаю")
            _ = run(disabled: false)
        }
    }
}
