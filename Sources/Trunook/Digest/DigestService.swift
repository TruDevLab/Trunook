import TrunookXPC
import AppKit
import Foundation

/// Собирает сводку новостей по расписанию и хранит прошлые.
///
/// Устроена как `UpdateService`: частый тик спрашивает чистое расписание,
/// пробуждение проверяет его сразу, первый заход — через полминуты после
/// запуска. Сама работа идёт последовательно по темам: у местной модели
/// одна очередь, и параллельные вопросы только растянули бы каждый.
final class DigestService: ObservableObject {
    /// Сводки, новые первыми.
    @Published private(set) var digests: [Digest] = []
    @Published private(set) var isRunning = false
    /// Что делается сейчас — строкой для панели и настроек.
    @Published private(set) var progress: String?
    /// Последняя сборка сорвалась целиком.
    @Published private(set) var lastFailed = false
    /// Свежую сводку ещё не открывали. Держит метку в свёрнутой чёлке.
    @Published private(set) var hasUnseen = false
    /// Темы, предложенные моделью, и идёт ли подбор.
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var isSuggesting = false

    /// Сводка готова. Владелец показывает плашку.
    var onReady: ((Digest) -> Void)?

    static let keep = 30
    private static let tick: TimeInterval = 60
    private static let firstDelay: TimeInterval = 30
    /// Не чаще раза в час после сорвавшейся сборки: иначе минутный тик
    /// долбил бы выключенную сеть до вечера.
    private static let retryAfterFailure: TimeInterval = 60 * 60

    private let settings: Settings
    private let client: ModelClient
    private let session: URLSession
    private let fileURL: URL
    private var timer: Timer?
    private var lastAttempt: Date?

    init(settings: Settings = .shared, client: ModelClient = ModelClient(), fileURL: URL = DigestService.defaultFile) {
        self.settings = settings
        self.client = client
        self.fileURL = fileURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        load()
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("digests.json")
    }

