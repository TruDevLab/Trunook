import AppKit
import Foundation
import TrunookXPC

/// Скачивает образ Ollama, сверяет подпись и переносит приложение
/// в «Программы».
///
/// Сделано по образцу обновления самого Trunook — `UpdateService`, —
/// и отличий от него три, каждое по делу:
///
/// 1. Подпись сверяется не с нашей, а с названной: у Ollama чужой
///    Developer ID (`OllamaApp.requirement`).
/// 2. Образ **не отмонтируется**, если перенести не удалось: человеку
///    показывают открытое окно Finder, чтобы он перетащил приложение сам.
///    Пароля мы не просим никогда.
/// 3. Ставим не себя, а чужое приложение, и оно останется на машине,
///    даже если Trunook удалить. Поэтому об установке говорится прямо.
final class OllamaDownload: NSObject {
    /// Куда складывается образ на время работы.
    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Trunook/Engine", isDirectory: true)
    }

    static var imageFile: URL { folder.appendingPathComponent("Ollama.dmg") }

    /// Куда ставим. Только «Программы»: второе место, где может лежать
    /// Ollama, превратило бы каждое дальнейшее опознание в вопрос с двумя
    /// ответами.
    static let applications = URL(fileURLWithPath: "/Applications")

    private let onState: (OllamaState) -> Void
    private let onInstalled: (URL) -> Void

    private var session: URLSession?
    private var expected: Int64 = 0
    private var shown = -1
    /// Смонтированный образ: держим, чтобы отмонтировать — или **не**
    /// отмонтировать, если человеку ещё предстоит перетащить из него.
    private var mounted: MountedImage?

    /// - Parameters:
    ///   - onState: куда сообщать о ходе работы.
    ///   - onInstalled: куда отдать готовый бандл. Зовётся один раз.
    init(onState: @escaping (OllamaState) -> Void, onInstalled: @escaping (URL) -> Void) {
        self.onState = onState
        self.onInstalled = onInstalled
        super.init()
    }

    // MARK: - Загрузка

    func start() {
        onState(.downloading(0))
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)

        measure { [weak self] size in
            guard let self else { return }
            expected = size
            guard Self.hasRoom(for: size) else {
                DebugLog.write("движок: места мало под образ \(size) Б")
                onState(.failed(.noSpace))
                return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 300
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: OllamaApp.imageURL).resume()
        }
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
        detach()
    }

    /// Спрашивает размер образа заголовком.
    ///
    /// Ошибка не смертельна: без размера полоса пойдёт по тому, что
    /// присылает сервер, а проверка места просто пропустится — так же
    /// устроено и в обновлении.
    private func measure(then done: @escaping (Int64) -> Void) {
        var request = URLRequest(url: OllamaApp.imageURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let size = Self.size(of: response)
            DispatchQueue.main.async { done(size) }
        }.resume()
    }

    /// Размер из заголовков ответа. Чистая — под тестом.
    static func size(of response: URLResponse?) -> Int64 {
        guard let http = response as? HTTPURLResponse else { return 0 }
        if let raw = http.value(forHTTPHeaderField: "Content-Length"), let size = Int64(raw) {
            return size
        }
        return max(0, http.expectedContentLength)
    }

    /// Места нужно втрое: образ, развёрнутое приложение и запас.
    ///
    /// Считается на домашнем томе: сразу после движка туда лягут слои
    /// моделей в `~/.ollama/models`, и места должно хватить и на них.
    static func hasRoom(for size: Int64) -> Bool {
        guard size > 0 else { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return true }
        return Int64(free) > size * 3
    }

    // MARK: - Образ

    /// Монтирует, сверяет подпись, переносит.
    private func settle(image: URL) {
        onState(.verifying)

        guard let volume = DiskImage.attach(image) else {
            DebugLog.write("движок: образ не смонтировался")
            onState(.failed(.damaged))
            return
        }
        mounted = volume

        guard let app = DiskImage.application(in: volume.mountPoint) else {
            onState(.failed(.damaged))
            detach()
            return
        }

        // Подпись — у того бандла, который сейчас и будет скопирован.
        // Проверить одно, а поставить другое значит не проверить ничего.
        let verdict = CodeSignatureCheck.matches(app, requirement: OllamaApp.requirement)
        if case let .rejected(reason) = verdict {
            DebugLog.write("движок: подпись Ollama не сошлась")
            onState(.failed(Self.failure(for: reason)))
            // Образ оставляем смонтированным: путь руками — единственный,
            // что здесь остаётся, и окно Finder человеку пригодится.
            reveal(app)
            return
        }

        copy(app)
    }

    /// Чем наша причина отказа зовётся на языке движка.
    static func failure(for reason: UpdateFailure) -> OllamaFailure {
        switch reason {
        case .unsigned: return .unsigned
        case .wrongCertificate: return .wrongIdentity
        default: return .damaged
        }
    }

    private func copy(_ app: URL) {
        onState(.copying)
        let target = Self.applications.appendingPathComponent(app.lastPathComponent)

        // Право на запись — не предсказание, а попытка: `isWritableFile`
        // отвечает «да» там, где копирование потом отказывает.
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: app, to: target)
        } catch {
            DebugLog.write("движок: в «Программы» не легло — \(error.localizedDescription)")
            // Пароля не просим никогда: установщик от root — ровно тот
            // механизм, который превращает самоподписанное приложение
            // в лазейку для повышения прав.
            onState(.failed(.notWritable))
            reveal(app)
            return
        }

        DebugLog.write("движок: Ollama легла в \(target.path)")
        detach()
        try? FileManager.default.removeItem(at: Self.imageFile)
        onInstalled(target)
    }

    /// Показывает приложение на образе в Finder: дальше человек сам.
    private func reveal(_ app: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([app])
    }

    /// Отмонтирует образ, если он ещё висит. Оставленный том — не просто
    /// мусор: следующая попытка налетит на него.
    func detach() {
        guard let volume = mounted else { return }
        DiskImage.detach(volume)
        mounted = nil
    }
}

extension OllamaDownload: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : Double(expected)
        guard total > 0 else { return }
        let share = min(1, Double(totalBytesWritten) / total)
        // Раз в процент: иначе состояние меняется сотни раз в секунду,
        // и вёрстка перерисовывается вместо того, чтобы качать.
        let percent = Int(share * 100)
        guard percent != shown else { return }
        shown = percent
        DispatchQueue.main.async { [weak self] in self?.onState(.downloading(share)) }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Временный файл система уносит сразу по возвращении из этого
        // метода — переносим его себе прежде всего прочего.
        let image = Self.imageFile
        try? FileManager.default.removeItem(at: image)
        do {
            try FileManager.default.moveItem(at: location, to: image)
        } catch {
            DebugLog.write("движок: скачанное не перенеслось — \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in self?.onState(.failed(.damaged)) }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.settle(image: image) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        // Отмену человек сделал сам — это не отказ, и говорить о ней нечего.
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        DebugLog.write("движок: образ не скачался — \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in self?.onState(.failed(.network)) }
    }
}
