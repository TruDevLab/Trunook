import TrunookXPC
import Foundation

/// Описания выпусков для страницы «Описание» в окне знакомства.
///
/// Берутся у GitHub и кладутся в кэш на диск. Кэш не ради экономии запросов,
/// а ради того, чтобы страница работала без сети: человек, только что
/// обновившийся, читает, что изменилось, — и лист «не загрузилось» вместо
/// описания обесценивает саму затею.
///
/// Выбор текущей страницы живёт здесь же, а не в вёрстке: `@State` в этом
/// тулчейне недоступен, и держать его больше негде — по той же причине так
/// устроены `HoverTracker` и `WeatherPlaceSearch`.
final class ReleaseNotesService: NSObject, ObservableObject {
    /// Что показывать в правой половине страницы.
    enum Selection: Equatable {
        case release(tag: String)
        /// README из бандла — рассказ о приложении целиком.
        case readme
    }

    enum State: Equatable {
        case idle
        case loading
        case ready([ReleaseNote])
        /// Ни сети, ни кэша. README при этом всё равно есть — он в бандле.
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published var selection: Selection = .readme

    private let session: URLSession
    /// Сколько выпусков просить. Двадцати хватает на всю историю проекта
    /// с запасом, а страничная навигация ради архива, который читают раз
    /// в жизни, не окупается.
    private static let pageSize = 20

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        super.init()
    }

    // MARK: - Загрузка

    /// Читает кэш и сразу за ним идёт в сеть.
    ///
    /// Именно в таком порядке: кэш показывается мгновенно, а обновление
    /// приезжает молча. Ждать сети, имея на диске готовый ответ, значит
    /// показывать пустой лист на ровном месте.
    func load() {
        // Отладочный вход: нажать по строке списка из сессии нечем, а снимать
        // README нужно — в нём таблицы и картинки, которых у выпусков нет.
        //   defaults write com.trunook.Trunook debugNotesReadme -bool YES
        if DebugLog.isEnabled, UserDefaults.standard.bool(forKey: "debugNotesReadme") {
            select(.readme)
        }
        if case .loading = state { return }
        if let cached = Self.readCache(), !cached.isEmpty {
            settle(.ready(cached))
        } else {
            settle(.loading)
        }
        fetch()
    }

    private func fetch() {
        let address = "https://api.github.com/repos/\(UpdateService.repository)"
            + "/releases?per_page=\(Self.pageSize)"
        guard let url = URL(string: address) else {
            settle(.failed)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // Без своего имени GitHub отвечает отказом — та же мелочь, что
        // и в `UpdateService`.
        request.setValue("Trunook/\(AppInfo.shortVersion)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, failure in
            guard let self else { return }
            if let failure {
                DebugLog.write("описания выпусков: сеть — \(failure.localizedDescription)")
                self.finishFetch(nil)
                return
            }
            guard let data else {
                self.finishFetch(nil)
                return
            }
            let notes = ReleaseNote.parseList(data)
            if notes.isEmpty {
                DebugLog.write("описания выпусков: ответ не разобран")
                self.finishFetch(nil)
                return
            }
            Self.writeCache(data)
            DebugLog.write("описания выпусков: получено \(notes.count)")
            self.finishFetch(notes)
        }.resume()
    }

    private func finishFetch(_ notes: [ReleaseNote]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let notes {
                self.apply(.ready(notes))
                return
            }
            // Неудача поверх показанного кэша ничего не меняет: старое
            // описание полезнее пустого листа.
            if case .ready = self.state { return }
            self.apply(.failed)
        }
    }

    private func settle(_ next: State) {
        if Thread.isMainThread {
            apply(next)
        } else {
            DispatchQueue.main.async { [weak self] in self?.apply(next) }
        }
    }

    private func apply(_ next: State) {
        guard state != next else { return }
        state = next
        // Выбор по умолчанию — свежий выпуск: страницу открывают сразу после
        // обновления, и первое, что человек хочет прочитать, — что нового.
        if case let .ready(notes) = next, let newest = notes.first {
            if case .readme = selection, !openedByHand {
                selection = .release(tag: newest.tag)
            }
        }
    }

    /// Человек уже выбрал страницу сам — не перебивать его приехавшим ответом.
    private var openedByHand = false

    func select(_ selection: Selection) {
        openedByHand = true
        self.selection = selection
    }

    var notes: [ReleaseNote] {
        if case let .ready(notes) = state { return notes }
        return []
    }

    func note(tagged tag: String) -> ReleaseNote? {
        notes.first { $0.tag == tag }
    }

    // MARK: - README из бандла

    /// README на языке интерфейса.
    ///
    /// Из бандла, а не из сети: он описывает ровно ту версию, которая стоит,
    /// и читается без интернета. В сети лежит README ветки `main` — он
    /// рассказывал бы про то, чего в установленном приложении ещё нет.
    ///
    /// С памятью на прочитанное, и это не преждевременная забота: спрашивают
    /// его из тела вида, а тело вида SwiftUI пересчитывает постоянно —
    /// ходить за этим на диск нельзя. Языков три, файл читается по разу
    /// на каждый.
    static func readme(language: Language) -> String {
        if let ready = readmeByLanguage[language] { return ready }
        let text = readFromBundle(language: language)
        readmeByLanguage[language] = text
        return text
    }

    private static var readmeByLanguage: [Language: String] = [:]

    private static func readFromBundle(language: Language) -> String {
        let name: String
        switch language {
        case .en: name = "README.en"
        case .zh: name = "README.zh"
        case .ru, .system: name = "README"
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            DebugLog.write("описание: \(name).md не найден в бандле")
            return ""
        }
        return text
    }

    // MARK: - Кэш

    /// Рядом с прочим нашим в Application Support, но **не** в папке
    /// обновления: её выносит целиком `UpdateStore.clear()` после установки —
    /// то есть ровно перед тем запуском, на котором описание и понадобится.
    private static var cacheFile: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base
            .appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("releases.json")
    }

    private static func readCache() -> [ReleaseNote]? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return ReleaseNote.parseList(data)
    }

    private static func writeCache(_ data: Data) {
        let file = cacheFile
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        } catch {
            DebugLog.write("описания выпусков: кэш не записан — \(error.localizedDescription)")
        }
    }
}
