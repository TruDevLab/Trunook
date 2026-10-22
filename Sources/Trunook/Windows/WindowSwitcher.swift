import TrunookXPC
import AppKit
import ApplicationServices
import CoreGraphics

/// Каким модификатором держат переключатель: ⌘Tab вместо системного
/// или ⌥Tab рядом с ним.
enum SwitcherTrigger: String, CaseIterable, Identifiable {
    case command
    case option

    var id: String { rawValue }

    var flag: CGEventFlags {
        switch self {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        }
    }

    var title: String {
        switch self {
        case .command: return "⌘Tab"
        case .option: return "⌥Tab"
        }
    }
}

/// Что делать с клавишей, пока переключатель открыт или вот-вот откроется.
///
/// Решение — чистая функция от кода клавиши и флагов: перехватчик зовёт её
/// на каждое нажатие во всей системе, и ничего тяжелее сравнения чисел
/// там быть не должно.
enum SwitcherKey: Equatable {
    /// Первое нажатие Tab с модификатором — открыть и сделать шаг.
    case open(step: Int)
    /// Tab, ⇧Tab, стрелки вбок — шаг по ряду.
    case step(Int)
    /// ↓ — к вкладкам, ↑ — обратно к окнам.
    case tabs(Bool)
    case commit
    case cancel
    /// Открыт — чужому приложению не отдаём ничего.
    case swallow
    /// Переключатель считается открытым, а модификатор уже не держат:
    /// отпускание прошло мимо. Выбор делается, нажатие уходит, куда шло, —
    /// иначе клавиатура осталась бы проглоченной.
    case lost
    case pass

    static let tab: Int64 = 48
    static let escape: Int64 = 53
    static let enter: Int64 = 36
    static let keypadEnter: Int64 = 76
    static let left: Int64 = 123
    static let right: Int64 = 124
    static let down: Int64 = 125
    static let up: Int64 = 126

    /// Нажатие клавиши.
    static func keyDown(_ keyCode: Int64, flags: CGEventFlags, isOpen: Bool, trigger: SwitcherTrigger) -> SwitcherKey {
        if keyCode == tab, flags.contains(trigger.flag) {
            // Лишний модификатор — чужое сочетание: ⌃Tab листает вкладки
            // в браузере, ⌘⌥Tab кто-то назначил себе. Не трогаем.
            let others: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
            let extra = others.subtracting(trigger.flag)
            if !flags.intersection(extra).isEmpty { return isOpen ? .swallow : .pass }
            let step = flags.contains(.maskShift) ? -1 : 1
            return isOpen ? .step(step) : .open(step: step)
        }
        guard isOpen else { return .pass }
        guard flags.contains(trigger.flag) else { return .lost }
        switch keyCode {
        case left: return .step(-1)
        case right: return .step(1)
        case down: return .tabs(true)
        case up: return .tabs(false)
        case escape: return .cancel
        case enter, keypadEnter: return .commit
        default: return .swallow
        }
    }

