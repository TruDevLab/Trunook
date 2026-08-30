import TrunookXPC
import AppKit
import CryptoKit
import Foundation

/// Проверяет GitHub на новую версию, скачивает её и держит проверенной
/// до нажатия «Обновить».
///
/// Устроена по образцу `WeatherService`: своя недолговечная сессия, таймер
/// в общем режиме цикла, `start()`/`stop()` у владельца. Разбор ответа,
/// расписание и решение об исходе живут отдельными чистыми типами — их
/// проверяет тест, а не живой запрос.
final class UpdateService: NSObject, ObservableObject {
    /// Репозиторий тот же, что в README. Держать его строкой в одном месте:
    /// разойтись с настоящим адресом ему негде.
    static let repository = "TruDevLab/Trunook"

    @Published private(set) var state: UpdateState = .idle

    /// Обновление скачано и проверено. Владелец показывает плашку.
    /// Зовётся один раз на запуск: сообщить — не значит напоминать.
    var onReady: ((GitHubRelease) -> Void)?

    private let settings: Settings
    private let session: URLSession
    private var timer: Timer?
    private var downloadSession: URLSession?
    private var downloading: GitHubRelease?
    private var announced = false

    /// Когда в последний раз пробовали сходить — удачно или нет.
    ///
    /// Живёт в памяти, а не в настройках, и это нарочно: на диске лежит только
    /// удачная проверка. Пара «удача на диске, попытка в памяти» не даёт ни
    /// долбить сеть после каждого пробуждения, ни замолчать на неделю из-за
    /// одной поездки без интернета.
    private var lastAttempt: Date?

    /// Тик таймера — шесть часов, а порог проверки — сутки.
    ///
    /// Суточный таймер съедается сном крышки: агент живёт неделями и дрейфует.
    /// Частый тик просто спрашивает расписание и сам себя выправляет, а лишние
    /// тики бесплатны — их гасит `UpdateSchedule.shouldCheck`.
    private static let tick: TimeInterval = 6 * 60 * 60

    /// Не чаще раза в час, если предыдущая попытка сорвалась.
    private static let retryAfterFailure: TimeInterval = 60 * 60

    init(settings: Settings = .shared) {
        self.settings = settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        super.init()
    }

    // MARK: - Жизнь службы

    func start() {
        UpdateInstaller.cleanLeftovers(near: Bundle.main.bundleURL.resolvingSymlinksInPath())
        restoreStaged()

        // Первый заход не сразу: запуск и так занят разрешениями, календарём
        // и списком моделей.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.check(manual: false)
        }

        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func woke() {
        check(manual: false)
    }

    // MARK: - Проверка

    func check(manual: Bool) {
        let now = Date()
        guard UpdateSchedule.shouldCheck(
            now: now, last: settings.lastUpdateCheck,
            enabled: settings.autoUpdateEnabled, manual: manual
        ) else { return }

        if isBusy { return }
        if !manual, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.retryAfterFailure { return }
        lastAttempt = now

        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            settle(.failed(.badResponse))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Без своего имени GitHub отвечает отказом. Ровно та мелочь, на которой
        // теряют полдня, принимая её за поломку сети.
        request.setValue("Trunook/\(AppInfo.shortVersion)", forHTTPHeaderField: "User-Agent")

        settle(.checking)
        session.dataTask(with: request) { [weak self] data, response, failure in
            guard let self else { return }
            if let failure {
                DebugLog.write("обновление: проверка не удалась — \(failure.localizedDescription)")
                self.settle(.failed(.network))
                return
            }
            self.received(data, response as? HTTPURLResponse)
        }.resume()
    }

