import Foundation

/// Диагностика в файл `~/Library/Logs/Trunook.log`.
///
/// Живёт в общем слое, потому что нужна и XPC-хелперу: без его журнала
/// не понять, доходят ли до него уведомления MediaRemote. Каждый процесс
/// пишет в свой файл — общий пришлось бы защищать от чередования строк.
///
/// Unified log на этой системе не отдаёт записи уровня info обратно через
/// `log show`, а во время отладки оверлея нужен способ увидеть состояние
/// приложения, не переключая фокус на терминал. Включается переменной
/// окружения `NOOK_DEBUG=1` либо файлом-маркером `~/Library/Logs/Trunook.debug`.
public enum DebugLog {
    private static let queue = DispatchQueue(label: "com.trunook.debuglog")

    private static let url: URL? = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        let enabled = ProcessInfo.processInfo.environment["NOOK_DEBUG"] == "1"
            || FileManager.default.fileExists(atPath: logs.appendingPathComponent("Trunook.debug").path)
        guard enabled else { return nil }
        // Имя файла по процессу: приложение и хелпер пишут раздельно.
        let name = ProcessInfo.processInfo.processName
        return logs.appendingPathComponent("\(name).log")
    }()

    public static var isEnabled: Bool { url != nil }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public static func write(_ message: String) {
        guard let url else { return }
        queue.async {
            let line = "\(formatter.string(from: Date()))  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
