import TrunookXPC
import AppKit
import AVFoundation
import ApplicationServices

/// Действие, доступное во время встречи.
enum MeetingAction: String, CaseIterable, Identifiable {
    case microphone
    case camera
    /// Куда система шлёт звук: динамики или наушники.
    case output
    /// Какой микрофон система слушает.
    case input
    /// Записать разговор и превратить его в заметку.
    case record
    case share
    case hand
    case copyLink
    case leave

    var id: String { rawValue }

    /// Действия, которые не ищутся на странице встречи.
    ///
    /// Они меняют устройство системы, а не состояние звонка, и потому есть
    /// всегда — как только встреча нашлась. Ровно так же устроена
    /// «Скопировать ссылку»: она берёт адрес вкладки, а не кнопку страницы.
    var isDevice: Bool { self == .output || self == .input }

    /// Действия, которые делает само приложение, а не страница встречи.
    ///
    /// Их не ищут в дереве браузера и они есть всегда, раз встреча идёт.
    /// `copyLink` сюда не входит: ссылка хоть и берётся из адреса вкладки,
    /// но без вкладки её нет вовсе — а запись и устройства живут
    /// независимо от того, что на странице.
    var isOwn: Bool { isDevice || self == .record }

    var title: String {
        switch self {
        case .microphone: return t("Микрофон")
        case .camera: return t("Камера")
        case .output: return t("Куда идёт звук")
        case .input: return t("Что слушает система")
        case .record: return t("Записать разговор")
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
        // Устройства не бывают включёнными или выключенными: у них
        // не состояние, а имя, и его показывает плашка под чёлкой.
        case .output: return "speaker.wave.2.fill"
        case .input: return "mic.and.signal.meter.fill"
        // Здесь `isOn` означает «идёт запись»: точка на кнопке — начать,
        // квадрат — закончить. Это единственное действие в ряду, где
        // состояние кнопки говорит о самом приложении, а не о встрече.
        case .record: return isOn ? "stop.circle.fill" : "record.circle"
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
        // Не кнопки страницы: ссылка берётся из адреса вкладки,
        // устройства — у звуковой подсистемы.
        case .copyLink, .output, .input, .record: return []
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
    private var timer: PowerAwareTimer?
    /// Приложение и окно встречи — чтобы не искать их заново на каждое нажатие.
    private var meetingApp: pid_t?
    private var meetingWindow: AXUIElement?
    private var meetingTabTitle: String?
    /// Откуда взялась встреча: вкладка, окно приложения или его меню.
    /// От этого зависит, где искать кнопку и как её нажимать.
    private var meetingSource: Source = .web

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

    /// Запущенные браузеры и приложения встреч — где вообще искать.
    ///
    /// Список держится здесь и обновляется по запуску и выходу приложений,
    /// а не собирается на каждом опросе: `runningApplications` с чтением
    /// `bundleIdentifier` — это обращения к LaunchServices, и раз в две
    /// секунды они стоили заметную долю всего обхода (`ENERGY.md`, О5).
    private var targets: [Target] = []

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        collectTargets()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
        }
        refresh()
        // Две секунды: встреча начинается и заканчивается не мгновенно,
        // а обход дерева страницы стоит заметно дороже сравнения точек.
        timer = PowerAwareTimer(every: 2, whenSaving: 10) { [weak self] in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Обнаружение

    /// Где искать встречу: процесс и то, что он такое.
    private struct Target {
        let pid: pid_t
        let bundleID: String
        /// Имя приложения — заголовок встречи, если у окна своего нет.
        let name: String
    }

    @objc private func appsChanged() {
        collectTargets()
    }

    private func collectTargets() {
        targets = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier,
                  Self.browserBundleIDs.contains(id) || MeetingApp.named(id) != nil
            else { return nil }
            return Target(pid: app.processIdentifier, bundleID: id, name: app.localizedName ?? "")
        }
    }

    /// Узлы площадок видеовстреч.
    private static let meetingHosts = [
        "telemost.yandex", "telemost.360",
        "meet.google.com",
        "zoom.us", "zoom.com",
        "teams.microsoft.com", "teams.live.com",
    ]

    /// Приложения встреч, которые ставят на компьютер: у них нет ни вкладки,
    /// ни адреса, и встреча ищется в их собственном окне.
    static let appBundleIDs = [
        "us.zoom.xos",
        "ru.yandex.desktop.telemost",
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

        let targets = self.targets
        scanQueue.async { [weak self] in
            let scan = Self.scan(targets)
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
        /// Откуда взялись кнопки. От этого зависит и как их нажимать:
        /// странице нужен фокус и пробел, родному окну и меню — само
        /// действие доступности.
        let source: Source
    }

    /// Обход дерева. Ни одного обращения к состоянию службы — только чтение
    /// чужих окон и разбор прочитанного.
    private static func scan(_ targets: [Target]) -> Scan? {
        guard let found = findMeeting(targets) else { return nil }

        let address = found.area.flatMap { AXTree.url(of: $0) }

        var states: [MeetingAction: Bool] = [:]
        var available: [MeetingAction] = []

        for action in MeetingAction.allCases {
            // Устройства звука к странице отношения не имеют: они есть
            // всегда, раз встреча идёт.
            if action.isOwn {
                available.append(action)
                continue
            }
            if action == .copyLink {
                if address != nil { available.append(action) }
                continue
            }
            guard let labels = control(action, of: found)?.labels else { continue }
            available.append(action)
            states[action] = isOn(labels: labels)
        }

        // Встреча считается найденной по кнопкам самой страницы. Свои две
        // кнопки в счёт не идут: иначе любая открытая вкладка сервиса — хоть
        // главная страница без звонка — выдавала бы себя за встречу.
        guard available.contains(where: { !$0.isOwn }) else { return nil }

        return Scan(
            pid: found.pid, window: found.window, tabTitle: found.tabTitle,
            url: address, states: states, available: available, source: found.source
        )
    }

    /// Орган управления действием и его нынешняя подпись.
    ///
    /// Одно место на три источника: обход и нажатие обязаны находить одно
    /// и то же. Порознь они однажды уже разошлись — вёрстка рисовала панель,
    /// а нажатия принимались в другом прямоугольнике.
    private static func control(
        _ action: MeetingAction, of found: Found
    ) -> (element: AXUIElement, labels: [String])? {
        switch found.source {
        case .web:
            guard let area = found.area else { return nil }
            return match(action, in: AXTree.buttons(of: area, maxDepth: 40))
        case .appButtons:
            let buttons = AXTree.buttons(of: found.window, maxDepth: windowDepth)
            return match(action, in: buttons, preferLargest: true)
        case let .appMenu(app):
            let titles = app.menuTitles(for: action)
            guard !titles.isEmpty else { return nil }
            let items = AXTree.menuItems(of: AXTree.application(pid: found.pid))
            // Подпись сверяется целиком: в меню Zoom рядом с «Выключить
            // звук» стоит «Выключить звук для всех».
            guard let item = items.first(where: { titles.contains($0.title.lowercased()) })
            else { return nil }
            return (item.element, [item.title])
        }
    }

    /// Прочитанное — в состояние службы. Только на главном потоке.
    private func apply(_ scan: Scan?) {
        guard let scan else {
            clear()
            return
        }

        // Не только на появлении: встреча переезжает из вкладки в приложение
        // и обратно, и молчаливая подмена читалась бы как «ничего
        // не происходит» — а управляем мы уже другим окном.
        if !isActive || meetingTabTitle != scan.tabTitle {
            let source: String
            switch scan.source {
            case .web: source = "вкладка"
            case .appButtons: source = "окно приложения"
            case let .appMenu(app): source = "меню \(app.bundleID)"
            }
            DebugLog.write("встреча: «\(scan.tabTitle)» (\(source)), кнопок — \(scan.available.count)")
        }

        meetingApp = scan.pid
        meetingWindow = scan.window
        meetingTabTitle = scan.tabTitle
        meetingSource = scan.source
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

    /// Откуда берутся органы управления встречей.
    ///
    /// Три места, а не два: у страницы кнопки в веб-области, у Телемоста —
    /// в самом окне, у Zoom их нет вовсе, и остаётся строка меню.
    enum Source: Equatable {
        case web
        case appButtons
        case appMenu(MeetingApp)
    }

    private struct Found {
        let pid: pid_t
        let window: AXUIElement
        let tabTitle: String
        /// Веб-область страницы. `nil` — встреча идёт в родном приложении.
        let area: AXUIElement?
        let source: Source
    }

    /// Сперва браузеры, потом свои приложения.
    ///
    /// Порядок не случаен: одна и та же встреча бывает открыта и вкладкой,
    /// и приложением — Телемост предлагает перейти в приложение прямо
    /// со страницы, — а у вкладки есть адрес, то есть работает и «скопировать
    /// ссылку». У окна приложения адреса нет вовсе.
    private static func findMeeting(_ targets: [Target]) -> Found? {
        findInBrowsers(targets) ?? findInApps(targets)
    }

    /// Веб-области окон браузеров с прошлого обхода.
    ///
    /// Поиск веб-области — спуск по дереву окна на десяток уровней, и раз
    /// в две секунды для каждого окна он был самой дорогой частью опроса.
    /// Заголовок окна — это заголовок открытой вкладки: пока он тот же,
    /// та же и вкладка, и достаточно прочитать адрес уже найденной области.
    /// Сменился заголовок или область перестала отвечать — ищем заново.
    ///
    /// Живёт только на `scanQueue`: обход и нажатие идут там же.
    private static var areaCache: [(window: AXUIElement, title: String, area: AXUIElement)] = []

    private static func findInBrowsers(_ targets: [Target]) -> Found? {
        var seen: [(window: AXUIElement, title: String, area: AXUIElement)] = []
        defer { areaCache = seen }

        for app in targets where browserBundleIDs.contains(app.bundleID) {
            let element = AXTree.application(pid: app.pid)
            for window in AXTree.windows(of: element) {
                let windowTitle = AXTree.string(window, kAXTitleAttribute) ?? ""
                let cached = areaCache.first { CFEqual($0.window, window) && $0.title == windowTitle }?.area
                var area = cached
                var address = area.flatMap { AXTree.url(of: $0) }
                if address == nil {
                    area = AXTree.webArea(in: window)
                    address = area.flatMap { AXTree.url(of: $0) }
                }
                guard let area else { continue }
                seen.append((window, windowTitle, area))
                // Открытая вкладка опознаётся по адресу, а не по заголовку:
                // главная страница Телемоста называется почти так же, как
                // сам звонок, и по названию их не различить.
                if let address, Self.isCallURL(address) {
                    return Found(
                        pid: app.pid, window: window,
                        tabTitle: windowTitle, area: area, source: .web
                    )
                }
            }
        }
        return nil
    }

    /// Встреча в своём окне Zoom или Телемоста.
    ///
    /// Признак — кнопка выхода: она есть только в звонке. По остальным
    /// кнопкам различить нельзя — «Демонстрация экрана» и «Микрофон» стоят
    /// и в главном окне Zoom, и в его настройках, а главное окно Телемоста
    /// показывает «Новую встречу» ровно теми же кнопками.
    private static func findInApps(_ targets: [Target]) -> Found? {
        for running in targets {
            guard let app = MeetingApp.named(running.bundleID) else { continue }
            let element = AXTree.application(pid: running.pid)
            let name = running.name

            for window in AXTree.windows(of: element) {
                let title = AXTree.string(window, kAXTitleAttribute) ?? name
                switch app.controls {
                case .windowButtons:
                    // Признак — кнопка выхода: она есть только в звонке.
                    // По остальным различить нельзя — «Демонстрация экрана»
                    // и «Микрофон» стоят и в главном окне, и в настройках.
                    let buttons = AXTree.buttons(of: window, maxDepth: windowDepth)
                    guard match(.leave, in: buttons, preferLargest: true) != nil else { continue }
                    return Found(
                        pid: running.pid, window: window,
                        tabTitle: title.isEmpty ? name : title, area: nil, source: .appButtons
                    )
                case .menu:
                    // Признак — само окно звонка: пункты меню конференции
                    // стоят в строке и до звонка, просто недоступные.
                    guard app.isMeetingWindow(title: title) else { continue }
                    return Found(
                        pid: running.pid, window: window,
                        tabTitle: title, area: nil, source: .appMenu(app)
                    )
                }
            }
        }
        return nil
    }

    /// Насколько глубоко идём по окну приложения.
    ///
    /// Меньше, чем по веб-странице: у родного окна кнопки лежат близко
    /// к корню — у Телемоста на шестом уровне, — а каждый лишний уровень
    /// это тысячи узлов и обход в минуты. Опрос идёт каждые две секунды,
    /// и платить за него столько нельзя.
    private static let windowDepth = 12

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
        if action.isDevice {
            switchDevice(action)
            return
        }
        // Запись ведёт не встреча: у службы встречи нет ни доступа
        // к звуку, ни права его заводить. Кнопку обрабатывает сама панель.
        if action == .record { return }
        if action == .copyLink {
            guard let url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            DebugLog.write("встреча: ссылка скопирована")
            onCopiedLink?(url)
            return
        }

        guard let pid = meetingApp, let window = meetingWindow else { return }
        let found = Found(
            pid: pid, window: window, tabTitle: meetingTabTitle ?? "",
            area: nil, source: meetingSource
        )
        // Кнопку ещё надо найти, а это тот же обход дерева, что и у опроса,
        // и на главном потоке ему так же не место: вырез замирал бы ровно
        // в тот момент, когда человек по нему нажал.
        scanQueue.async { [weak self] in
            Self.pressButton(action, of: found)
            // Подпись кнопки меняется не мгновенно: странице нужно мгновение
            // на обработку, и опрос раньше времени прочитал бы прежнее.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
    }

    // MARK: - Устройства звука

    /// Имя нынешнего устройства для подписи под чёлкой.
    ///
    /// Подпись, а не состояние кнопки: у устройства нет «включено» и
    /// «выключено», у него есть имя, и другого способа показать выбранное
    /// в круглой кнопке нет. Читается заново на каждое наведение —
    /// устройство меняют и мимо приложения, из системной панели звука.
    func deviceName(for action: MeetingAction) -> String? {
        switch action {
        case .output: return AudioDevices.defaultOutput?.name
        case .input: return AudioDevices.defaultInput?.name
        default: return nil
        }
    }

    /// Следующее устройство по кругу.
    ///
    /// Список читается в момент нажатия, а не хранится: наушники втыкают
    /// и вынимают посреди встречи, и сохранённый список отправил бы звук
    /// в то, чего уже нет.
    private func switchDevice(_ action: MeetingAction) {
        let devices = action == .output ? AudioDevices.outputs() : AudioDevices.inputs()
        let current = action == .output ? AudioDevices.defaultOutput : AudioDevices.defaultInput
        guard let next = AudioDevices.next(after: current, in: devices) else {
            DebugLog.write("встреча: устройств для «\(action.title)» нет")
            return
        }
        if action == .output {
            AudioDevices.setDefaultOutput(next)
        } else {
            AudioDevices.setDefaultInput(next)
        }
        // Подпись под чёлкой читает имя сама, но перерисовать её надо:
        // без этого человек нажал, звук уехал, а в плашке прежнее имя.
        objectWillChange.send()
    }

    /// Действие на открытой вкладке или в окне приложения — без переключений.
    /// Только обход и нажатие, без обращений к состоянию службы: идёт
    /// в стороне от главного потока.
    ///
    /// Способа два, и это не перестраховка. Страница действие доступности
    /// не слышит вовсе — веб-приложение слушает указатель, — и ей нужен фокус
    /// с пробелом. Родное окно, наоборот, живёт по правилам AppKit и Qt:
    /// `AXPress` у него настоящий, а вот фокуса у кнопки в панели звонка
    /// может не быть вовсе, и пробел тогда уйдёт в никуда.
    @discardableResult
    private static func pressButton(_ action: MeetingAction, of found: Found) -> Bool {
        // Веб-область ищется здесь заново: между обходом и нажатием человек
        // мог сменить вкладку, а хранить элемент страницы дольше одного
        // обхода нельзя — он живёт в чужом процессе.
        let target = found.source == .web
            ? Found(
                pid: found.pid, window: found.window, tabTitle: found.tabTitle,
                area: AXTree.webArea(in: found.window), source: .web
            )
            : found
        guard let control = control(action, of: target) else {
            DebugLog.write("встреча: кнопка «\(action.title)» не найдена")
            return false
        }

        // 49 — пробел. Странице действие доступности не слышно вовсе,
        // и ей нужен фокус с пробелом; у родного окна и меню `AXPress`
        // настоящий, а фокуса у кнопки панели звонка может не быть.
        let pressed: Bool
        switch target.source {
        case .web:
            pressed = AXTree.focusAndKey(control.element, pid: target.pid, keyCode: 49)
        case .appButtons, .appMenu:
            pressed = AXTree.press(control.element)
                || AXTree.focusAndKey(control.element, pid: target.pid, keyCode: 49)
        }
        DebugLog.write("встреча: \(action.title) — \(pressed ? "нажато" : "не удалось")")
        return pressed
    }

    // MARK: - Сопоставление

    private static func match(
        _ action: MeetingAction,
        in buttons: [(element: AXUIElement, labels: [String])],
        preferLargest: Bool = false
    ) -> (element: AXUIElement, labels: [String])? {
        let matches = buttons.filter { button in
            let joined = button.labels.joined(separator: " ").lowercased()
            return action.labels.contains { joined.contains($0) }
        }
        guard preferLargest else { return matches.first }
        // В родном окне одна и та же подпись висит на двух элементах сразу:
        // у Телемоста «Включить микрофон» — и кнопка панели 48×48, и значок
        // состояния 16×16 в плитке участника. Первый в обходе — как раз
        // значок, и нажатие уходило бы в него.
        return matches.max { left, right in
            area(of: left.element) < area(of: right.element)
        } ?? matches.first
    }

    private static func area(of element: AXUIElement) -> CGFloat {
        AXTree.frame(of: element).map { $0.width * $0.height } ?? 0
    }

    /// Не `private`: по этому правилу читается состояние всех трёх
    /// источников сразу, и проверяется оно тестом на подписях, снятых
    /// с живых звонков Телемоста и Zoom.
    static func isOn(labels: [String]) -> Bool {
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
            // Тем же путём, каким кнопка и нажимается: одно место расчёта
            // на обход, нажатие и пробу.
            let found = Found(
                pid: pid, window: window, tabTitle: "",
                area: meetingSource == .web ? AXTree.webArea(in: window) : nil,
                source: meetingSource
            )
            if let control = Self.control(action, of: found) {
                return control.labels.first
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

    /// Печатает окна, кнопки и меню Zoom и Телемоста.
    ///
    /// Разведка перед тем, как писать таблицу подписей: у родных приложений
    /// подписи свои, и взять их неоткуда, кроме живого звонка. Вне встречи
    /// вывод почти пуст — это тоже ответ.
    func dumpApps() {
        guard AXTree.isTrusted else {
            DebugLog.write("встреча: нет Универсального доступа")
            return
        }
        let apps = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.appBundleIDs.contains(id)
        }
        guard !apps.isEmpty else {
            DebugLog.write("встреча: ни Zoom, ни Телемост не запущены")
            return
        }
        for app in apps {
            AXTree.dumpApp(
                pid: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "?"
            )
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
