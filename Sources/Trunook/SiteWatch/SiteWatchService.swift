import TrunookXPC
import AppKit
import CryptoKit
import Foundation

/// Проверяет сайты по расписанию и сообщает, когда значение изменилось.
///
/// Порядок проверки держит модель в стороне, пока без неё можно:
/// цена из разметки страницы берётся без модели, а неизменившийся текст
/// страницы не показывается ей вовсе. Модель зовётся, только когда
/// страница правда стала другой.
final class SiteWatchService: ObservableObject {
    @Published private(set) var states: [Int: WatchState] = [:]
    /// Какую слежку проверяют прямо сейчас.
    @Published private(set) var checkingID: Int?

    /// Значение изменилось. Владелец показывает плашку.
    var onChange: ((SiteWatch, WatchChange) -> Void)?

    private static let tick: TimeInterval = 60
    private static let firstDelay: TimeInterval = 45

    private let settings: Settings
    private let client: ModelClient
    private let loader = PageLoader()
    private let fileURL: URL
    private var timer: Timer?
    private var queue: [Int] = []

    init(settings: Settings = .shared, client: ModelClient = ModelClient(), fileURL: URL = SiteWatchService.defaultFile) {
        self.settings = settings
        self.client = client
        self.fileURL = fileURL
        load()
    }

    static var defaultFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Trunook", isDirectory: true)
            .appendingPathComponent("site-watch.json")
    }

    var hasUnseen: Bool {
        let ids = Set(settings.siteWatches.map(\.id))
        return states.contains { ids.contains($0.key) && $0.value.unseen }
    }

    /// Состояние слежки — пустое, если цель или адрес с тех пор поменяли.
    func state(of watch: SiteWatch) -> WatchState {
        guard let state = states[watch.id], state.matches(watch) else { return WatchState() }
        return state
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.tick()
        }
    }

    func tick(now: Date = Date()) {
        guard settings.siteWatchEnabled else { return }
        // Состояние от прежней цели — всё равно что его нет: такую слежку
        // проверяем сразу, а не через час.
        let due = settings.siteWatches.filter {
            $0.isEnabled && $0.pageURL != nil
                && WatchSchedule.isDue(now: now, checkedAt: state(of: $0).checkedAt, interval: $0.interval)
        }
        enqueue(due.map(\.id))
    }

    func checkAll() {
        enqueue(settings.siteWatches.filter { $0.isEnabled && $0.pageURL != nil }.map(\.id))
    }

    func check(id: Int) {
        enqueue([id])
    }

    private func enqueue(_ ids: [Int]) {
        for id in ids where id != checkingID && !queue.contains(id) {
            queue.append(id)
        }
        next()
    }

    private func next() {
        guard checkingID == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let watch = settings.siteWatches.first(where: { $0.id == id }), let url = watch.pageURL else {
            next()
            return
        }
        checkingID = id
        Task { @MainActor in
            await run(watch, url: url)
            checkingID = nil
            next()
        }
    }

    // MARK: - Проверка

    @MainActor
    private func run(_ watch: SiteWatch, url: URL) async {
        var state = self.state(of: watch)
        state.target = watch.target
        state.url = watch.url
        let now = Date()
        defer {
            state.checkedAt = now
            states[watch.id] = state
            save()
        }

        guard let page = await loader.load(url) else {
            state.status = .failed
            return
        }
        if PageBlock.detect(title: page.title, text: page.text) {
            DebugLog.write("слежка: «\(watch.displayName)» — сайт не пустил («\(page.title)»)")
            state.status = .blocked
            return
        }

        let reading: WatchReading
        if WatchExtract.wantsPrice(watch.target), let price = Self.priceReading(page) {
            reading = price
        } else {
            let text = String(page.text.prefix(WatchExtract.pageLimit))
            let hash = Self.hash(text)
            if hash == state.textHash, state.reading != nil {
                state.status = .ok
                DebugLog.write("слежка: «\(watch.displayName)» — страница та же, модель не зову")
                return
            }
            guard settings.ollamaEnabled else {
                DebugLog.write("слежка: «\(watch.displayName)» — нужна модель, а она выключена")
                state.status = .failed
                return
            }
            OllamaEngine.shared.ensureUp()
            let prompt = WatchExtract.prompt(target: watch.target, title: page.title, text: text)
            guard let raw = await BackgroundModel.ask(
                prompt, model: settings.digestModel, client: client, label: "слежка"
            ) else {
                state.status = .failed
                return
            }
            guard let found = WatchExtract.parse(raw) else {
                DebugLog.write("слежка: «\(watch.displayName)» — на странице не нашлось «\(watch.target)»")
                state.textHash = hash
                state.status = .notFound
                return
            }
            state.textHash = hash
            reading = found
        }

        state.status = .ok
        let change = WatchRule.evaluate(
            previous: state.reading, current: reading,
            condition: watch.condition, threshold: watch.threshold
        )
        DebugLog.write("слежка: «\(watch.displayName)» — \(reading.text)\(change == nil ? "" : ", изменилось")")
        if let change {
            state.previous = change.old
            state.changedAt = now
            state.unseen = true
            onChange?(watch, change)
        }
        state.reading = reading
    }

    /// Цена из разметки: «11490» и «RUB» становятся «11 490 ₽».
    static func priceReading(_ page: PageSnapshot) -> WatchReading? {
        guard let raw = page.price, let number = WatchNumber.parse(raw) else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.locale = Localization.shared.resolved.locale
        let amount = formatter.string(from: NSNumber(value: number)) ?? raw
        let symbols = ["RUB": "₽", "RUR": "₽", "USD": "$", "EUR": "€", "GBP": "£", "CNY": "¥", "KZT": "₸"]
        guard let code = page.currency?.uppercased(), !code.isEmpty else {
            return WatchReading(text: amount, number: number)
        }
        return WatchReading(text: "\(amount) \(symbols[code] ?? code)", number: number)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Действия

    func markSeen() {
        guard states.values.contains(where: \.unseen) else { return }
        for id in states.keys { states[id]?.unseen = false }
        save()
    }

    /// Слежку убрали или сменили адрес — старое значение к ней больше
    /// не относится.
    func reset(id: Int) {
        states[id] = nil
        save()
    }

    func openForVerification(_ watch: SiteWatch) {
        guard let url = watch.pageURL else { return }
        SiteVerifyWindow.shared.open(url, title: watch.displayName)
    }

    /// Отладка: загрузить первую слежку и рассказать в журнал, что увидели.
    func probe() {
        guard let watch = settings.siteWatches.first, let url = watch.pageURL else {
            DebugLog.write("слежка: проба — слежек нет")
            return
        }
        Task { @MainActor in
            guard let page = await loader.load(url) else {
                DebugLog.write("слежка: проба — страница не открылась")
                return
            }
            let blocked = PageBlock.detect(title: page.title, text: page.text)
            DebugLog.write("слежка: проба «\(page.title)», текста \(page.text.count), "
                           + "цена в разметке \(page.price ?? "нет") \(page.currency ?? ""), "
                           + "отказ \(blocked ? "да" : "нет")")
            DebugLog.write("слежка: начало страницы — \(page.text.prefix(300).replacingOccurrences(of: "\n", with: " ¶ "))")
        }
    }

    // MARK: - Хранение

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: WatchState].self, from: data)
        else { return }
        var states: [Int: WatchState] = [:]
        for (key, value) in stored {
            if let id = Int(key) { states[id] = value }
        }
        self.states = states
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: states.map { (String($0.key), $0.value) })
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.write("слежка: не записалось — \(error.localizedDescription)")
        }
    }
}
