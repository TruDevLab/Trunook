import TrunookXPC
import AppKit
import ApplicationServices

/// Входящий звонок в чужом приложении: заметить, показать, ответить.
///
/// Устроено тем же приёмом, что и управление встречей (`MeetingService`):
/// дерево Универсального доступа читает кнопки окна и нажимает их
/// `AXPress`. Другого способа нет — CallKit на macOS не существует,
/// а словаря AppleScript у телефонов, как и у Zoom, обычно нет.
///
/// Разница со встречей одна, но важная: встреча идёт часами, и её можно
/// опрашивать раз в несколько секунд, а звонок звонит двадцать. Поэтому
/// здесь не опрос, а подписка на появление окна (`AXObserver`): окно
/// звонка создаётся в тот же миг, когда телефон начинает звонить.
final class CallService: ObservableObject {
    /// Зазвонило.
    var onCall: ((CallInvite) -> Void)?
    /// Отзвонило: ответили, бросили трубку или сдались на том конце.
    var onEnded: (() -> Void)?

    @Published private(set) var invite: CallInvite?

    private let settings: Settings
    private var observers: [pid_t: AXObserver] = [:]
    private var watched: [pid_t: CallApp] = [:]
    /// Окно, по которому показан звонок: по нему же нажимаются кнопки.
    private var callWindow: AXUIElement?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    // MARK: - Жизнь службы

    func start() {
        guard settings.callsEnabled else { return }
        guard AXTree.isTrusted else {
            DebugLog.write("звонки: нет Универсального доступа — ловить нечем")
            return
        }
        for app in NSWorkspace.shared.runningApplications {
            attach(to: app)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        DebugLog.write("звонки: слежу за приложениями — \(watched.count)")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (pid, observer) in observers {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
            )
            observers[pid] = nil
        }
        watched.removeAll()
        clear()
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        attach(to: app)
    }

