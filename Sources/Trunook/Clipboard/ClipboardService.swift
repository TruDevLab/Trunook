import TrunookXPC
import AppKit

/// История буфера обмена: наблюдение, хранение и возврат записи обратно.
final class ClipboardService: ObservableObject {
    /// Свежие записи, самая новая первой.
    @Published private(set) var entries: [ClipboardEntry] = []

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
    }

    private func prune() {
        store.prune(lifetime: settings.clipboardLifetime, limit: settings.clipboardLimit)
    }

    // MARK: - Использование записи

    /// Кладёт запись обратно в буфер и, если попросили, вставляет её
    /// в активное приложение.
    func use(_ entry: ClipboardEntry) {
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
        // Панель не забирает фокус, поэтому активным остаётся то приложение,
        // в котором человек работал, — вставка уходит туда.
        ClipboardPaster.paste()
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

/// Вставка в активное приложение.
enum ClipboardPaster {
    /// Задержка перед нажатием: приложению нужно мгновение, чтобы принять
    /// новое содержимое буфера, иначе вставляется прежнее.
    private static let delay: TimeInterval = 0.08

    static func paste() {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyV: CGKeyCode = 9

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
            else { return }

            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
