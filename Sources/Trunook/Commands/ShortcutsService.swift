import TrunookXPC
import Foundation

/// Работа с приложением «Команды» через штатный `/usr/bin/shortcuts`.
///
/// Через CLI, а не через URL-схему `shortcuts://run-shortcut`: схема умеет
/// только запустить команду, а CLI ещё и передаёт вход и забирает результат.
final class ShortcutsService: ObservableObject {
    @Published private(set) var names: [String] = []
    @Published private(set) var isLoading = false

    private static let executable = "/usr/bin/shortcuts"
    private let queue = DispatchQueue(label: "com.trunook.shortcuts")

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executable)
    }

    func refresh() {
        guard !isLoading, Self.isAvailable else { return }
        isLoading = true

        queue.async { [weak self] in
            let output = Self.run(arguments: ["list"])?.output ?? ""
            let names = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            DispatchQueue.main.async {
                self?.isLoading = false
                self?.names = names
                DebugLog.write("Команды: найдено — \(names.count)")
            }
        }
    }

    /// Запускает команду. Выделенный текст передаётся как вход, а всё, что
    /// команда вернёт, отдаётся вызывающей стороне.
    static func run(
        name: String,
        input: String?,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var arguments = ["run", name]
            var inputURL: URL?
            let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("nook-shortcut-out-\(UUID().uuidString)")

            if let input, !input.isEmpty {
                let url = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("nook-shortcut-in-\(UUID().uuidString).txt")
                do {
                    try input.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    // Промолчать здесь нельзя. Команда запустилась бы с путём
                    // к несуществующему файлу и отработала не над тем, что
                    // человек выделил, — а выглядело бы это как обычный
                    // её результат.
                    DebugLog.write("Команды: не записать вход — \(error.localizedDescription)")
                    completion(.failure(ShortcutsError.inputFailed))
                    return
                }
                inputURL = url
                arguments += ["--input-path", url.path]
            }
            arguments += ["--output-path", outputURL.path]

            defer {
                inputURL.map { try? FileManager.default.removeItem(at: $0) }
            }

            guard let result = run(arguments: arguments) else {
                completion(.failure(ShortcutsError.launchFailed))
                return
            }

            guard result.status == 0 else {
                let message = result.error.isEmpty ? t("Команда завершилась с ошибкой") : result.error
                completion(.failure(ShortcutsError.failed(message)))
                return
            }

            let produced = try? String(contentsOf: outputURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: outputURL)
            completion(.success(produced?.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    private struct Result0 {
        let status: Int32
        let output: String
        let error: String
    }

    /// Ссылочная коробка под то, что читает соседний поток: локальная
    /// переменная, изменяемая из замыкания, здесь не годится.
    private final class Drain {
        var data = Data()
    }

    private static func run(arguments: [String]) -> Result0? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            DebugLog.write("Команды: не удалось запустить — \(error.localizedDescription)")
            return nil
        }

        // Оба канала дренируются одновременно, а не по очереди. По очереди —
        // классическая форма взаимной блокировки: дочерний процесс, забивший
        // буфер stderr, встаёт на записи и не закрывает stdout, которого мы
        // в это время ждём. У `shortcuts` вероятность мала — килобайтами
        // в stderr он не пишет, — но форма неверная, а цена правки одна
        // фоновая очередь.
        let errors = Drain()
        let draining = DispatchGroup()
        draining.enter()
        DispatchQueue.global(qos: .utility).async {
            errors.data = err.fileHandleForReading.readDataToEndOfFile()
            draining.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        draining.wait()
        process.waitUntilExit()

        return Result0(
            status: process.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errors.data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    enum ShortcutsError: LocalizedError {
        case launchFailed
        case inputFailed
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed: return t("Не удалось запустить «Команды»")
            case .inputFailed: return t("Не удалось передать выделенный текст")
            case let .failed(message): return message
            }
        }
    }
}