    /// Подписаться на окна знакомого телефона.
    ///
    /// Подписка, а не опрос: опрос с шагом в секунду перебирал бы дерево
    /// чужого приложения по кругу весь день ради события, которое случается
    /// трижды в неделю.
    private func attach(to app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              let known = CallApp.app(bundleID: bundleID),
              observers[app.processIdentifier] == nil
        else { return }

        var observer: AXObserver?
        let created = AXObserverCreate(app.processIdentifier, callObserverCallback, &observer)
        guard created == .success, let observer else {
            DebugLog.write("звонки: наблюдатель не создан для \(known.name)")
            return
        }
        let element = AXTree.application(pid: app.processIdentifier)
        let context = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
        AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, context)
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode
        )
        observers[app.processIdentifier] = observer
        watched[app.processIdentifier] = known
        DebugLog.write("звонки: слежу за \(known.name)")
    }

    // MARK: - Поиск звонка

    /// Окно появилось — посмотреть, не звонок ли это.
    ///
    /// Смотрим на окна самого приложения, а не обходим всё подряд вглубь:
    /// у телефона открыты и список контактов, и настройки, и полный обход
    /// стоил бы тех самых секунд, которых у звонка нет.
    func windowAppeared(pid: pid_t) {
        guard let app = watched[pid], invite == nil else { return }
        let element = AXTree.application(pid: pid)

        for window in AXTree.windows(of: element) {
            let title = AXTree.string(window, kAXTitleAttribute) ?? ""
            guard app.looksLikeCall(window: title) else { continue }
            let buttons = AXTree.buttons(of: window, maxDepth: 12)

            guard buttons.contains(where: { Self.match($0.labels, app.answerTitles) }) else { continue }
            let canDecline = buttons.contains { Self.match($0.labels, app.declineTitles) }

            let invite = CallInvite(
                app: app, caller: caller(in: window, title: title), canDecline: canDecline
            )
            callWindow = window
            self.invite = invite
            // Следим и за исчезновением окна: бросили трубку на том конце
            // или ответили в самом телефоне — плашка должна уйти сразу,
            // а не висеть свои сорок пять секунд над кончившимся звонком.
            if let observer = observers[pid] {
                AXObserverAddNotification(
                    observer, window, kAXUIElementDestroyedNotification as CFString,
                    Unmanaged.passUnretained(self).toOpaque()
                )
            }
            DebugLog.write("звонки: \(app.name) — \(invite.caller.isEmpty ? "без имени" : invite.caller)"
                           + (canDecline ? ", есть отбой" : ", отбоя нет"))
            onCall?(invite)
            return
        }
    }

    /// Кто звонит.
    ///
    /// Сначала заголовок окна — в нём у большинства клиентов и стоит номер.
    /// Заголовок, совпадающий с именем самого приложения, именем звонящего
    /// не считается: выдумывать номер нельзя, плашка без имени честнее
    /// плашки с чужим.
    private func caller(in window: AXUIElement, title: String) -> String {
        let clean = CallInvite.caller(fromTitle: title)
        if !clean.isEmpty, !watched.values.contains(where: { $0.name == clean }) {
            return clean
        }
        return ""
    }

    static func match(_ labels: [String], _ titles: [String]) -> Bool {
        labels.contains { label in
            titles.contains { $0.compare(label, options: .caseInsensitive) == .orderedSame }
        }
    }

    // MARK: - Ответ

    /// Нажать «Ответить» или «Отклонить» в самом приложении.
    ///
    /// Нажатием по кнопке, а не клавишей: клавиша ушла бы активному окну,
    /// а телефон в этот момент стоит позади — и нажатие досталось бы тому,
    /// в чём человек работает.
    @discardableResult
    func answer(_ invite: CallInvite, accept: Bool) -> Bool {
        guard let window = callWindow else { return false }
        let titles = accept ? invite.app.answerTitles : invite.app.declineTitles
        let buttons = AXTree.buttons(of: window, maxDepth: 12)

        guard let target = buttons.first(where: { Self.match($0.labels, titles) }) else {
            DebugLog.write("звонки: кнопка \(accept ? "ответа" : "отбоя") не найдена")
            clear()
            return false
        }
        let pressed = AXTree.press(target.element)
        DebugLog.write("звонки: \(accept ? "ответ" : "отбой") — \(pressed ? "нажато" : "не нажалось")")
        clear()
        return pressed
    }

    /// Звонок кончился — сам или ответом.
    func clear() {
        guard invite != nil else { return }
        invite = nil
        callWindow = nil
        onEnded?()
    }

    // MARK: - Отладка

    /// Напечатать окна и кнопки знакомых телефонов.
    ///
    /// Карта подписей пишется только отсюда: у каждого клиента свои слова,
    /// и вслепую их не угадать — на встречах это уже стоило двух заходов.
    func dump() {
        guard AXTree.isTrusted else {
            DebugLog.write("звонки: нет Универсального доступа")
            return
        }
        let running = NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return CallApp.app(bundleID: id) != nil
        }
        guard !running.isEmpty else {
            DebugLog.write("звонки: знакомых телефонов не запущено")
            return
        }
        for app in running {
            AXTree.dumpApp(pid: app.processIdentifier, name: app.localizedName ?? "?")
        }
    }
}

/// Ответ наблюдателя приходит функцией языка C: замыкание с контекстом
/// туда не передать, поэтому служба приезжает указателем.
private func callObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let service = Unmanaged<CallService>.fromOpaque(context).takeUnretainedValue()
    // Окно звонка закрылось — звонок кончился, как бы он ни кончился.
    if (notification as String) == kAXUIElementDestroyedNotification {
        DispatchQueue.main.async {
            guard service.invite != nil else { return }
            DebugLog.write("звонки: окно звонка закрылось")
            service.clear()
        }
        return
    }
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    // На главной очереди: служба публикует состояние, а его читает вёрстка.
    DispatchQueue.main.async { service.windowAppeared(pid: pid) }
}