    /// Сменились модификаторы: отпустили держащий — выбор сделан.
    static func flagsChanged(_ flags: CGEventFlags, isOpen: Bool, trigger: SwitcherTrigger) -> SwitcherKey {
        guard isOpen, !flags.contains(trigger.flag) else { return .pass }
        return .commit
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Вкладка браузера.
struct BrowserTab: Equatable, Identifiable {
    /// Номер с единицы — так его считает AppleScript.
    let index: Int
    let title: String
    var id: Int { index }
}

/// Вкладки одного окна браузера.
enum SwitcherTabs: Equatable {
    /// Не браузер — вкладок нет и не будет.
    case none
    case loading
    /// Система ещё не спрашивала, можно ли управлять браузером.
    case needsConsent
    /// Человек отказал в «Автоматизации».
    case denied
    /// Окно браузера, у которого вкладок не нашлось: окно настроек, загрузок.
    case unavailable
    case loaded(windowID: String, tabs: [BrowserTab], active: Int)

    var tabs: [BrowserTab] {
        if case let .loaded(_, tabs, _) = self { return tabs }
        return []
    }
}

/// Строка переключателя: окно, свёрнутое окно или приложение без окон.
struct SwitcherItem: Identifiable {
    enum Kind: Hashable {
        case window
        case minimized
        /// Окон на этом столе нет — переключиться можно только на приложение.
        case app
    }

    let id: String
    let kind: Kind
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let title: String
    let element: AXUIElement?
    /// Номер окна у сервера окон — по нему снимается миниатюра. У свёрнутых
    /// и у приложений без окон его нет: снимать нечего.
    var windowNumber: CGWindowID? = nil
    var tabs: SwitcherTabs = .none
}

/// Порядок и подсветка — то, что проверяется тестом.
enum SwitcherOrder {
    /// С какой строки начинать. Первая строка — окно, в котором работают
    /// сейчас: переключаться на него незачем, и одно нажатие ⌘Tab, как
    /// и у системы, ведёт к предыдущему окну.
    static func start(count: Int, firstIsFrontmost: Bool) -> Int {
        guard count > 1, firstIsFrontmost else { return 0 }
        return 1
    }

    /// Шаг по кругу: с последней на первую и обратно.
    static func move(_ index: Int, by step: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + step) % count + count) % count
    }

    /// Подсветка, когда список пришёл позже нажатий.
    ///
    /// `firstStep` — шаг самого открытия: ⌘Tab ведёт к начальной строке,
    /// ⇧⌘Tab — назад от текущего окна, то есть к последней. `steps` — сумма
    /// всех шагов, включая первый.
    static func selection(firstStep: Int, steps: Int, count: Int, firstIsFrontmost: Bool) -> Int {
        guard firstStep > 0 else { return move(0, by: steps, count: count) }
        return move(start(count: count, firstIsFrontmost: firstIsFrontmost), by: steps - 1, count: count)
    }
}

/// Окна и приложения для переключателя — снимок на момент открытия.
///
/// Порядок окон — из списка CoreGraphics: он отдаёт окна текущего стола
/// в порядке наложения, то есть от последнего, в котором работали.
/// Заголовок и сам элемент для подъёма окна — из Универсального доступа,
/// окно ищется по совпадению рамки, как у выбора второго окна.
///
/// Свёрнутые окна список CoreGraphics не отдаёт — они берутся у самих
/// приложений. Приложения без окон на этом столе (скрытые, с окнами
/// на другом столе, во весь экран) идут в конце: системный ⌘Tab их
/// показывает, и, заменив его, терять их нельзя.
///
/// Зовётся не с главного потока: Универсальный доступ спрашивает каждое
/// приложение, и зависшее ответит только по таймауту.
enum SwitcherWindows {
    static func collect() -> [SwitcherItem] {
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own
        }
        let byPid = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        var windowsByApp: [pid_t: [AXUIElement]] = [:]
        func windows(_ pid: pid_t) -> [AXUIElement] {
            if let known = windowsByApp[pid] { return known }
            let found = DraggedWindow.windows(ofApp: pid)
            windowsByApp[pid] = found
            return found
        }