    private func received(_ data: Data?, _ response: HTTPURLResponse?) {
        if let response, response.statusCode != 200 {
            // Исчерпанный лимит — не поломка, а «позже», и сказать это надо
            // отдельно: иначе человек будет чинить сеть, с которой всё хорошо.
            let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let limited = response.statusCode == 403 && remaining == "0"
            DebugLog.write("обновление: GitHub ответил \(response.statusCode), запас проверок \(remaining ?? "?")")
            settle(.failed(limited ? .rateLimited : .badResponse))
            return
        }

        guard let data, let release = GitHubRelease.parse(data) else {
            DebugLog.write("обновление: ответ GitHub не разобран")
            settle(.failed(.badResponse))
            return
        }

        let now = Date()
        DispatchQueue.main.async { self.settings.lastUpdateCheck = now }

        guard let current = AppInfo.current else {
            DebugLog.write("обновление: своя версия не разобрана, сравнивать не с чем")
            settle(.failed(.badResponse))
            return
        }

        guard release.version > current else {
            DebugLog.write("обновление: на GitHub \(release.version), у нас \(current) — новее нет")
            // Скачанное, ставшее ненужным, выносим: держать бандл, который
            // уже не новее нашего, незачем.
            if UpdateStore.staged() != nil { UpdateStore.clear() }
            settle(.upToDate(checkedAt: now))
            return
        }

        DebugLog.write("обновление: найдена \(release.version), у нас \(current)")
        useStagedOrDownload(release)
    }

    // MARK: - Загрузка

    private func useStagedOrDownload(_ release: GitHubRelease) {
        if let staged = UpdateStore.staged(), let ready = AppVersion(staged.version) {
            if ready == release.version {
                DebugLog.write("обновление: \(ready) уже скачано, загрузка не нужна")
                becomeReady(release)
                return
            }
            // Вышло что-то ещё новее — старое под нож. Половина от одной версии
            // и половина от другой не соберутся ни во что.
            DebugLog.write("обновление: скачано \(ready), а нужна \(release.version) — чистим")
            UpdateStore.clear()
        }

        guard UpdateStore.makeFolder() else {
            settle(.failed(.installFailed))
            return
        }
        guard hasRoom(for: release) else {
            settle(.failed(.noSpace))
            return
        }

        settle(.downloading(release, progress: 0))
        downloading = release

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        downloadSession = session
        session.downloadTask(with: release.assetURL).resume()
    }

    /// Места надо втрое больше образа: сам образ, распакованное приложение
    /// и запас на копию рядом с целью при установке.
    private func hasRoom(for release: GitHubRelease) -> Bool {
        guard release.assetSize > 0 else { return true }
        let values = try? UpdateStore.folder.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let free = values?.volumeAvailableCapacityForImportantUsage else { return true }
        return free > Int64(release.assetSize) * 3
    }

    // MARK: - Проверка и распаковка скачанного

    /// Разбирает образ: сумма, монтирование, копия, подпись, версия.
    ///
    /// Подпись проверяется у **своей копии**, а не у приложения на образе:
    /// проверить одно, а поставить другое — значит не проверить ничего.
    private func unpack(_ release: GitHubRelease, from image: URL) {
        defer { try? FileManager.default.removeItem(at: image) }

        if let expected = release.checksum {
            guard let actual = Self.checksum(of: image) else {
                settle(.failed(.damaged))
                return
            }
            guard actual == expected else {
                DebugLog.write("обновление: сумма не сошлась — ждали \(expected), вышло \(actual)")
                settle(.failed(.checksumMismatch))
                return
            }
        } else {
            // Суммы в описании не оказалось. Это не повод отказываться: её
            // переносит рукой человек, а подлинность держится на подписи.
            DebugLog.write("обновление: в описании выпуска нет суммы, идём дальше")
        }

        guard let mounted = DiskImage.attach(image) else {
            settle(.failed(.damaged))
            return
        }
        defer { DiskImage.detach(mounted) }

        guard let source = DiskImage.application(in: mounted.mountPoint) else {
            settle(.failed(.damaged))
            return
        }

        let destination = UpdateStore.stagedApp
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            DebugLog.write("обновление: копия с образа не удалась — \(error.localizedDescription)")
            settle(.failed(.installFailed))
            return
        }

        if case let .rejected(reason) = CodeSignatureCheck.matchesSelf(destination) {
            UpdateStore.clear()
            settle(.failed(reason))
            return
        }

        let inside = Self.version(inside: destination)
        guard let inside, inside == release.version else {
            DebugLog.write("обновление: в образе версия \(inside?.text ?? "?"), обещали \(release.version)")
            UpdateStore.clear()
            settle(.failed(.badResponse))
            return
        }

