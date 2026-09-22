import TrunookXPC
import Foundation

/// Входящие уведомления: папка, куда кто угодно кладёт файл-вопрос.
///
/// Папкой, а не сетевым портом и не своей схемой ссылок. Порт — это служба,
/// которую надо защищать; схема ссылок требует бинарника-посредника, чтобы
/// ею воспользоваться из шелла. А файл умеет положить всё на свете: хук
/// помощника в терминале, сборочный скрипт, `cron`, «Команды», одна строка
/// `cat > … <<EOF`. Права на папку — те же, что на домашний каталог: кто
/// туда пишет, тот и так работает от имени человека.
///
/// Ответ уходит тем же способом — строкой в файл, путь к которому назвал
/// сам приславший (`reply`). Ждать появления файла умеет любой скрипт,
/// а ничего другого от нас и не нужно: вырез не исполняет присланные
/// команды и не ходит по присланным ссылкам — он только спрашивает
/// человека и пересказывает ответ.
final class NotifyInbox: ObservableObject {
    /// Пришло новое уведомление.
    var onNotice: ((ExternalNotice) -> Void)?

    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private let queue = DispatchQueue(label: "com.trunook.notify-inbox")
    private let settings: Settings

    init(settings: Settings = .shared, folder: URL? = nil) {
        self.settings = settings
        self.folder = folder ?? Self.defaultFolder
    }

    static var defaultFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
    }

    // MARK: - Жизнь службы

    func start() {
        guard settings.inboxEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            DebugLog.write("входящие: папку не создать — \(error.localizedDescription)")
            return
        }

        descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DebugLog.write("входящие: папка не открылась")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: queue
        )
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
        DebugLog.write("входящие: слежу за \(folder.path)")

        // Первый разбор сразу: пока приложение не работало, в папке могло
        // накопиться — и тот, кто ждёт ответа, ждёт его до сих пор.
        queue.async { [weak self] in self?.drain() }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    // MARK: - Разбор

    /// Сколько раз перечитывать файл, который не разобрался.
    ///
    /// Папка сообщает о записи в тот же миг, когда её начали, а не когда
    /// закончили: обычное `echo > файл` успевает отдать нам половину строки.
    /// Поймано живьём на первом же образце — «не разобрался как JSON»
    /// на совершенно правильном файле.
    ///
    /// Поэтому негодный файл не выбрасывается сразу, а перечитывается
    /// ещё дважды. Писать атомарно (во временный файл и `mv`) всё равно
    /// правильнее, и в примерах так и написано, — но требовать этого
    /// от чужого однострочника нельзя.
    private static let retries = 2
    private static let retryDelay: TimeInterval = 0.2
    private var attempts: [String: Int] = [:]

    /// Забрать всё, что лежит в папке, и показать по очереди.
    ///
    /// Файл удаляется сразу после удачного разбора, до показа: плашка живёт
    /// минутами, а следующее событие папки придёт через миллисекунды —
    /// оставленный файл показался бы второй раз, третий и так далее.
    func drain() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []

        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
            let name = file.lastPathComponent
            guard let data = try? Data(contentsOf: file) else { continue }

            guard data.count <= Self.maxFileSize else {
                try? FileManager.default.removeItem(at: file)
                DebugLog.write("входящие: \(name) больше \(Self.maxFileSize) байт — пропущено")
                continue
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                retry(file, name: name)
                continue
            }

            attempts[name] = nil
            try? FileManager.default.removeItem(at: file)
            guard let notice = ExternalNotice(
                json: json, id: file.deletingPathExtension().lastPathComponent
            ) else { continue }

            DebugLog.write("входящие: «\(notice.source): \(notice.title)»"
                           + (notice.waitsForAnswer ? ", ждёт ответа" : ""))
            DispatchQueue.main.async { [weak self] in self?.onNotice?(notice) }
        }
    }

    /// Перечитать файл позже — может быть, его ещё дописывают.
    private func retry(_ file: URL, name: String) {
        let done = (attempts[name] ?? 0) + 1
        attempts[name] = done
        guard done <= Self.retries else {
            attempts[name] = nil
            try? FileManager.default.removeItem(at: file)
            DebugLog.write("входящие: \(name) — не разобрался как JSON, выброшен")
            return
        }
        queue.asyncAfter(deadline: .now() + Self.retryDelay) { [weak self] in self?.drain() }
    }

    /// Потолок размера файла. Уведомление — это вопрос в одну строку;
    /// всё, что больше, прислано по ошибке, и разбирать мегабайты чужого
    /// JSON в вырезе незачем.
    static let maxFileSize = 64 * 1024

    // MARK: - Ответ

    /// Написать ответ туда, куда просил приславший.
    ///
    /// Путь проверяется на попадание в домашнюю папку или во временную:
    /// уведомление приходит снаружи, и запись по присланному пути куда
    /// угодно — это чужими руками править чужие файлы. Ответ короткий
    /// и заведомо безобидный, но право писать в «/etc» давать нельзя.
    @discardableResult
    func reply(to notice: ExternalNotice, answer: String) -> Bool {
        guard let path = notice.replyPath, !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized
        guard Self.mayWrite(to: url) else {
            DebugLog.write("входящие: ответ мимо домашней папки — \(url.path), отказ")
            return false
        }
        do {
            try (answer + "\n").write(to: url, atomically: true, encoding: .utf8)
            DebugLog.write("входящие: ответ «\(answer)» — \(url.lastPathComponent)")
            return true
        } catch {
            DebugLog.write("входящие: ответ не записан — \(error.localizedDescription)")
            return false
        }
    }

    /// Куда разрешено писать ответ.
    ///
    /// Отдельной чистой функцией — ровно затем, чтобы это правило можно было
    /// проверить, не трогая диска: запись по присланному пути стоит
    /// проверять тестом, а не глазами.
    ///
    /// Своя временная папка (`$TMPDIR`) здесь наравне с домашней, и это
    /// не мелочь: на macOS она лежит не в «/tmp», а в
    /// «/var/folders/…/T/» — и первое же живое испытание скрипта
    /// уткнулось в «ответ мимо домашней папки», потому что скрипт клал
    /// файл ровно туда, куда кладут все.
    static func mayWrite(to url: URL) -> Bool {
        let path = url.standardized.path
        let allowed = [
            FileManager.default.homeDirectoryForCurrentUser.standardized.path,
            FileManager.default.temporaryDirectory.standardized.path,
            "/tmp",
            "/private/tmp",
        ]
        // Внутрь папки, а не в саму папку: путь без имени файла — это
        // запись в каталог, и разрешать её незачем.
        return allowed.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}
