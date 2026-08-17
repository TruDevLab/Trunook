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
                try? input.write(to: url, atomically: true, encoding: .utf8)
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

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result0(
            status: process.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            error: String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    enum ShortcutsError: LocalizedError {
        case launchFailed
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .launchFailed: return t("Не удалось запустить «Команды»")
            case let .failed(message): return message
            }
        }
    }
}