        var items: [SwitcherItem] = []
        var listed: [AXUIElement] = []
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = byPid[pid],
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width >= 100, bounds.height >= 60,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0
            else { continue }
            // Рамка не совпала ни с одним окном Универсального доступа —
            // окно не поднять, только приложение целиком. Терять его
            // не будем: ставим приложением, один раз.
            let element = windows(pid).first { matches($0, bounds) }
            if let element {
                listed.append(element)
            } else if items.contains(where: { $0.pid == pid }) {
                continue
            }
            let title = element.flatMap(DraggedWindow.title(of:)) ?? ""
            let name = app.localizedName ?? ""
            items.append(SwitcherItem(
                id: "w\(number)",
                kind: element == nil ? .app : .window,
                pid: pid,
                bundleID: app.bundleIdentifier,
                appName: name,
                title: title.isEmpty ? name : title,
                element: element,
                windowNumber: number
            ))
        }

        // Свёрнутые — после видимых, в порядке приложений.
        for app in apps {
            let pid = app.processIdentifier
            for (index, element) in windows(pid).enumerated() where isMinimized(element) {
                guard !listed.contains(where: { CFEqual($0, element) }) else { continue }
                let title = DraggedWindow.title(of: element) ?? ""
                let name = app.localizedName ?? ""
                items.append(SwitcherItem(
                    id: "m\(pid)-\(index)",
                    kind: .minimized,
                    pid: pid,
                    bundleID: app.bundleIdentifier,
                    appName: name,
                    title: title.isEmpty ? name : title,
                    element: element
                ))
            }
        }

        // Приложения, которых в списке ещё нет совсем.
        let present = Set(items.map(\.pid))
        for app in apps where !present.contains(app.processIdentifier) {
            let name = app.localizedName ?? ""
            items.append(SwitcherItem(
                id: "a\(app.processIdentifier)",
                kind: .app,
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                appName: name,
                title: name,
                element: nil
            ))
        }
        return items
    }

    private static func matches(_ element: AXUIElement, _ bounds: CGRect) -> Bool {
        guard let position = DraggedWindow.position(of: element), let size = DraggedWindow.size(of: element) else {
            return false
        }
        return abs(position.x - bounds.minX) <= 2 && abs(position.y - bounds.minY) <= 2
            && abs(size.width - bounds.width) <= 2 && abs(size.height - bounds.height) <= 2
    }

    static func isMinimized(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success else {
            return false
        }
        return (value as? Bool) == true
    }

    /// Перейти к выбранному: развернуть, если свёрнуто, показать скрытое
    /// приложение и поднять окно.
    ///
    /// Окно поднимается Универсальным доступом, как у выбора второго окна:
    /// `NSRunningApplication.activate` фоновому приложению система с macOS 14
    /// молча отказывает. Приложение без окна делается передним тем же путём.
    static func activate(_ item: SwitcherItem) {
        let app = NSRunningApplication(processIdentifier: item.pid)
        if app?.isHidden == true { app?.unhide() }
        guard let element = item.element else {
            let axApp = AXUIElementCreateApplication(item.pid)
            AXUIElementSetMessagingTimeout(axApp, 0.2)
            let result = AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if result != .success { app?.activate() }
            return
        }
        if item.kind == .minimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        DraggedWindow.raise(element)
    }
}

/// Переключатель окон и вкладок в вырезе.
///
/// Живёт от первого ⌘Tab до отпускания ⌘: перехватчик клавиш шлёт сюда
/// шаги, выбор и отмену, а сам решает только, глотать ли нажатие. Список
/// собирается в фоне — чужие приложения отвечают не мгновенно, — и шаги,
/// пришедшие раньше него, копятся и применяются, когда он готов.
///
/// Вырез показывается не сразу, а через долю секунды: быстрое ⌘Tab
/// просто переключает на предыдущее окно, как у системы, и панель
/// не мигает на каждом переключении.
final class WindowSwitcher: ObservableObject {
    static let shared = WindowSwitcher()

    @Published private(set) var items: [SwitcherItem] = []
    @Published private(set) var selected = 0
    /// Подсветка в ряду вкладок, а не окон.
    @Published private(set) var inTabs = false
    @Published private(set) var selectedTab = 0
    /// Значки по процессам — с главного потока, один раз на открытие.
    @Published private(set) var icons: [pid_t: NSImage] = [:]
    /// Миниатюры по номеру окна. Живут между открытиями: на следующем ⌘Tab
    /// прежний снимок виден сразу, пока снимается свежий.
    @Published private(set) var thumbnails: [CGWindowID: NSImage] = [:]

    /// Переключатель держат: от первого Tab до отпускания или отмены.
    private(set) var isActive = false
    /// Панель в вырезе показана.
    private(set) var isShown = false

    /// Показать панель — накладкой в вырезе.
    var onShow: () -> Void = {}
    /// Убрать панель.
    var onHide: () -> Void = {}
    /// Сессия кончилась — выбором или отменой. Перехватчик перестаёт глотать.
    var onEnd: () -> Void = {}

