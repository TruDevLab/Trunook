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
        // До всего, что спрашивает адрес модели: провайдеры разъезжаются
        // по своим полям, и до переноса общие поля читались бы как чужие.
        settings.migrateProviderSettings()
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
            ("com.trunook.debug.update", #selector(checkForUpdates)),
            ("com.trunook.debug.updatePill", #selector(testUpdatePill)),
            ("com.trunook.debug.updateVerify", #selector(testUpdateVerify)),
            ("com.trunook.debug.updateInstall", #selector(testUpdateInstall)),
            ("com.trunook.debug.clipboard", #selector(toggleClipboardPanel)),
            ("com.trunook.debug.clipboardUse", #selector(useClipboardSlot3)),
            ("com.trunook.debug.shelf", #selector(showShelf)),
            ("com.trunook.debug.timer", #selector(showTimer)),
            ("com.trunook.debug.monitor", #selector(showMonitor)),
            ("com.trunook.debug.teleprompter", #selector(showTeleprompter)),
            ("com.trunook.debug.teleprompterScroll", #selector(scrollTeleprompter)),
            ("com.trunook.debug.teleprompterPrompt", #selector(promptTeleprompter)),
            ("com.trunook.debug.caffeine", #selector(toggleCaffeine)),
            ("com.trunook.debug.notes", #selector(showNotes)),
            ("com.trunook.debug.notesFill", #selector(fillNotes)),
            ("com.trunook.debug.notesAsk", #selector(askNotes)),
            ("com.trunook.debug.noteNew", #selector(newNote)),
            ("com.trunook.debug.noteSelection", #selector(noteSelection)),
            ("com.trunook.debug.askLong", #selector(askLong)),
            ("com.trunook.debug.voice", #selector(toggleVoice)),
            ("com.trunook.debug.voiceNotes", #selector(toggleVoiceNotes)),
            ("com.trunook.debug.voiceGlow", #selector(showVoiceGlow)),
            ("com.trunook.debug.voiceSpeak", #selector(speakSample)),
            ("com.trunook.debug.voiceAnswer", #selector(voiceAnswer)),
            ("com.trunook.debug.noteClipboard", #selector(noteClipboard)),
            ("com.trunook.debug.noteEdit", #selector(editNote)),
            ("com.trunook.debug.noteSave", #selector(saveNote)),
            ("com.trunook.debug.caffeineExpire", #selector(expireCaffeine)),
            ("com.trunook.debug.caffeineOn", #selector(startCaffeine)),
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
            ("com.trunook.debug.shotMarks", #selector(shotMarks)),
            ("com.trunook.debug.meeting", #selector(testMeeting)),
            ("com.trunook.debug.links", #selector(testLinkExtraction)),
            ("com.trunook.debug.nextTrack", #selector(testNextTrack)),
            ("com.trunook.debug.reminder", #selector(testReminderSoon)),
            ("com.trunook.debug.dump", #selector(dumpUpcoming)),
            ("com.trunook.debug.capture", #selector(testCapture)),
            ("com.trunook.debug.captureOpen", #selector(testCaptureExpanded)),
            ("com.trunook.debug.captureDown", #selector(testCaptureHighlight)),
            ("com.trunook.debug.clipboardDown", #selector(testClipboardHighlight)),
            ("com.trunook.debug.captureModels", #selector(testCaptureModels)),
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
        add(to: menu, title: t("Проверить обновления"), action: #selector(checkForUpdates), key: "")
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

    /// Список заметок: поиск, строки, пустое состояние.
    @objc private func showNotes() {
        controller.debugToggleNotes()
    }

    /// Набить заметками — иначе список нечем показать, а сохранить из панели
    /// можно только нажатием, которого из сессии нет.
    @objc private func fillNotes() {
        controller.debugFillNotes()
    }

    /// Открыть свежую заметку на правку — то же, что нажатие по строке
    /// списка. Нажать её из сессии нечем, а именно на ней ловили ошибку:
    /// заметка из ответа модели открывалась как ответ, а не как заметка.
    @objc private func editNote() {
        controller.debugEditNewestNote()
    }

    /// Сохранить набранное заметкой — то же, что главная кнопка панели.
    /// Ею же проверяется подтверждение: плашки событий из-под накладки
    /// не видно, и без своего подтверждения сохранение выглядит
    /// несработавшим.
    @objc private func saveNote() {
        controller.debugSaveNote()
    }

    /// Создание заметки — то же, что делает сочетание клавиш.
    @objc private func newNote() {
        controller.debugNoteComposer()
    }

    /// Вопрос по заметкам: включает переключатель и шлёт запрос с их
    /// контекстом. Нажать кнопку из сессии нечем.
    @objc private func askNotes() {
        controller.debugAskNotes()
    }

    /// Панель с длинным вопросом в поле: так видно выросшее поле и панель,
    /// подросшую вслед за ним. Набрать текст из сессии нечем.
    @objc private func askLong() {
        controller.debugLongQuestion()
    }

    /// Голосовой заход — то же, что двойное нажатие модификатора.
    ///
    /// Сам жест из сессии не изобразить: глобальный монитор не получает
    /// синтетических событий, а Универсальный доступ выдан приложению,
    /// а не отладочной сессии.
    @objc private func toggleVoice() {
        controller.debugToggleVoice()
    }

    /// То же, но с заметками в контексте.
    @objc private func toggleVoiceNotes() {
        controller.debugToggleVoiceNotes()
    }

    /// Прогнать фазы свечения по очереди — чтобы каждую успеть снять
    /// `shotNotch`. Живой заход для этого не годится: он идёт своим ходом
    /// и ждать снимка не станет.
    @objc private func showVoiceGlow() {
        controller.debugVoiceGlow()
    }

    /// Прочитать образец вслух: голос, скорость и обрыв проверяются только
    /// на слух.
    @objc private func speakSample() {
        controller.speakVoiceSample()
    }

    /// Полный путь голосового ответа — до тишины включительно.
    @objc private func voiceAnswer() {
        controller.debugVoiceAnswer()
    }

    /// Выделенное в заметки — то же, что делает сочетание.
    ///
    /// Само сочетание из сессии не проверить: синтетические нажатия
    /// до Carbon не доходят. Обработчик — проверяется, и вместе с ним весь
    /// путь: чтение выделения, запись и подтверждение.
    @objc private func noteSelection() {
        controller.saveSelectionToNotes()
    }

    /// Свежая запись буфера в заметки — то же, что кнопка в списке истории
    /// и на плашке о копировании. Нажать их из сессии нечем.
    @objc private func noteClipboard() {
        controller.debugSaveNewestClipboardToNotes()
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

    /// Лист со значками провайдеров.
    @objc private func shotMarks() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Trunook-marks.png")
        ProviderMark.writeSheet(to: url)
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

    /// Панель разговора с образцом захваченного текста.
    ///
    /// Настоящее выделение из отладочной сессии не создать: чужому окну
    /// его негде взять, а синтетические нажатия до Carbon не доходят.
    /// Образец подставляется прямо — вёрстку плашки и списка команд иначе
    /// не снять вовсе.
    @objc private func testCapture() {
        controller.debugCapture()
    }

    /// То же, но с раскрытой плашкой: свёрнутая показывает две строки,
    /// и по ней не увидеть ни прокрутки, ни того, во что панель вырастает.
    @objc private func testCaptureExpanded() {
        controller.debugCapture(expanded: true)
    }

    /// Подсветка уведена на пятую команду: список должен сдвинуться,
    /// иначе подсветка стоит там, где её не видно.
    @objc private func testCaptureHighlight() {
        controller.debugCaptureHighlight(steps: 5)
    }

    /// Зажечь чашку на срок: полоску в свёрнутом вырезе иначе не снять —
    /// срок выбирают нажатием, а нажать из сессии нечем.
    @objc private func startCaffeine() {
        controller.wake.setLimit(minutes: 90)
    }

    /// Панель с открытым выбором модели.
    @objc private func testCaptureModels() {
        controller.debugCaptureModels()
    }

    /// Подсветка истории уведена на седьмую строку: видно шесть, список
    /// обязан сдвинуться.
    @objc private func testClipboardHighlight() {
        controller.debugClipboardHighlight(steps: 7)
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
            notes: controller.notes,
            updates: controller.updates,
            onHotKeysChanged: { [weak self] in self?.controller.installHotKeys() },
            onLayoutChanged: { [weak self] in self?.controller.relayout() },
            onOpenWelcome: { [weak self] in self?.openWelcome() },
            onPreviewVoice: { [weak self] in self?.controller.speakVoiceSample() },
            // Ползунок прозрачности меняет вид выреза из другого окна —
            // и держит его раскрытым, пока человек смотрит.
            onPreviewNotch: { [weak self] seconds in
                self?.controller.holdOpen(seconds: seconds)
            }
        )
    }

    @objc private func refreshMusic() {
        controller.music.refresh()
    }

    /// Проверка рукой идёт всегда, даже при выключенной автопроверке:
    /// иначе у пункта нет смысла.
    @objc private func checkForUpdates() {
        controller.updates.check(manual: true)
    }

    /// Установить скачанное. Нажать кнопку из отладочной сессии нечем:
    /// синтетические клики до приложения не доходят.
    @objc private func testUpdateInstall() {
        controller.updates.install()
    }

    /// Плашка обновления с выдуманным номером: ждать настоящего выпуска ради
    /// одной вёрстки — плохой цикл разработки.
    @objc private func testUpdatePill() {
        controller.activities.present(.update(version: "9.9.9"))
    }

    /// Проверка подписи на образе, лежащем в папке проекта, без установки.
    ///
    /// Тестом это не закрыть: нужен подписанный бандл и живая служба Security.
    /// Проверять надо тем процессом, который этим будет пользоваться, —
    /// скрипт под `swift` подписан Apple и ответит иначе.
    @objc private func testUpdateVerify() {
        let path = NSHomeDirectory() + "/Desktop/Trunook/Trunook-\(AppInfo.shortVersion).dmg"
        let image = URL(fileURLWithPath: path)
        guard let mounted = DiskImage.attach(image) else {
            DebugLog.write("проверка подписи: образ \(path) не смонтировался")
            return
        }
        defer { DiskImage.detach(mounted) }
        guard let application = DiskImage.application(in: mounted.mountPoint) else {
            DebugLog.write("проверка подписи: приложения на образе не нашлось")
            return
        }
        switch CodeSignatureCheck.matchesSelf(application) {
        case .valid:
            DebugLog.write("проверка подписи: годно — \(application.lastPathComponent)")
        case let .rejected(reason):
            DebugLog.write("проверка подписи: отказ — \(reason.message)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