        UpdateStore.write(StagedUpdate(
            tag: release.tag,
            version: release.version.text,
            build: Self.build(inside: destination) ?? "?",
            checksum: release.checksum,
            verifiedAt: Date()
        ))
        DebugLog.write("обновление: \(release.version) скачано и проверено")
        becomeReady(release)
    }

    /// Поднимает уже скачанное после перезапуска.
    ///
    /// Подпись перепроверяется: папка доступна на запись любому процессу
    /// пользователя, и бандл, пролежавший там сутки, — не обязательно тот же
    /// самый бандл, который туда клали.
    private func restoreStaged() {
        guard let staged = UpdateStore.staged() else { return }
        guard let ready = AppVersion(staged.version), let current = AppInfo.current, ready > current else {
            DebugLog.write("обновление: скачанное уже не новее — чистим")
            UpdateStore.clear()
            return
        }
        if case .rejected = CodeSignatureCheck.matchesSelf(UpdateStore.stagedApp) {
            DebugLog.write("обновление: подпись скачанного не сошлась при запуске — чистим")
            UpdateStore.clear()
            return
        }
        DebugLog.write("обновление: с прошлого раза готово \(ready)")
    }

    // MARK: - Установка

    /// Ставит скачанное и выходит. Дальше работает подменщик: он дождётся
    /// нашего выхода, подменит бандл и запустит новое приложение.
    func install() {
        guard case let .ready(release, staged) = state else { return }

        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parent = bundle.deletingLastPathComponent()
        let writable = FileManager.default.isWritableFile(atPath: parent.path)

        switch UpdateInstaller.target(bundleURL: bundle, parentIsWritable: writable) {
        case let .refused(reason):
            DebugLog.write("обновление: ставить некуда — \(reason.message)")
            settle(.failed(reason))

        case let .ready(target):
            settle(.installing)
            if let reason = UpdateInstaller.install(staged: staged, into: target) {
                settle(.failed(reason))
                return
            }
            DebugLog.write("обновление: ставим \(release.version), выходим")
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Мелочи

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private func becomeReady(_ release: GitHubRelease) {
        settle(.ready(release, staged: UpdateStore.stagedApp))
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.announced else { return }
            self.announced = true
            self.onReady?(release)
        }
    }

    private func settle(_ next: UpdateState) {
        DispatchQueue.main.async { [weak self] in self?.state = next }
    }

    static func checksum(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        var digest = SHA256()
        // Кусками, а не целиком: образ невелик, но читать файл в память ради
        // суммы — привычка, которая однажды встретит файл побольше.
        while let piece = try? handle.read(upToCount: 1 << 20), !piece.isEmpty {
            digest.update(data: piece)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func plist(inside bundle: URL) -> [String: Any]? {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
            as? [String: Any]
    }

    private static func version(inside bundle: URL) -> AppVersion? {
        (plist(inside: bundle)?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private static func build(inside bundle: URL) -> String? {
        plist(inside: bundle)?["CFBundleVersion"] as? String
    }
}

extension UpdateService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let release = downloading else { return }
        // Сервер не всегда присылает длину — тогда берём размер из описания
        // выпуска: он там есть всегда.
        let total = totalBytesExpectedToWrite > 0
            ? Double(totalBytesExpectedToWrite)
            : Double(release.assetSize)
        guard total > 0 else { return }

        let share = min(1, Double(totalBytesWritten) / total)
        if case let .downloading(_, shown) = state, Int(shown * 100) == Int(share * 100) { return }
        settle(.downloading(release, progress: share))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let release = downloading else { return }
        // Временный файл система уносит сразу после возврата из этого метода —
        // переносим его себе прежде всего прочего.
        let image = UpdateStore.imageFile(named: release.assetName)
        try? FileManager.default.removeItem(at: image)
        do {
            try FileManager.default.moveItem(at: location, to: image)
        } catch {
            DebugLog.write("обновление: скачанное не перенеслось — \(error.localizedDescription)")
            settle(.failed(.installFailed))
            return
        }
        unpack(release, from: image)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            downloadSession?.finishTasksAndInvalidate()
            downloadSession = nil
            downloading = nil
        }
        guard let error else { return }
        DebugLog.write("обновление: загрузка сорвалась — \(error.localizedDescription)")
        settle(.failed(.network))
    }
}
