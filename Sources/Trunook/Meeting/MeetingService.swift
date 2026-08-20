import TrunookXPC
import AppKit
import AVFoundation
import ApplicationServices

/// Действие, доступное во время встречи.
enum MeetingAction: String, CaseIterable, Identifiable {
    case microphone
    case camera
    case share
    case hand
    case copyLink
    case leave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return t("Микрофон")
        case .camera: return t("Камера")
        case .share: return t("Демонстрация")
        case .hand: return t("Поднять руку")
        case .copyLink: return t("Скопировать ссылку")
        case .leave: return t("Выйти")
        }
    }

    /// Значок для включённого и выключенного состояния.
    func symbol(isOn: Bool) -> String {
        switch self {
        case .microphone: return isOn ? "mic.fill" : "mic.slash.fill"
        case .camera: return isOn ? "video.fill" : "video.slash.fill"
        case .share: return isOn ? "rectangle.inset.filled.on.rectangle" : "rectangle.on.rectangle"
        case .hand: return isOn ? "hand.raised.fill" : "hand.raised"
        case .copyLink: return "link"
        case .leave: return "phone.down.fill"
        }
    }

    /// Подписи кнопок на странице встречи.
    ///
    /// Сравнение идёт по вхождению подстроки в нижнем регистре, поэтому
    /// достаточно опорных слов, а не точных фраз. Список расширяемый: если
    /// сервис поменяет формулировки, правится таблица, а не логика.
    var labels: [String] {
        switch self {
        case .microphone: return ["микрофон", "microphone", "mute", "unmute", "звук"]
        case .camera: return ["камер", "camera", "video", "видео"]
        case .share: return ["демонстрац", "поделит", "share", "present"]
        case .hand: return ["руку", "рука", "hand", "raise"]
        // Не кнопка страницы: ссылка берётся из адреса вкладки.
        case .copyLink: return []
        case .leave: return ["выйти", "покинуть", "завершить", "leave", "end call", "hang up"]
        }
    }

    /// Слова, означающие, что действие сейчас выключено.
    ///
    /// Подпись кнопки описывает то, что произойдёт по нажатию: «Включить
    /// микрофон» значит, что он сейчас выключен. Отсюда и инверсия.
    ///
    /// Слова сняты с живой встречи Телемоста: «Выключить микрофон»,
    /// «Начать демонстрацию экрана», «Поднять руку». Обрати внимание, что
    /// «выключить» не содержит «включить» как подстроку — из-за «ы» между
    /// «в» и «к», — поэтому ложного срабатывания нет.
    static let offWords = [
        "включить", "unmute", "turn on", "enable",
        "начать", "start",
        "поднять", "raise",
    ]
}