    /// Вкладки браузеров спрашивать.
    var tabsEnabled: () -> Bool = { true }
    /// Миниатюры снимать.
    var thumbnailsEnabled: () -> Bool = { true }
    /// В этот заход миниатюры уже снимались.
    private var thumbnailsTaken = false

    private var firstStep = 1
    private var pendingSteps = 0
    private var commitWhenReady = false
    private var generation = 0
    private let queue = DispatchQueue(label: "com.trunook.switcher", qos: .userInteractive)
    /// Через сколько показывать панель, если ⌘ всё ещё держат.
    static let showDelay: TimeInterval = 0.12

    var current: SwitcherItem? { items.indices.contains(selected) ? items[selected] : nil }

    // MARK: - Сессия

    func begin(step: Int) {
        guard !isActive else { return move(step) }
        isActive = true
        generation += 1
        let session = generation
        firstStep = step
        pendingSteps = step
        thumbnailsTaken = false
        commitWhenReady = false
        inTabs = false
        selectedTab = 0
        items = []
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        DebugLog.write("переключатель: открыт")
        queue.async { [weak self] in
            let collected = SwitcherWindows.collect()
            DispatchQueue.main.async { self?.loaded(collected, frontmost: frontmost, session: session) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay) { [weak self] in
            guard let self, self.isActive, self.generation == session else { return }
            self.show()
        }
    }

    private func loaded(_ collected: [SwitcherItem], frontmost: pid_t?, session: Int) {
        guard isActive, generation == session else { return }
        var icons: [pid_t: NSImage] = [:]
        for item in collected where icons[item.pid] == nil {
            icons[item.pid] = NSRunningApplication(processIdentifier: item.pid)?.icon
        }
        self.icons = icons
        var list = collected
        let tabs = tabsEnabled()
        for index in list.indices where list[index].kind != .app {
            if tabs, let bundleID = list[index].bundleID, BrowserTabs.family(of: bundleID) != nil {
                list[index].tabs = .loading
            }
        }
        items = list
        selected = SwitcherOrder.selection(firstStep: firstStep, steps: pendingSteps, count: list.count,
                                           firstIsFrontmost: list.first?.pid == frontmost)
        pendingSteps = 0
        DebugLog.write("переключатель: \(list.count) строк, подсвечена \(selected)")
        if tabs { loadTabs(session: session) }
        // Окна, которых больше нет, из запаса снимков уходят.
        let numbers = Set(list.compactMap(\.windowNumber))
        thumbnails = thumbnails.filter { numbers.contains($0.key) }
        if commitWhenReady { commit() } else { takeThumbnails() }
    }

    /// Вкладки — по браузеру за раз: один запрос отдаёт все его окна.
    private func loadTabs(session: Int) {
        let browsers = Set(items.filter { $0.tabs == .loading }.compactMap(\.bundleID))
        for bundleID in browsers {
            let titles = items.filter { $0.bundleID == bundleID && $0.tabs == .loading }.map(\.title)
            BrowserTabs.load(bundleID: bundleID) { [weak self] result in
                guard let self, self.isActive, self.generation == session else { return }
                let matched = BrowserTabs.match(result, to: titles)
                var rank = 0
                for index in self.items.indices where self.items[index].bundleID == bundleID
                    && self.items[index].tabs == .loading {
                    self.items[index].tabs = matched.indices.contains(rank) ? matched[rank] : .unavailable
                    rank += 1
                }
            }
        }
    }

    func move(_ step: Int) {
        guard isActive else { return }
        guard !items.isEmpty else {
            pendingSteps += step
            // Листают — значит выбирают глазами: панель нужна сразу.
            show()
            return
        }
        if inTabs, let tabs = current?.tabs.tabs, !tabs.isEmpty {
            selectedTab = SwitcherOrder.move(selectedTab, by: step, count: tabs.count)
        } else {
            inTabs = false
            selected = SwitcherOrder.move(selected, by: step, count: items.count)
        }
        show()
    }

    /// ↓ — к вкладкам подсвеченного окна, ↑ — обратно.
    func enterTabs(_ down: Bool) {
        guard isActive, let item = current else { return }
        guard down else {
            inTabs = false
            return
        }
        switch item.tabs {
        case let .loaded(_, tabs, active) where !tabs.isEmpty:
            inTabs = true
            selectedTab = tabs.firstIndex { $0.index == active } ?? 0
            show()
        case .needsConsent:
            // Спросить разрешение посреди ⌘Tab нельзя: системное окно встанет
            // поверх, а ⌘ всё ещё держат. Закрываемся и спрашиваем.
            guard let bundleID = item.bundleID else { return }
            cancel()
            BrowserTabs.requestConsent(bundleID: bundleID)
        default:
            break
        }
    }

    /// Подсветка за курсором.
    func highlight(_ index: Int) {
        guard isActive, items.indices.contains(index) else { return }
        guard index != selected || inTabs else { return }
        inTabs = false
        selected = index
    }

    func highlightTab(_ index: Int) {
        guard isActive, let tabs = current?.tabs.tabs, tabs.indices.contains(index) else { return }
        guard !inTabs || index != selectedTab else { return }
        inTabs = true
        selectedTab = index
    }

    /// Отпустили ⌘, Enter или щелчок: перейти к выбранному.
    func commit() {
        guard isActive else { return }
        guard !items.isEmpty else {
            // Список ещё не собран — быстрое ⌘Tab. Выбор сделаем, когда
            // он придёт: это переход к предыдущему окну.
            commitWhenReady = true
            return
        }
        let item = current
        var tab: (window: String, index: Int)?
        if inTabs, let item, case let .loaded(windowID, tabs, _) = item.tabs, tabs.indices.contains(selectedTab) {
            tab = (windowID, tabs[selectedTab].index)
        }
        end()
        guard let item else { return }
        DebugLog.write("переключатель: выбрано «\(item.appName)», \(item.kind)\(tab.map { ", вкладка \($0.index)" } ?? "")")
        if let tab, let bundleID = item.bundleID {
            BrowserTabs.select(bundleID: bundleID, windowID: tab.window, tab: tab.index) {
                SwitcherWindows.activate(item)
            }
        } else {
            SwitcherWindows.activate(item)
        }
    }

    func commit(at index: Int) {
        highlight(index)
        commit()
    }

    func commitTab(at index: Int) {
        highlightTab(index)
        commit()
    }

    /// Образцы вкладок у подсвеченной строки — проверить ряд вкладок
    /// на снимке, не выдавая браузеру «Автоматизацию».
    func debugDemoTabs() {
        guard isActive, items.indices.contains(selected) else { return }
        let titles = ["Почта — Входящие (12)", "Документация: устройство переключателя окон",
                      "Прогноз погоды на неделю", "Задачи спринта — доска", "Новости"]
        let tabs = titles.enumerated().map { BrowserTab(index: $0.offset + 1, title: $0.element) }
        items[selected].tabs = .loaded(windowID: "0", tabs: tabs, active: 2)
        inTabs = true
        selectedTab = 2
    }

    /// Esc, щелчок мимо, другая панель.
    func cancel() {
        guard isActive else { return }
        DebugLog.write("переключатель: отмена")
        end()
    }

    private func end() {
        isActive = false
        commitWhenReady = false
        pendingSteps = 0
        generation += 1
        if isShown {
            isShown = false
            onHide()
        }
        onEnd()
    }

    private func show() {
        guard isActive, !isShown else { return }
        isShown = true
        onShow()
        takeThumbnails()
    }

    /// Снимки — только когда панель видна и список готов: быстрое ⌘Tab
    /// без панели не стоит ни одного.
    private func takeThumbnails() {
        guard isShown, !items.isEmpty, !thumbnailsTaken, thumbnailsEnabled() else { return }
        thumbnailsTaken = true
        // Снимок, пришедший после закрытия, тоже в запас: пригодится
        // на следующем открытии.
        WindowThumbnails.capture(items.compactMap(\.windowNumber)) { [weak self] id, image in
            self?.thumbnails[id] = image
        }
    }
}