    // MARK: - Жизнь службы

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstDelay) { [weak self] in
            self?.tick()
        }
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func woke() {
        // Сеть после пробуждения поднимается не сразу — первый запрос
        // в ту же секунду почти всегда падает.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.tick()
        }
    }

    func tick(now: Date = Date()) {
        guard settings.digestEnabled, settings.ollamaEnabled, !isRunning else { return }
        let anchor = DigestSchedule.anchor(now: now, last: settings.lastDigestRun)
        if anchor != settings.lastDigestRun { settings.lastDigestRun = anchor }
        guard settings.digestSchedule.isDue(now: now, last: anchor) else { return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.retryAfterFailure { return }
        run(manual: false)
    }

    // MARK: - Сборка

    var activeTopics: [DigestTopic] {
        settings.digestTopics.filter {
            $0.isEnabled && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func run(manual: Bool) {
        guard !isRunning else { return }
        guard settings.ollamaEnabled else {
            DebugLog.write("сводка: модель выключена — не собираю")
            return
        }
        let topics = activeTopics
        guard !topics.isEmpty else {
            DebugLog.write("сводка: тем нет — не собираю")
            return
        }

        let now = Date()
        lastAttempt = now
        isRunning = true
        lastFailed = false
        OllamaEngine.shared.ensureUp()
        DebugLog.write("сводка: собираю \(manual ? "вручную" : "по расписанию"), тем \(topics.count)")

        Task { @MainActor in
            let since = DigestSchedule.since(now: now, last: settings.lastDigestRun)
            var sections: [DigestSection] = []
            for (index, topic) in topics.enumerated() {
                progress = tf("%@ — %d из %d", topic.title, index + 1, topics.count)
                sections.append(await section(for: topic, since: since, now: now))
            }
            finish(sections: sections, since: since, now: now)
        }
    }

    @MainActor
    private func section(for topic: DigestTopic, since: Date, now: Date) async -> DigestSection {
        let model = settings.digestModel
        var topic = topic
        if topic.queries.isEmpty,
           let raw = await BackgroundModel.ask(
               DigestPrompt.queriesPrompt(topic: topic.title), model: model, client: client, label: "сводка"
           ) {
            let queries = DigestPrompt.parseQueries(raw)
            if !queries.isEmpty {
                topic.queries = queries
                // Сохраняем, только если тему не переименовали, пока шла сборка:
                // иначе запросы старой темы легли бы под новое название.
                if settings.digestTopics.first(where: { $0.id == topic.id })?.title == topic.title {
                    settings.updateDigestTopic(topic)
                }
                DebugLog.write("сводка: «\(topic.title)» — запросы \(queries)")
            }
        }

        var items: [NewsItem] = []
        var fetched = false
        let interface = Localization.shared.resolved
        for query in topic.searchQueries {
            let edition = NewsFeed.edition(for: query, interface: interface)
            guard let url = NewsFeed.url(query: query, since: since, now: now, edition: edition) else { continue }
            if let found = await fetch(url) {
                fetched = true
                items += found
            }
        }
        guard fetched else {
            return DigestSection(id: topic.id, title: topic.title, entries: [], failed: true)
        }

        let candidates = NewsCandidates.prepare(items, since: since)
        DebugLog.write("сводка: «\(topic.title)» — в ленте \(items.count), кандидатов \(candidates.count)")
        guard !candidates.isEmpty else {
            return DigestSection(id: topic.id, title: topic.title, entries: [])
        }

        let prompt = DigestPrompt.selectionPrompt(topic: topic.title, candidates: candidates, language: interface)
        guard let raw = await BackgroundModel.ask(prompt, model: model, client: client, label: "сводка") else {
            return DigestSection(id: topic.id, title: topic.title, entries: [], failed: true)
        }
        DebugLog.write("сводка: «\(topic.title)» — ответ модели: \(raw.prefix(400).replacingOccurrences(of: "\n", with: " ¶ "))")
        let entries = DigestPrompt.parseSelection(raw, count: candidates.count).map { found in
            let item = candidates[found.index]
            let pick = DigestPrompt.dropsEcho(found, title: item.title)
            return DigestEntry(title: item.title, source: item.source, link: item.link,
                               published: item.published, summary: pick.summary)
        }
        DebugLog.write("сводка: «\(topic.title)» — отобрано \(entries.count)")
        return DigestSection(id: topic.id, title: topic.title, entries: entries)
    }

    private func fetch(_ url: URL) async -> [NewsItem]? {
        var request = URLRequest(url: url)
        request.setValue(PageLoader.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                DebugLog.write("сводка: лента ответила \(http.statusCode)")
                return nil
            }
            return NewsFeedParser.parse(data)
        } catch {
            DebugLog.write("сводка: лента не открылась — \(error.localizedDescription)")
            return nil
        }
    }

    @MainActor
    private func finish(sections: [DigestSection], since: Date, now: Date) {
        isRunning = false
        progress = nil
        // Все темы сорвались — это не сводка, а сбой. Пустую сводку класть
        // нельзя: плашка «сводка готова» над пустотой учит ей не верить.
        guard sections.contains(where: { !$0.failed }) else {
            lastFailed = true
            DebugLog.write("сводка: не собралась ни одна тема")
            return
        }
        let digest = Digest(createdAt: now, since: since, sections: sections)
        digests.insert(digest, at: 0)
        if digests.count > Self.keep { digests.removeLast(digests.count - Self.keep) }
        hasUnseen = true
        lastAttempt = nil
        settings.lastDigestRun = now
        save()
        DebugLog.write("сводка: готова, новостей \(digest.entryCount)")
        onReady?(digest)
    }

    // MARK: - Подсказка тем

    /// Отдаёт ли подсказка модели названия заметок: только местной.
    var suggestionsUseNotes: Bool {
        let provider = settings.modelRef(settings.digestModel)?.provider ?? settings.aiProvider
        return provider.isLocal
    }

    func suggestTopics(noteTitles: [String]) {
        guard settings.ollamaEnabled, !isSuggesting else { return }
        isSuggesting = true
        OllamaEngine.shared.ensureUp()
        let existing = settings.digestTopics.map(\.title)
        let titles = suggestionsUseNotes ? Array(noteTitles.prefix(40)) : []
        let prompt = DigestPrompt.suggestionsPrompt(
            existing: existing, noteTitles: titles, language: Localization.shared.resolved
        )
        Task { @MainActor in
            let raw = await BackgroundModel.ask(prompt, model: settings.digestModel, client: client, label: "сводка")
            suggestions = raw.map {
                DigestPrompt.parseSuggestions($0, existing: existing, noteTitles: titles)
            } ?? []
            isSuggesting = false
            DebugLog.write("сводка: предложено тем \(suggestions.count), по заметкам \(titles.count)")
        }
    }

    /// Отмеченные темы добавлены — из подсказок они уходят.
    func accept(_ chosen: Set<String>) {
        for title in suggestions where chosen.contains(title) {
            settings.addDigestTopic(title)
        }
        suggestions.removeAll { chosen.contains($0) }
    }

    func clearSuggestions() {
        suggestions = []
    }

    // MARK: - Действия

    func markSeen() {
        guard hasUnseen else { return }
        hasUnseen = false
        save()
    }

    @discardableResult
    func saveToNotes(_ digest: Digest, notes: NotesService) -> Bool {
        notes.save(DigestExport.attributed(for: digest), origin: .digest,
                   title: DigestExport.noteTitle(for: digest)) != nil
    }

    // MARK: - Хранение

    private struct Archive: Codable {
        var unseen: Bool
        var digests: [Digest]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Archive.self, from: data)
        else { return }
        digests = archive.digests
        hasUnseen = archive.unseen && !archive.digests.isEmpty
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Archive(unseen: hasUnseen, digests: digests))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.write("сводка: не записалась — \(error.localizedDescription)")
        }
    }
}
