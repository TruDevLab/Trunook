import TrunookXPC
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let launchAtLogin = LaunchAtLogin.shared
    private let controller = NotchController()
    private let settingsWindow = SettingsWindowController()
    private let welcomeWindow = WelcomeWindowController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.migrateSettingsIfNeeded()
        // До всего остального: меню и окна собираются уже переведёнными.
        Localization.shared.apply(settings.language)
        // Невидимое меню: оно раздаёт ⌘C, ⌘V и прочую правку текста.
        // Без него поля ввода в настройках и в вырезе не копировались.
        AppMenu.install()
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.start()
        installStatusItem()
        installDebugTrigger()
        // Меню строки состояния — AppKit, само себя не перерисует.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildStatusItem),
            name: .trunookLanguageChanged,
            object: nil
        )
        showWelcomeIfFirstRun()
        DebugLog.write("запуск \(AppInfo.name) \(AppInfo.version), "
                       + "автозапуск \(launchAtLogin.isEnabled ? "включён" : "выключен")")
    }

    /// Позволяет вызвать плашку события из терминала:
    ///   swift scripts/debug-event.swift lowBattery
    /// Нужно потому, что проверять состояния приложения-агента иначе можно
    /// только руками через меню в строке состояния.
    private func installDebugTrigger() {
        guard DebugLog.isEnabled else { return }
        let center = DistributedNotificationCenter.default()
        let triggers: [(String, Selector)] = [
            ("com.trunook.debug.powerConnected", #selector(testPowerConnected)),
            ("com.trunook.debug.powerDisconnected", #selector(testPowerDisconnected)),
            ("com.trunook.debug.lowBattery", #selector(testLowBattery)),
            ("com.trunook.debug.trackChanged", #selector(testTrackChanged)),
            ("com.trunook.debug.settings", #selector(openSettings)),
            ("com.trunook.debug.welcome", #selector(openWelcome)),
            ("com.trunook.debug.purr", #selector(testPurr)),
            ("com.trunook.debug.clipboard", #selector(toggleClipboardPanel)),
            ("com.trunook.debug.clipboardUse", #selector(useClipboardSlot3)),
            ("com.trunook.debug.shelf", #selector(showShelf)),
            ("com.trunook.debug.timer", #selector(showTimer)),
            ("com.trunook.debug.monitor", #selector(showMonitor)),
            ("com.trunook.debug.teleprompter", #selector(showTeleprompter)),
            ("com.trunook.debug.teleprompterScroll", #selector(scrollTeleprompter)),
            ("com.trunook.debug.teleprompterPrompt", #selector(promptTeleprompter)),
            ("com.trunook.debug.caffeine", #selector(toggleCaffeine)),
            ("com.trunook.debug.caffeineExpire", #selector(expireCaffeine)),
            ("com.trunook.debug.timerRun", #selector(runTimer)),
            ("com.trunook.debug.hub", #selector(showHub)),
            ("com.trunook.debug.openEvent", #selector(openFirstItem)),
            ("com.trunook.debug.expand", #selector(expandNotch)),
            ("com.trunook.debug.assistant", #selector(testAssistant)),
            ("com.trunook.debug.ask", #selector(testAsk)),
            ("com.trunook.debug.shot", #selector(shotWelcome)),
            ("com.trunook.debug.shotDemo", #selector(shotDemo)),
            ("com.trunook.debug.shotSettings", #selector(shotSettings)),
            ("com.trunook.debug.shotNotch", #selector(shotNotch)),
            ("com.trunook.debug.meeting", #selector(testMeeting)),
            ("com.trunook.debug.links", #selector(testLinkExtraction)),
            ("com.trunook.debug.nextTrack", #selector(testNextTrack)),
            ("com.trunook.debug.reminder", #selector(testReminderSoon)),
            ("com.trunook.debug.dump", #selector(dumpUpcoming)),
            ("com.trunook.debug.commands", #selector(toggleCommandsMenu)),
            ("com.trunook.debug.runslot1", #selector(runSlot1)),
            ("com.trunook.debug.ollama", #selector(ollamaEcho)),
            ("com.trunook.debug.meetingButtons", #selector(dumpMeetingButtons)),
            ("com.trunook.debug.meetingHand", #selector(toggleMeetingHand)),
            ("com.trunook.debug.meetingLink", #selector(copyMeetingLink)),
        ]
        for (name, action) in triggers {
            center.addObserver(self, selector: action, name: Notification.Name(name), object: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Набранное в телесуфлере уходит на диск с задержкой — при выходе
        // ждать её некому.
        controller.teleprompter.saveNow()
        controller.stop()
    }

    @objc private func rebuildStatusItem() {
        AppMenu.install()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "Trunook"
        )

        let menu = NSMenu()
        add(to: menu, title: t("Настройки…"), action: #selector(openSettings), key: ",")
        add(to: menu, title: t("Знакомство…"), action: #selector(openWelcome), key: "")
        menu.addItem(.separator())
        add(to: menu, title: t("Обновить сведения о треке"), action: #selector(refreshMusic), key: "r")
        if DebugLog.isEnabled {
            menu.addItem(.separator())
            menu.addItem(debugMenu())
        }

        menu.addItem(.separator())
        add(to: menu, title: t("Завершить Trunook"), action: #selector(quit), key: "q")

        item.menu = menu
        statusItem = item
    }

    /// Плашки событий иначе не проверить: ждать разрядки батареи ради
    /// одной анимации — плохой цикл разработки.
    private func debugMenu() -> NSMenuItem {
        let submenu = NSMenu()
        add(to: submenu, title: "Событие: зарядка подключена", action: #selector(testPowerConnected), key: "")
        add(to: submenu, title: "Событие: зарядка отключена", action: #selector(testPowerDisconnected), key: "")
        add(to: submenu, title: "Событие: низкий заряд", action: #selector(testLowBattery), key: "")
        add(to: submenu, title: "Событие: смена трека", action: #selector(testTrackChanged), key: "")
        add(to: submenu, title: "Мурчание", action: #selector(testPurr), key: "")
        add(to: submenu, title: "Окно знакомства", action: #selector(openWelcome), key: "")

        let item = NSMenuItem(title: "Отладка", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func testPowerConnected() {
        controller.activities.present(.powerConnected(percentage: controller.battery.percentage))
    }

    @objc private func testPowerDisconnected() {
        controller.activities.present(.powerDisconnected(percentage: controller.battery.percentage))
    }

    @objc private func testLowBattery() {
        controller.activities.present(.lowBattery(percentage: settings.lowBatteryThreshold))
    }

    @objc private func testTrackChanged() {
        controller.activities.present(.trackChanged)
    }

    @objc private func testPurr() {
        controller.debugPurr()
    }

    @objc private func toggleClipboardPanel() {
        controller.debugToggleClipboard()
    }

    /// Третья запись: проверяет и возврат в буфер, и подъём наверх.
    @objc private func useClipboardSlot3() {
        controller.debugUseClipboardSlot(2)
    }

    /// Полка с содержимым: само перетаскивание из отладочной сессии
    /// не изобразить — синтетические события мыши до системы не доходят.
    /// Поэтому кладём файлы на полку напрямую и смотрим вёрстку.
    @objc private func showShelf() {
        controller.debugFillShelf()
    }

    /// Меню всех функций: правую кнопку из отладочной сессии не нажать.
    @objc private func showHub() {
        controller.openHub()
    }

    @objc private func expandNotch() {
        controller.debugExpand()
    }

    @objc private func showMonitor() {
        controller.debugToggleMonitor()
    }

    @objc private func showTimer() {
        controller.debugToggleTimer()
    }

    @objc private func runTimer() {
        controller.debugRunTimer()
    }

    @objc private func openFirstItem() {
        controller.debugOpenFirstItem()
    }

    @objc private func testAssistant() {
        controller.debugAssistant()
    }

    /// Панель ответа с полем ввода: без неё вёрстку встречного вопроса
    /// из отладочной сессии не снять — «Ответить» нажимают мышью.
    @objc private func testAsk() {
        controller.askAssistant()
    }

    /// Снимок открытого окна знакомства в ~/Library/Logs/Trunook-welcome.png.
    @objc private func shotWelcome() {
        welcomeWindow.snapshot()
    }

    /// Кадры демонстрации выреза: из них собирается docs/demo.gif.
    @objc private func shotDemo() {
        welcomeWindow.snapshotDemo()
    }

    /// Снимок открытого окна настроек.
    @objc private func shotSettings() {
        settingsWindow.snapshot()
    }

    /// Снимок самого выреза.
    @objc private func shotNotch() {
        controller.snapshot()
    }

    @objc private func testMeeting() {
        let item = CalendarItem(
            id: "debug",
            title: "Разбор задач недели",
            start: Date().addingTimeInterval(5 * 60),
            end: Date().addingTimeInterval(35 * 60),
            isAllDay: false,
            source: .event,
            link: MeetingLink.extract(
                url: URL(string: "https://telemost.yandex.ru/j/12345678901234"),
                location: nil,
                notes: nil
            ),
            colorComponents: [0.3, 0.6, 1.0]
        )
        controller.activities.present(.meeting(item: item, minutesBefore: 5))
    }

    /// Извлечение ссылок — чистая логика с множеством краевых случаев,
    /// и проверять её на живых встречах неудобно: нужного события может
    /// просто не оказаться в календаре.
    @objc private func testLinkExtraction() {
        let samples: [(String, URL?, String?, String?)] = [
            ("Telemost в url", URL(string: "https://telemost.yandex.ru/j/123"), nil, nil),
            ("Zoom в location", nil, "https://us02web.zoom.us/j/8912345678", nil),
            ("Meet в notes", nil, "Переговорная 3", "Подключиться: https://meet.google.com/abc-defg-hij"),
            ("Teams в notes", nil, nil, "https://teams.microsoft.com/l/meetup-join/19%3ameeting"),
            ("Карта рядом со ссылкой", nil, "https://yandex.ru/maps/-/CDe12", "Зум: https://zoom.us/j/999"),
            ("Только карта", nil, "https://yandex.ru/maps/-/CDe12", nil),
            ("Вложение", nil, nil, "Материалы: https://disk.yandex.ru/d/abcdef"),
            ("Пусто", nil, nil, nil),
        ]

        DebugLog.write("— проверка извлечения ссылок —")
        for (name, url, location, notes) in samples {
            let link = MeetingLink.extract(url: url, location: location, notes: notes)
            let result = link.map { "\($0.provider.rawValue) → \($0.url.host ?? "?")" } ?? "не найдено"
            DebugLog.write("  \(name): \(result)")
        }
    }

    /// Переключает трек по-настоящему: канал уведомлений MediaRemote иначе
    /// не проверить — он молчит, пока трек не сменился.
    @objc private func testNextTrack() {
        controller.music.send(.nextTrack)
    }

    /// Подсовывает планировщику напоминание со сроком через 20 секунд.
    /// Проверяет настоящий путь срабатывания, а не только внешний вид плашки:
    /// заводить ради этого живое напоминание в системе неудобно.
    @objc private func testReminderSoon() {
        controller.scheduleTestReminder(in: 20)
    }

    /// Печатает то, что приложение реально видит в календаре и напоминаниях.
    @objc private func dumpUpcoming() {
        let items = controller.calendar.upcoming
        DebugLog.write("— список впереди: \(items.count) —")
        for item in items.prefix(12) {
            let kind: String
            switch item.source {
            case .event: kind = "встреча"
            case .reminder: kind = "напоминание"
            case .things: kind = "задача"
            }
            DebugLog.write("  \(item.timeLabel) \(kind)"
                           + (item.isAllDay ? " (весь день)" : "")
                           + " «\(item.title)»")
        }
    }

    @objc private func toggleCommandsMenu() {
        controller.debugToggleCommands()
    }

    /// Снимает кнопки страницы встречи — по этому выводу калибруются подписи.
    @objc private func dumpMeetingButtons() {
        controller.meeting.dumpButtons()
    }

    /// Поднимает и тут же опускает руку: единственное действие встречи,
    /// которое можно проверить, не тронув звук и видео собеседников.
    @objc private func toggleMeetingHand() {
        controller.meeting.perform(.hand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.controller.meeting.perform(.hand)
        }
    }


    @objc private func copyMeetingLink() {
        controller.meeting.perform(.copyLink)
    }

    @objc private func ollamaEcho() {
        controller.debugOllamaEcho()
    }

    @objc private func runSlot1() {
        controller.debugRunSlot(0)
    }

    @objc private func showTeleprompter() {
        controller.debugToggleTeleprompter()
    }

    @objc private func scrollTeleprompter() {
        controller.debugToggleTeleprompterScroll()
    }

    @objc private func promptTeleprompter() {
        controller.debugCycleTeleprompterPrompt()
    }

    @objc private func toggleCaffeine() {
        controller.debugToggleAwake()
    }

    @objc private func expireCaffeine() {
        controller.debugExpireAwake()
    }



    private func add(to menu: NSMenu, title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    /// Первый запуск: окно знакомства открывается само и берёт на себя
    /// запрос доступов. Задержка — чтобы окно не выскочило раньше, чем
    /// система дорисует рабочий стол после входа в систему.
    private func showWelcomeIfFirstRun() {
        guard !settings.hasSeenWelcome else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.openWelcome()
        }
    }

    @objc private func openWelcome() {
        welcomeWindow.show(
            calendar: controller.calendar,
            launchAtLogin: launchAtLogin,
            weather: controller.weather,
            onHotKeysChanged: { [weak self] in self?.controller.installHotKeys() }
        )
    }

    @objc private func openSettings() {
        settingsWindow.show(
            settings: settings,
            launchAtLogin: launchAtLogin,
            calendar: controller.calendar,
            clipboard: controller.clipboard,
            weather: controller.weather,
            onHotKeysChanged: { [weak self] in self?.controller.installHotKeys() },
            onOpenWelcome: { [weak self] in self?.openWelcome() }
        )
    }

    @objc private func refreshMusic() {
        controller.music.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
