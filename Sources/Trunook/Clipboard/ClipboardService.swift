import TrunookXPC
import AppKit

/// История буфера обмена: наблюдение, хранение и возврат записи обратно.
final class ClipboardService: ObservableObject {
    /// Свежие записи, самая новая первой.
    @Published private(set) var entries: [ClipboardEntry] = []

    /// Какая строка подсвечена с клавиатуры. `nil` — ни одна, и это обычное
    /// состояние: список открывают и мышью тоже, а подсветка без нажатой
    /// стрелки — обещание, что Enter куда-то вставит.
    @Published var highlighted: Int64?

    /// Сообщает о новом копировании — по нему вырез показывает плашку.
    var onCopy: ((ClipboardEntry) -> Void)?

    /// Сколько записей получают горячие клавиши и номера в списке.
    static let hotSlotCount = 9

    private let settings: Settings
    private let store = ClipboardStore()
    private let monitor = ClipboardMonitor()
    private var pruneTimer: Timer?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        guard settings.clipboardEnabled else { return }

        monitor.onCopy = { [weak self] entry in
            guard let self else { return }
            self.store.insert(entry)
            self.reload()
            // Плашку показываем по свежему списку: в нём у записи уже есть
            // номер, а у повтора — прежний идентификатор.
            if let stored = self.entries.first { self.onCopy?(stored) }
        }
        monitor.start()

        prune()
        reload()

        // Срок хранения истекает сам по себе, без всяких событий: раз
        // в минуту проверяем, не пора ли что-то убрать.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.prune()
            self?.reload()
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    func stop() {
        monitor.stop()
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    /// Перечитывает список. Держим на один больше, чем показываем: так видно,
    /// что список прокручивается, а не обрывается ровно по границе.
    private func reload() {
        entries = store.recent(limit: settings.clipboardLimit)
        // Подсветка снимается вместе с записью, на которой стояла: список
        // живой, и запись из него уходит сама — по сроку хранения или потому,
        // что вытеснена свежей. Оставленная подсветка означала бы Enter
        // в никуда.
        if let id = highlighted, !entries.contains(where: { $0.id == id }) {
            highlighted = nil
        }
    }

    /// Запись, на которой стоит подсветка.
    var highlightedEntry: ClipboardEntry? {
        guard let id = highlighted else { return nil }
        return entries.first { $0.id == id }
    }

    /// Увести подсветку на строку выше или ниже. Возвращает, забрал ли
    /// список нажатие себе. Само правило шага — в `HighlightMove`: оно общее
    /// со списком команд.
    @discardableResult
    func moveHighlight(_ offset: Int) -> Bool {
        guard !entries.isEmpty else { return false }
        highlighted = HighlightMove.next(
            from: highlighted, in: entries.map(\.id), offset: offset
        )
        return true
    }

    private func prune() {
        store.prune(lifetime: settings.clipboardLifetime, limit: settings.clipboardLimit)
    }

    // MARK: - Использование записи

    /// Кладёт запись обратно в буфер и, если попросили, вставляет её
    /// в активное приложение.
    /// `destination` — куда вставлять. Раньше цели не было: панель
    /// не забирала клавиатуру, и активным оставалось то приложение,
    /// в котором работали. С клавиатурной навигацией панель фокус забирает,
    /// и ⌘V без возврата фокуса досталось бы нам же — той самой ошибке,
    /// на которой однажды сломалась вставка ответа модели.
    func use(_ entry: ClipboardEntry, into destination: NSRunningApplication? = nil) {
        // Своё же копирование историю пополнять не должно — иначе выбор
        // записи плодил бы её двойник и показывал плашку о копировании.
        PasteboardActivity.beQuiet(for: 1.0)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .text:
            pasteboard.setString(entry.text, forType: .string)
        case .files:
            let urls = entry.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else {
                DebugLog.write("буфер: файлов записи больше нет на диске")
                return
            }
            pasteboard.writeObjects(urls as [NSURL])
        case .image:
            guard let data = entry.data else { return }
            pasteboard.setData(data, forType: .png)
        }

        // Использованное становится самым свежим: в следующий раз искать
        // его будет незачем — оно наверху.
        store.touch(id: entry.id)
        reload()
        DebugLog.write("буфер: возвращено «\(entry.oneLine.prefix(40))»")

        guard settings.clipboardPastes else { return }
        ClipboardPaster.paste(into: destination)
    }

    func clear() {
        store.deleteAll()
        reload()
    }

    func delete(_ entry: ClipboardEntry) {
        store.delete(id: entry.id)
        reload()
    }

    /// Запись под номером горячей клавиши. Номера считаются от свежих.
    func entry(atSlot index: Int) -> ClipboardEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }
}

/// Вставка в чужое приложение.
///
/// Одно место на всех, кто вставляет: строка истории, ответ модели, запись
/// по цифре. Порядок здесь важнее самого нажатия и куплен отладкой —
/// см. `paste(into:)`.
enum ClipboardPaster {
    /// Задержка перед нажатием: приложению нужно мгновение, чтобы принять
    /// новое содержимое буфера, иначе вставляется прежнее.
    private static let delay: TimeInterval = 0.08

    /// Сколько ждать после переключения приложений.
    ///
    /// Переключение система делает не мгновенно, и нажатие, посланное раньше
    /// времени, достаётся ещё нам. Прежние 0,2 с отмерялись от `activate()`
    /// без деактивации — то есть от момента, когда переключения
    /// и не начиналось.
    private static let switchDelay: TimeInterval = 0.35

    /// Вставить туда, откуда пришли.
    ///
    /// `destination` пуст — вставляем туда, где фокус окажется сам: так
    /// работает вставка по цифре, когда панель фокуса не забирала.
    static func paste(into destination: NSRunningApplication? = nil) {
        guard let destination, !destination.isActive else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { press() }
            return
        }

        // Наше приложение перестаёт быть активным явно. `activate()` чужого
        // само этого не делает: агент без окон остаётся активным, и система
        // продолжает слать ему нажатия.
        NSApp.deactivate()
        destination.activate()
        DebugLog.write("буфер: вставка в \(destination.localizedName ?? "?")")
        DispatchQueue.main.asyncAfter(deadline: .now() + switchDelay) { press() }
    }

    /// Через `SyntheticKey`: вставку зовут клавишей — ⌃⌥1…9 или Enter
    /// в открытом списке, — и в этот миг клавиши человека ещё нажаты. Своё
    /// ⌘V, ушедшее поверх них, чужое приложение читает как ⌃⌥⌘V
    /// и не вставляет ничего.
    private static func press() {
        SyntheticKey.send(SyntheticKey.v, flags: .maskCommand)
    }
}