/// Отслеживает активную встречу и управляет ею.
final class MeetingService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var title: String?
    /// Состояние кнопок: включено ли действие прямо сейчас.
    @Published private(set) var states: [MeetingAction: Bool] = [:]
    @Published private(set) var availableActions: [MeetingAction] = []

    /// Адрес встречи — для кнопки копирования.
    private(set) var url: URL?
    /// Сообщает наружу, что ссылка скопирована: плашку показывает вырез.
    var onCopiedLink: ((URL) -> Void)?

    private let settings: Settings
    private var timer: Timer?
    /// Приложение и окно встречи — чтобы не искать их заново на каждое нажатие.
    private var meetingApp: pid_t?
    private var meetingWindow: AXUIElement?
    private var meetingTabTitle: String?

    /// Обход дерева идёт здесь и только здесь.
    ///
    /// На главном потоке ему не место: каждый шаг обхода — обращение
    /// к чужому процессу, а шагов тысячи. С тяжёлой страницей в браузере
    /// приложение вставало насмерть прямо на запуске — обход начинался
    /// из `start()`, и до значка в строке состояния дело не доходило.
    private let scanQueue = DispatchQueue(label: "com.trunook.meeting", qos: .utility)

    /// Обход уже идёт: тик опроса пропускаем. Иначе очередь копила бы обходы,
    /// каждый из которых бывает дольше периода опроса.
    private var isScanning = false

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        refresh()
        // Две секунды: встреча начинается и заканчивается не мгновенно,
        // а обход дерева страницы стоит заметно дороже сравнения точек.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Обнаружение

    /// Узлы площадок видеовстреч.
    private static let meetingHosts = [
        "telemost.yandex", "telemost.360",
        "meet.google.com",
        "zoom.us", "zoom.com",
        "teams.microsoft.com", "teams.live.com",
    ]

    /// Браузеры, в которых может идти встреча.
    private static let browserBundleIDs = [
        "ru.yandex.desktop.yandex-browser",
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
    ]

    func refresh() {
        guard settings.meetingControlsEnabled, AXTree.isTrusted else {
            clear()
            return
        }
        guard !isScanning else { return }
        isScanning = true

        scanQueue.async { [weak self] in
            let scan = Self.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                self.apply(scan)
            }
        }
    }

    /// Всё, что удалось прочитать со страницы за один обход.
    ///
    /// Значением, а не записью прямо в поля службы: обход идёт в стороне
    /// от главного потока, а состояние службы остаётся его собственностью —
    /// иначе `perform` читал бы окно встречи, пока обход его переписывает.
    private struct Scan {
        let pid: pid_t
        let window: AXUIElement
        let tabTitle: String
        let url: URL?
        let states: [MeetingAction: Bool]
        let available: [MeetingAction]
    }

    /// Обход дерева. Ни одного обращения к состоянию службы — только чтение
    /// чужих окон и разбор прочитанного.
    private static func scan() -> Scan? {
        guard let found = findMeeting(), let area = AXTree.webArea(in: found.window) else {
            return nil
        }

        let buttons = AXTree.buttons(of: area, maxDepth: 40)
        let address = AXTree.url(of: area)

        var states: [MeetingAction: Bool] = [:]
        var available: [MeetingAction] = []

        for action in MeetingAction.allCases {
            if action == .copyLink {
                if address != nil { available.append(action) }
                continue
            }
            guard let match = match(action, in: buttons) else { continue }
            available.append(action)
            states[action] = isOn(labels: match.labels)
        }

        return Scan(
            pid: found.pid, window: found.window, tabTitle: found.tabTitle,
            url: address, states: states, available: available
        )
    }

    /// Прочитанное — в состояние службы. Только на главном потоке.
    private func apply(_ scan: Scan?) {
        guard let scan else {
            clear()
            return
        }

        if !isActive {
            DebugLog.write("встреча: «\(scan.tabTitle)», кнопок — \(scan.available.count)")
        }

        meetingApp = scan.pid
        meetingWindow = scan.window
        meetingTabTitle = scan.tabTitle
        url = scan.url
        title = scan.tabTitle
        states = scan.states
        availableActions = scan.available
        isActive = !scan.available.isEmpty
    }

    private func clear() {
        guard isActive || title != nil else { return }
        DebugLog.write("встреча: не найдена")
        isActive = false
        title = nil
        states = [:]
        availableActions = []
        meetingApp = nil
        meetingWindow = nil
        meetingTabTitle = nil
        url = nil
    }

    private struct Found {
        let pid: pid_t
        let window: AXUIElement
        let tabTitle: String
    }

    private static func findMeeting() -> Found? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.browserBundleIDs.contains(id)
        }

        for app in apps {
            let element = AXTree.application(pid: app.processIdentifier)
            for window in AXTree.windows(of: element) {
                // Открытая вкладка опознаётся по адресу, а не по заголовку:
                // главная страница Телемоста называется почти так же, как
                // сам звонок, и по названию их не различить.
                if let area = AXTree.webArea(in: window),
                   let address = AXTree.url(of: area),
                   Self.isCallURL(address) {
                    let windowTitle = AXTree.string(window, kAXTitleAttribute) ?? ""
                    return Found(
                        pid: app.processIdentifier, window: window,
                        tabTitle: windowTitle
                    )
                }
            }
        }
        return nil
    }

    /// Похож ли адрес на идущий звонок, а не на страницу сервиса.
    ///
    /// У всех площадок звонок отличается непустым путём: `/j/1234…`
    /// у Телемоста и Zoom, код встречи у Meet. Главная всегда «/».
    private static func isCallURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard meetingHosts.contains(where: { host.contains($0) }) else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).count > 2
    }

    // MARK: - Управление

    func perform(_ action: MeetingAction) {
        if action == .copyLink {
            guard let url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            DebugLog.write("встреча: ссылка скопирована")
            onCopiedLink?(url)
            return
        }

        guard let pid = meetingApp, let window = meetingWindow else { return }
        // Кнопку ещё надо найти, а это тот же обход дерева, что и у опроса,
        // и на главном потоке ему так же не место: вырез замирал бы ровно
        // в тот момент, когда человек по нему нажал.
        scanQueue.async { [weak self] in
            Self.pressButton(action, pid: pid, window: window)
            // Подпись кнопки меняется не мгновенно: странице нужно мгновение
            // на обработку, и опрос раньше времени прочитал бы прежнее.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
    }

    /// Действие на открытой вкладке — без переключений. Только обход и нажатие,
    /// без обращений к состоянию службы: идёт в стороне от главного потока.
    @discardableResult
    private static func pressButton(_ action: MeetingAction, pid: pid_t, window: AXUIElement) -> Bool {
        guard let area = AXTree.webArea(in: window),
              let match = match(action, in: AXTree.buttons(of: area, maxDepth: 40))
        else {
            DebugLog.write("встреча: кнопка «\(action.title)» не найдена")
            return false
        }

        // 49 — пробел.
        let pressed = AXTree.focusAndKey(match.element, pid: pid, keyCode: 49)
        DebugLog.write("встреча: \(action.title) — \(pressed ? "нажато" : "не удалось")")
        return pressed
    }

    // MARK: - Сопоставление

    private static func match(
        _ action: MeetingAction,
        in buttons: [(element: AXUIElement, labels: [String])]
    ) -> (element: AXUIElement, labels: [String])? {
        buttons.first { button in
            let joined = button.labels.joined(separator: " ").lowercased()
            return action.labels.contains { joined.contains($0) }
        }
    }

    private static func isOn(labels: [String]) -> Bool {
        let joined = labels.joined(separator: " ").lowercased()
        // Подпись описывает будущее действие: «Включить микрофон» — значит
        // сейчас выключен.
        return !MeetingAction.offWords.contains { joined.contains($0) }
    }

    /// Проверяет, доходит ли нажатие до страницы: читает подпись кнопки,
    /// жмёт её и читает снова. Если подпись не изменилась — `AXPress`
    /// отработал формально, а обработчик страницы его не услышал.
    func probePress(_ action: MeetingAction) {
        guard let label = currentLabel(of: action) else {
            DebugLog.write("проба: кнопка «\(action.title)» не найдена")
            return
        }
        DebugLog.write("проба: до нажатия — «\(label)»")
        perform(action)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let after = self.currentLabel(of: action) ?? "?"
            DebugLog.write("проба: после нажатия — «\(after)»")
            DebugLog.write(after == label
                           ? "проба: подпись не изменилась — страница нажатие не приняла"
                           : "проба: подпись изменилась — нажатие сработало")
        }
    }

    private func currentLabel(of action: MeetingAction) -> String? {
        guard let pid = meetingApp else { return nil }
        let element = AXTree.application(pid: pid)
        for window in AXTree.windows(of: element) {
            guard let area = AXTree.webArea(in: window) else { continue }
            let buttons = AXTree.buttons(of: area, maxDepth: 40)
            if let match = Self.match(action, in: buttons) {
                return match.labels.first
            }
        }
        return nil
    }

    // MARK: - Разведка

    /// Печатает кнопки всех окон браузеров — по этому выводу и калибруются
    /// подписи в `MeetingAction.labels`.
    func dumpButtons() {
        guard AXTree.isTrusted else {
            DebugLog.write("встреча: нет Универсального доступа")
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.browserBundleIDs.contains(id)
        }
        guard !apps.isEmpty else {
            DebugLog.write("встреча: браузеров не запущено")
            return
        }

        for app in apps {
            let element = AXTree.application(pid: app.processIdentifier)
            for window in AXTree.windows(of: element) {
                let title = AXTree.string(window, kAXTitleAttribute) ?? "без заголовка"
                let areas = AXTree.webAreas(in: window)
                DebugLog.write("окно «\(title)»: веб-областей \(areas.count)")
                for area in areas {
                    let address = AXTree.url(of: area)?.absoluteString ?? "адрес не прочитан"
                    let count = AXTree.buttons(of: area, maxDepth: 40).count
                    DebugLog.write("    \(address) — кнопок \(count)")
                }
            }
        }
    }

    /// Занят ли микрофон — запасной признак встречи, не зависящий от площадки.
    static var isMicrophoneBusy: Bool {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices.contains { $0.isInUseByAnotherApplication }
    }
}
