import AppKit
import TrunookXPC

/// Ссылка на файл из iCloud Drive: копия в папку «Trunook» в iCloud Drive
/// и публичная ссылка на неё — в буфер обмена.
///
/// Ссылку выдаёт `FileManager.url(forPublishingUbiquitousItemAt:)` — то же,
/// что «Скопировать ссылку» в Finder. Разрешения iCloud приложению для этого
/// не нужно: iCloud Drive — обычная папка человека, а ссылку выдаёт служба
/// системы, а не контейнер приложения. Проверено пробой.
///
/// **Ссылка бывает только на загруженный файл.** Пока копия едет на сервер,
/// служба отвечает ошибкой `BRCloudDocsErrorDomain` 7 — «ещё не загружено».
/// Поэтому не спрашиваем один раз, а ждём: переспрашиваем, пока не выдаст
/// или не выйдет срок. Срок — час, и он не перестраховка: файл встаёт
/// в общую очередь iCloud Drive, и если в ней тысячи других файлов, пять
/// килобайт ждут за ними. Так и было: рабочий стол синхронизировался
/// вместе с `.build` проекта, и файл получил ссылку через полтора часа,
/// хотя в Finder лежал в iCloud Drive сразу — Finder показывает место,
/// а не то, что файл уже на сервере.
///
/// Папку ссылкой не отдать — служба делится только файлами. Папка
/// сначала сжимается в ZIP прямо в iCloud Drive.
enum CloudShare {
    enum Failure: Error {
        case noDrive
        case timedOut
        case other(String)
    }

    /// Корень iCloud Drive. Нет папки — iCloud Drive выключен.
    static var driveRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: driveRoot.path)
    }

    /// Сколько ждать загрузки, прежде чем сдаться.
    static let uploadTimeout: TimeInterval = 60 * 60
    /// Как часто переспрашивать.
    static let pollInterval: TimeInterval = 2

    /// Лежит ли файл уже в iCloud Drive — тогда копировать незачем.
    static func isInDrive(_ url: URL, root: URL = driveRoot) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(base + "/")
    }

    /// Кладёт файл в iCloud Drive и дожидается ссылки. Синхронно и долго —
    /// звать не с главного потока.
    static func publish(_ url: URL, onUploading: () -> Void, onQueued: () -> Void) throws -> URL {
        guard isAvailable else { throw Failure.noDrive }
        let item = try place(url)
        onUploading()
        return try waitForLink(item, onQueued: onQueued)
    }

    /// Копия в папку «Trunook». Файл, уже лежащий в iCloud Drive, идёт как есть.
    private static func place(_ url: URL) throws -> URL {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        if isInDrive(url), !isDirectory { return url }

        let folder = driveRoot.appendingPathComponent("Trunook", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        if isDirectory {
            let zip = ShelfFileActions.freeURL(named: url.lastPathComponent + ".zip", in: folder)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, zip.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.other("ditto \(process.terminationStatus)") }
            return zip
        }
        let copy = ShelfFileActions.freeURL(named: url.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    /// Через сколько ожидания сказать, что файл стоит в очереди iCloud.
    static let queuedAfter: TimeInterval = 20

    private static func waitForLink(_ item: URL, onQueued: () -> Void) throws -> URL {
        let started = Date()
        var toldQueued = false
        let deadline = Date().addingTimeInterval(uploadTimeout)
        var attempt = 0
        while true {
            do {
                let link = try FileManager.default.url(forPublishingUbiquitousItemAt: item, expiration: nil)
                DebugLog.write("icloud: ссылка готова с попытки \(attempt + 1)")
                return link
            } catch {
                let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
                let notYet = underlying?.domain == "BRCloudDocsErrorDomain" && underlying?.code == 7
                if !notYet {
                    DebugLog.write("icloud: ссылки нет — \(error)")
                    throw Failure.other(error.localizedDescription)
                }
                if attempt % 15 == 0 {
                    DebugLog.write("icloud: ждём загрузки \(item.lastPathComponent), попытка \(attempt + 1)")
                }
            }
            attempt += 1
            guard Date() < deadline else { throw Failure.timedOut }
            if !toldQueued, Date().timeIntervalSince(started) >= queuedAfter {
                toldQueued = true
                onQueued()
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}
