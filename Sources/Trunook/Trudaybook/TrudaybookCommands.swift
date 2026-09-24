import TrunookXPC
import Foundation

/// Просьбы к Trudaybook от помощника: файл с командой в папку Trudaybook,
/// ответ — файлом в нашу.
///
/// Trudaybook исполняет только свой закрытый список: показать неразобранное,
/// открыть письмо, отложить, поставить приоритет, отметить разобранным,
/// открыть черновик ответа. Отправки письма в нём нет — её делает человек
/// в самом Trudaybook.
enum TrudaybookCommands {
    enum Reply {
        case ok([String: Any])
        case failed(String)
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trudaybook/commands", isDirectory: true)
    }

    static var repliesFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trunook/trudaybook-replies", isDirectory: true)
    }

    /// Сколько ждать ответа. Trudaybook отвечает за доли секунды; дольше —
    /// значит, он закрыт или завис, и модели надо сказать об этом, а не ждать.
    static let timeout: TimeInterval = 6

    /// Отправить команду. `completion` — на главной очереди.
    static func send(_ command: [String: Any], completion: @escaping (Reply) -> Void) {
        let id = UUID().uuidString
        let reply = repliesFolder.appendingPathComponent("\(id).json")
        var payload = command
        payload["reply"] = reply.path
        do {
            try FileManager.default.createDirectory(at: repliesFolder, withIntermediateDirectories: true)
            // Папку команд создаёт Trudaybook, когда разрешает их принимать:
            // её нет — значит, и спрашивать некого.
            guard FileManager.default.fileExists(atPath: folder.path) else {
                return completion(.failed(t("Trudaybook не принимает команды: разрешите это в его настройках, раздел «Trunook».")))
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            // Во временный — скрытый, с другим расширением — и перенос:
            // иначе Trudaybook прочитал бы недописанное.
            let temporary = folder.appendingPathComponent(".\(id).tmp")
            try data.write(to: temporary)
            try FileManager.default.moveItem(at: temporary, to: folder.appendingPathComponent("trunook-\(id).json"))
        } catch {
            DebugLog.write("Trudaybook: команда не записана — \(error.localizedDescription)")
            return completion(.failed(t("Не вышло передать просьбу в Trudaybook.")))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(timeout)
            var answer: Reply = .failed(t("Trudaybook не ответил — возможно, он закрыт."))
            while Date() < deadline {
                if let data = try? Data(contentsOf: reply) {
                    try? FileManager.default.removeItem(at: reply)
                    answer = parse(data)
                    break
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            DispatchQueue.main.async { completion(answer) }
        }
    }

    static func parse(_ data: Data) -> Reply {
        guard data.count <= 256 * 1024,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed(t("Ответ Trudaybook не разобрался."))
        }
        if (json["ok"] as? NSNumber)?.boolValue == true { return .ok(json) }
        return .failed(String(((json["error"] as? String) ?? t("Trudaybook не смог это сделать.")).prefix(600)))
    }
}
