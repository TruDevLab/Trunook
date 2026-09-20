import TrunookXPC
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private let launchAtLogin = LaunchAtLogin.shared
    private let controller = NotchController()
    private let settingsWindow = SettingsWindowController()
    private let welcomeWindow = WelcomeWindowController()
    private let confetti = ConfettiWindowController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppInfo.migrateSettingsIfNeeded()
        // До всего, что спрашивает адрес модели: провайдеры разъезжаются
        // по своим полям, и до переноса общие поля читались бы как чужие.
        settings.migrateProviderSettings()
        // После разъезда провайдеров: решение зависит от того, что у них
        // в полях, и до переноса поля ещё общие.
        settings.migrateAdvancedProviders()
        settings.migrateEmbedModel()
        // До всего остального: меню и окна собираются уже переведёнными.
        Localization.shared.apply(settings.language)
        // Невидимое меню: оно раздаёт ⌘C, ⌘V и прочую правку текста.
        // Без него поля ввода в настройках и в вырезе не копировались.
        AppMenu.install()
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onOpenSettingsTab = { [weak self] tab in
            self?.settingsWindow.select(tab)
            self?.openSettings()
        }
        controller.onOpenReleaseNotes = { [weak self] in self?.openReleaseNotes() }
        controller.onCelebrate = { [weak self] in
            guard let self else { return }
            self.confetti.fire(on: self.controller.notchScreen)
        }
        controller.start()
        installStatusItem()
        installDebugTrigger()
        // Движок опознаётся при запуске, и стоящая, но молчащая Ollama
        // поднимается сама: иначе первый вопрос дня падает ни за что.
        OllamaEngine.shared.refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            OllamaEngine.shared.ensureUp()
        }
        // Меню строки состояния — AppKit, само себя не перерисует.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildStatusItem),
            name: .trunookLanguageChanged,
            object: nil
        )
        greetLaunch()
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
            ("com.trunook.debug.releaseNotes", #selector(openReleaseNotes)),
            ("com.trunook.debug.confetti", #selector(testConfetti)),
            ("com.trunook.debug.obsidianScan", #selector(obsidianScan)),
            ("com.trunook.debug.obsidianSync", #selector(obsidianSync)),
            ("com.trunook.debug.obsidianLinks", #selector(obsidianLinks)),
            ("com.trunook.debug.shotConfetti", #selector(shotConfetti)),
            ("com.trunook.debug.purr", #selector(testPurr)),
            ("com.trunook.debug.update", #selector(checkForUpdates)),
            ("com.trunook.debug.updatePill", #selector(testUpdatePill)),
            ("com.trunook.debug.updateVerify", #selector(testUpdateVerify)),
            ("com.trunook.debug.updateInstall", #selector(testUpdateInstall)),
            ("com.trunook.debug.clipboard", #selector(toggleClipboardPanel)),
            ("com.trunook.debug.clipboardUse", #selector(useClipboardSlot3)),
            ("com.trunook.debug.shelf", #selector(showShelf)),
            ("com.trunook.debug.shelfZones", #selector(stepShelfZones)),
            ("com.trunook.debug.windowSlots", #selector(stepWindowSlots)),
            ("com.trunook.debug.windowLeft", #selector(windowLeft)),
            ("com.trunook.debug.windowFill", #selector(windowFill)),
            ("com.trunook.debug.windowCycle", #selector(windowCycle)),
            ("com.trunook.debug.countdownNow", #selector(countdownNow)),
            ("com.trunook.debug.breakRest", #selector(breakRest)),
            ("com.trunook.debug.breakWater", #selector(breakWater)),
            ("com.trunook.debug.breakStretch", #selector(breakStretch)),
            ("com.trunook.debug.shelfZip", #selector(shelfZip)),
            ("com.trunook.debug.shelfUnzip", #selector(shelfUnzip)),
            ("com.trunook.debug.shelfShare", #selector(shelfShare)),
            ("com.trunook.debug.shelfTrash", #selector(shelfTrash)),
            ("com.trunook.debug.timer", #selector(showTimer)),
            ("com.trunook.debug.monitor", #selector(showMonitor)),
            ("com.trunook.debug.feeds", #selector(showFeeds)),
            ("com.trunook.debug.feedsSites", #selector(showFeedsSites)),
            ("com.trunook.debug.digestRun", #selector(runDigest)),
            ("com.trunook.debug.digestSuggest", #selector(suggestDigestTopics)),
            ("com.trunook.debug.digestPill", #selector(testDigestPill)),
            ("com.trunook.debug.watchCheck", #selector(checkWatches)),
            ("com.trunook.debug.watchProbe", #selector(probeWatch)),
            ("com.trunook.debug.watchPill", #selector(testWatchPill)),
            ("com.trunook.debug.teleprompter", #selector(showTeleprompter)),
            ("com.trunook.debug.teleprompterScroll", #selector(scrollTeleprompter)),
            ("com.trunook.debug.teleprompterPrompt", #selector(promptTeleprompter)),
            ("com.trunook.debug.caffeine", #selector(toggleCaffeine)),
            ("com.trunook.debug.notes", #selector(showNotes)),
            ("com.trunook.debug.calendar", #selector(showCalendar)),
            ("com.trunook.debug.calendarTimeline", #selector(showCalendarTimeline)),
            ("com.trunook.debug.homeTimeline", #selector(toggleHomeTimeline)),
            ("com.trunook.debug.homeCommands", #selector(toggleHomeCommands)),
            ("com.trunook.debug.ring", #selector(showQuickRing)),
            ("com.trunook.debug.eventEdit", #selector(editEvent2)),
            ("com.trunook.debug.eventNew", #selector(composeEvent)),
            ("com.trunook.debug.eventSeries", #selector(editSeries)),
            ("com.trunook.debug.eventNotes", #selector(editEventWithNotes)),
            ("com.trunook.debug.notesFill", #selector(fillNotes)),
            ("com.trunook.debug.notesMiss", #selector(missingNote)),
            ("com.trunook.debug.notesAsk", #selector(askNotes)),
            ("com.trunook.debug.noteNew", #selector(newNote)),
            ("com.trunook.debug.noteSelection", #selector(noteSelection)),
            ("com.trunook.debug.askLong", #selector(askLong)),
            ("com.trunook.debug.mention", #selector(mention)),
            ("com.trunook.debug.mentionRun", #selector(mentionRun)),
            ("com.trunook.debug.voice", #selector(toggleVoice)),
            ("com.trunook.debug.voiceGlow", #selector(showVoiceGlow)),
            ("com.trunook.debug.voiceSpeak", #selector(speakSample)),
            ("com.trunook.debug.voiceAnswer", #selector(voiceAnswer)),
            ("com.trunook.debug.voiceAsk", #selector(askByVoice)),
            ("com.trunook.debug.dictate", #selector(dictateIntoNote)),
            ("com.trunook.debug.noteClipboard", #selector(noteClipboard)),
            ("com.trunook.debug.noteEdit", #selector(editNote)),
            ("com.trunook.debug.noteSave", #selector(saveNote)),
            ("com.trunook.debug.caffeineExpire", #selector(expireCaffeine)),
            ("com.trunook.debug.caffeineOn", #selector(startCaffeine)),
            ("com.trunook.debug.water", #selector(showWater)),
            ("com.trunook.debug.waterPill", #selector(showWaterPill)),
            ("com.trunook.debug.waterVessel", #selector(showWaterVessel)),
            ("com.trunook.debug.keyboardLock", #selector(showKeyboardLock)),
            ("com.trunook.debug.keyboardLockRun", #selector(runKeyboardLock)),
            ("com.trunook.debug.keyboardLockExpire", #selector(expireKeyboardLock)),
            ("com.trunook.debug.timerRun", #selector(runTimer)),
            ("com.trunook.debug.stopwatchRun", #selector(runStopwatch)),
            ("com.trunook.debug.ringMenu", #selector(showRingMenu)),
            ("com.trunook.debug.openEvent", #selector(openFirstItem)),
            ("com.trunook.debug.expand", #selector(expandNotch)),
            ("com.trunook.debug.homeAll", #selector(showHomePage)),
            ("com.trunook.debug.homePinned", #selector(toggleHomePinned)),
            ("com.trunook.debug.notePin", #selector(togglePinNewestNote)),
            ("com.trunook.debug.noteChecklist", #selector(showChecklist)),
            ("com.trunook.debug.critter", #selector(playCritter)),
            ("com.trunook.debug.critterEyes", #selector(playCritterEyes)),
            ("com.trunook.debug.critterTail", #selector(playCritterTail)),
            ("com.trunook.debug.critterRun", #selector(playCritterRun)),
            ("com.trunook.debug.critterEars", #selector(playCritterEars)),
            ("com.trunook.debug.critterPaw", #selector(playCritterPaw)),
            ("com.trunook.debug.critterSleep", #selector(playCritterSleep)),
            ("com.trunook.debug.critterUpside", #selector(playCritterUpside)),
            ("com.trunook.debug.critterYarn", #selector(playCritterYarn)),
            ("com.trunook.debug.critterAngry", #selector(playCritterAngry)),
            ("com.trunook.debug.critterFist", #selector(playCritterFist)),
            ("com.trunook.debug.critterKiss", #selector(playCritterKiss)),
            ("com.trunook.debug.critterChase", #selector(playCritterChase)),
            ("com.trunook.debug.critterHunt", #selector(playCritterHunt)),
            ("com.trunook.debug.critterCool", #selector(playCritterCool)),
            ("com.trunook.debug.critterSmoke", #selector(playCritterSmoke)),
            ("com.trunook.debug.critterMouse", #selector(playCritterMouse)),
            ("com.trunook.debug.critterBeach", #selector(playCritterBeach)),
            ("com.trunook.debug.critterBird", #selector(playCritterBird)),
            ("com.trunook.debug.critterWatch", #selector(playCritterWatch)),
            ("com.trunook.debug.critterWinter", #selector(playCritterWinter)),
            ("com.trunook.debug.critterKittens", #selector(playCritterKittens)),
            ("com.trunook.debug.critterFlowers", #selector(playCritterFlowers)),
            ("com.trunook.debug.critterTank", #selector(playCritterTank)),
            ("com.trunook.debug.critterEaster", #selector(playCritterEaster)),
            ("com.trunook.debug.critterPumpkin", #selector(playCritterPumpkin)),
            ("com.trunook.debug.critterValentine", #selector(playCritterValentine)),
            ("com.trunook.debug.critterRibbon", #selector(playCritterRibbon)),
            ("com.trunook.debug.critterDragon", #selector(playCritterDragon)),
            ("com.trunook.debug.critterRocket", #selector(playCritterRocket)),
            ("com.trunook.debug.weatherScene", #selector(playWeatherScene)),
            ("com.trunook.debug.weatherChange", #selector(playWeatherChange)),
            ("com.trunook.debug.weatherHeavySnow", #selector(playWeatherHeavySnow)),
            ("com.trunook.debug.weatherBlizzard", #selector(playWeatherBlizzard)),
            ("com.trunook.debug.weatherSun", #selector(playWeatherSun)),
            ("com.trunook.debug.weatherClouds", #selector(playWeatherClouds)),
            ("com.trunook.debug.weatherFog", #selector(playWeatherFog)),
            ("com.trunook.debug.weatherDrizzle", #selector(playWeatherDrizzle)),
            ("com.trunook.debug.weatherRain", #selector(playWeatherRain)),
            ("com.trunook.debug.weatherSnow", #selector(playWeatherSnow)),
            ("com.trunook.debug.weatherThunder", #selector(playWeatherThunder)),
            ("com.trunook.debug.weatherWind", #selector(playWeatherWind)),
            ("com.trunook.debug.homeReset", #selector(resetHome)),
            ("com.trunook.debug.assistant", #selector(testAssistant)),
            ("com.trunook.debug.ask", #selector(testAsk)),
            ("com.trunook.debug.models", #selector(dumpModelOffers)),
            ("com.trunook.debug.engine", #selector(dumpEngine)),
            ("com.trunook.debug.engineStart", #selector(startEngine)),
            ("com.trunook.debug.engineQuit", #selector(quitEngine)),
            ("com.trunook.debug.engineVerify", #selector(verifyEngineImage)),
            ("com.trunook.debug.engineInstall", #selector(installEngine)),
            ("com.trunook.debug.modelPull", #selector(pullEmbedModel)),
            ("com.trunook.debug.modelsPair", #selector(pullModelPair)),
            ("com.trunook.debug.agentTools", #selector(dumpAgentTools)),
            ("com.trunook.debug.agentTime", #selector(dumpAgentTime)),
            ("com.trunook.debug.agentSteps", #selector(showAgentSteps)),
            ("com.trunook.debug.answerDown", #selector(stepAnswerHighlight)),
            ("com.trunook.debug.followUp", #selector(askFollowUp)),
            ("com.trunook.debug.monday", #selector(askMonday)),
            ("com.trunook.debug.agentCard", #selector(showAgentCard)),
            ("com.trunook.debug.agentCardNote", #selector(showAgentCardNote)),
            ("com.trunook.debug.agentRun", #selector(runAgentTimer)),
            ("com.trunook.debug.agentAsk", #selector(runAgentAgenda)),
            ("com.trunook.debug.helpAsk", #selector(askAppHelp)),
            ("com.trunook.debug.slash", #selector(showSlashList)),
            ("com.trunook.debug.slashAsk", #selector(askWithSlash)),
            ("com.trunook.debug.askStop", #selector(askAndStop)),
            ("com.trunook.debug.helpSetting", #selector(askAppHelpSetting)),
            ("com.trunook.debug.shot", #selector(shotWelcome)),
            ("com.trunook.debug.shotDemo", #selector(shotDemo)),
            ("com.trunook.debug.shotSettings", #selector(shotSettings)),
            ("com.trunook.debug.shotNotch", #selector(shotNotch)),
            ("com.trunook.debug.shotMirror", #selector(shotMirror)),
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
            ("com.trunook.debug.captureRun", #selector(runCaptureCommand)),
            ("com.trunook.debug.pasteProbe", #selector(probePaste)),
            ("com.trunook.debug.pasteRow", #selector(stepPasteRow)),
            ("com.trunook.debug.ollama", #selector(ollamaEcho)),
            ("com.trunook.debug.meetingButtons", #selector(dumpMeetingButtons)),
            ("com.trunook.debug.meetingApps", #selector(dumpMeetingApps)),
            ("com.trunook.debug.meetingProbe", #selector(probeMeetingPress)),
            ("com.trunook.debug.meetingHand", #selector(toggleMeetingHand)),
            ("com.trunook.debug.meetingLink", #selector(copyMeetingLink)),
            ("com.trunook.debug.audioProbe", #selector(audioProbe)),
            ("com.trunook.debug.devices", #selector(dumpAudioDevices)),
            ("com.trunook.debug.recordStart", #selector(startRecording)),
            ("com.trunook.debug.recordStop", #selector(stopRecording)),
            ("com.trunook.debug.recordNote", #selector(runRecording)),
            ("com.trunook.debug.installLanguage", #selector(installLanguage)),
            ("com.trunook.debug.transcribeLast", #selector(transcribeLast)),
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
        add(to: menu, title: t("Что нового…"), action: #selector(openReleaseNotes), key: "")
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
        add(to: submenu, title: "Описание выпусков", action: #selector(openReleaseNotes), key: "")
        add(to: submenu, title: "Конфетти из чёлки", action: #selector(testConfetti), key: "")
        submenu.addItem(.separator())
        submenu.addItem(scenesMenu(
            title: "Кот",
            random: ("Случайная сценка", #selector(playCritter)),
            items: CritterSchedule.everyday.map { (Self.debugTitle($0), $0.rawValue) },
            action: #selector(playCritterFromMenu(_:))
        ))
        submenu.addItem(scenesMenu(
            title: "Кот: праздники",
            random: nil,
            items: CritterHoliday.allCases.map { (Self.debugTitle($0.act), $0.act.rawValue) },
            action: #selector(playCritterFromMenu(_:))
        ))
        submenu.addItem(scenesMenu(
            title: "Перерывы",
            random: nil,
            items: BreakKind.allCases.map { ($0.message, $0.rawValue) },
            action: #selector(playBreakFromMenu(_:))
        ))
        submenu.addItem(scenesMenu(
            title: "Погода",
            random: ("Случайная сценка", #selector(playWeatherScene)),
            items: WeatherArt.Scene.allCases.map { (Self.debugTitle($0), $0.rawValue) },
            action: #selector(playWeatherFromMenu(_:))
        ))

        let item = NSMenuItem(title: "Отладка", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Подменю сценок: каждая — пунктом, её имя лежит в `representedObject`.
    private func scenesMenu(title: String, random: (String, Selector)?, items: [(String, String)],
                            action: Selector) -> NSMenuItem {
        let menu = NSMenu()
        if let random {
            add(to: menu, title: random.0, action: random.1, key: "")
            menu.addItem(.separator())
        }
        for (name, raw) in items {
            let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = raw
            menu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func playCritterFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let act = NotchCritter.Act(rawValue: raw) else { return }
        controller.debugCritter(act)
    }

    @objc private func playBreakFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = BreakKind(rawValue: raw) else { return }
        controller.debugBreak(kind)
    }

    /// Раскладки окна: перетаскивание окна из сессии не повторить.
    @objc private func stepWindowSlots() { controller.debugStepWindowSlots() }
    @objc private func windowLeft() { controller.debugApplyWindowSlot(.leftHalf) }
    @objc private func windowFill() { controller.debugApplyWindowSlot(.fill) }
    @objc private func windowCycle() { controller.debugCycleWindowSlots() }
    /// Наступление события отсчёта: плашка и залп, не дожидаясь даты.
    @objc private func countdownNow() { controller.debugCountdownReached() }
    @objc private func breakRest() { controller.debugBreak(.rest) }
    @objc private func breakWater() { controller.debugBreak(.water) }
    @objc private func breakStretch() { controller.debugBreak(.stretch) }

    @objc private func playWeatherFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let scene = WeatherArt.Scene(rawValue: raw) else { return }
        controller.debugWeatherScene(scene)
    }

    /// Имена сценок в меню отладки. Перечислением, а не словарём: новая
    /// сценка без имени не соберётся.
    static func debugTitle(_ act: NotchCritter.Act) -> String {
        switch act {
        case .eyes: return "Мордочка"
        case .tail: return "Хвост"
        case .run: return "Пробежка"
        case .ears: return "Уши"
        case .paw: return "Лапа"
        case .sleep: return "Сон"
        case .upside: return "Вверх ногами"
        case .yarn: return "Клубок"
        case .angry: return "Злой котик"
        case .fist: return "Кулак"
        case .kiss: return "Поцелуйчик"
        case .chase: return "За хвостом"
        case .hunt: return "Охота на курсор"
        case .cool: return "Очки"
        case .smoke: return "Сигарета"
        case .mouse: return "Погоня за мышью"
        case .beach: return "Зонт и смузи"
        case .bird: return "Птичка"
        case .watch: return "Слежка за курсором"
        case .winter: return "Новый год"
        case .kittens: return "1 июня — котята"
        case .flowers: return "8 Марта — букет"
        case .tank: return "23 Февраля — танк"
        case .easter: return "Пасха"
        case .pumpkin: return "Хэллоуин"
        case .valentine: return "14 Февраля"
        case .ribbon: return "9 Мая — ленточка"
        case .dragon: return "Китайский Новый год"
        case .rocket: return "День космонавтики"
        case .rest: return "Перерыв — чай"
        case .drink: return "Вода — стакан"
        case .stretch: return "Разминка"
        }
    }

    static func debugTitle(_ scene: WeatherArt.Scene) -> String {
        switch scene {
        case .sun: return "Солнце"
        case .clouds: return "Облачно"
        case .fog: return "Туман"
        case .drizzle: return "Морось"
        case .rain: return "Дождь"
        case .snow: return "Снег"
        case .heavySnow: return "Снегопад"
        case .blizzard: return "Вьюга"
        case .thunder: return "Гроза"
        case .wind: return "Ветер"
        }
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

    /// Разделы полки по одному: перетаскивание из сессии не повторить.
    @objc private func stepShelfZones() { controller.debugStepShelfZones() }
    /// Действия разделов на пробных файлах в кэше — не на файлах человека.
    @objc private func shelfZip() { controller.debugShelfAction(.archive, unpack: false) }
    @objc private func shelfUnzip() { controller.debugShelfAction(.archive, unpack: true) }
    @objc private func shelfShare() { controller.debugShelfAction(.share, unpack: false) }
    @objc private func shelfTrash() { controller.debugShelfAction(.trash, unpack: false) }

    /// Меню всех функций: правую кнопку из отладочной сессии не нажать.
    @objc private func showRingMenu() {
        controller.openRingMenu()
    }

    @objc private func expandNotch() {
        controller.debugExpand()
    }

    /// Какую страницу проверочной раскладки показать следующей.
    private var homePage = 0

    /// Все виджеты во всех размерах — по страницам, каждая в четыре ряда.
    /// Каждый вызов пишет в настройки следующую страницу и раскрывает вырез
    /// под снимок; `homeReset` возвращает раскладку по умолчанию.
    @objc private func showHomePage() {
        let pages = HomeWidgets.showcasePages()
        let page = homePage % pages.count
        homePage += 1
        // Открытая панель поверх главного экрана уносит снимок мимо цели:
        // раскладка меняется, а видно команды. Уже стоило одного кадра.
        controller.debugCloseOverlay()
        Settings.shared.homeWidgets = pages[page]
        DebugLog.write("главный экран: страница \(page + 1) из \(pages.count) — "
            + pages[page].map { "\($0.kind.rawValue) \($0.size.title)" }.joined(separator: ", "))
        controller.debugExpand(seconds: 8)
    }

    /// Раскладка человека на время показа плитки закреплённых заметок.
    private var homeBeforePinned: [HomeWidget]?

    /// Плитка закреплённых в двух размерах. Повторный вызов возвращает
    /// прежнюю раскладку: главный экран человека трогать насовсем нельзя.
    @objc private func toggleHomePinned() {
        if let saved = homeBeforePinned {
            Settings.shared.homeWidgets = saved
            homeBeforePinned = nil
            DebugLog.write("главный экран: раскладка возвращена")
            return
        }
        homeBeforePinned = Settings.shared.homeWidgets
        controller.debugCloseOverlay()
        Settings.shared.homeWidgets = [
            HomeWidget(id: 0, kind: .pinnedNotes, size: .large),
            HomeWidget(id: 1, kind: .pinnedNotes, size: .wide),
            HomeWidget(id: 2, kind: .pinnedNotes, size: .full),
        ]
        DebugLog.write("главный экран: плитки закреплённых заметок")
        controller.debugExpand(seconds: 8)
    }

    /// Раскладка человека на время показа плиток шкалы дня.
    private var homeBeforeTimeline: [HomeWidget]?
    private var timelinePage = 0

    /// Шкала дня во всех своих размерах: две вёрстки сразу — лента в один
    /// ряд и шкала с часами в два. Пять плиток в четыре ряда не влезают,
    /// поэтому идут страницами; после последней раскладка человека
    /// возвращается сама — главный экран трогать насовсем нельзя.
    @objc private func toggleHomeTimeline() {
        let pages = HomeWidgets.showcasePages(of: [.timeline])
        guard timelinePage < pages.count else {
            Settings.shared.homeWidgets = homeBeforeTimeline ?? HomeWidgets.standard
            homeBeforeTimeline = nil
            timelinePage = 0
            DebugLog.write("главный экран: раскладка возвращена")
            return
        }
        if homeBeforeTimeline == nil {
            homeBeforeTimeline = Settings.shared.homeWidgets
            controller.debugCloseOverlay()
        }
        let page = pages[timelinePage]
        Settings.shared.homeWidgets = page
        DebugLog.write("главный экран: шкала дня, страница \(timelinePage + 1) из \(pages.count) — "
            + page.map(\.size.title).joined(separator: ", "))
        timelinePage += 1
        controller.debugExpand(seconds: 8)
    }

    /// Раскладка человека на время показа плиток команд.
    private var homeBeforeCommands: [HomeWidget]?

    /// Плитка команд во всех размерах, с настоящими командами человека.
    ///
    /// Без них плитка показывала бы «Выберите команды в настройках» — то есть
    /// ровно не то, что надо снять: как встают ярлыки по клеткам и обрезается
    /// ли название в две строки. Повторный вызов возвращает прежнюю
    /// раскладку: главный экран человека трогать насовсем нельзя.
    @objc private func toggleHomeCommands() {
        if let saved = homeBeforeCommands {
            Settings.shared.homeWidgets = saved
            homeBeforeCommands = nil
            DebugLog.write("главный экран: раскладка возвращена")
            return
        }
        let ids = Settings.shared.quickCommands.filter(\.isConfigured).map(\.id)
        guard !ids.isEmpty else {
            DebugLog.write("плитка команд: настроенных команд нет — нечего показывать")
            return
        }
        homeBeforeCommands = Settings.shared.homeWidgets
        controller.debugCloseOverlay()
        // Порядок — от большой к маленькой: в четыре ряда влезают все пять
        // размеров, и страницами обходиться не приходится.
        Settings.shared.homeWidgets = [.large, .small, .wide, .threeWide, .full]
            .enumerated()
            .map { index, size in
                HomeWidget(id: index, kind: .commands, size: size, commands: ids)
            }
        DebugLog.write("плитка команд: пять размеров, команд в наборе — \(ids.count)")
        controller.debugExpand(seconds: 8)
    }

    /// Закрепить или открепить последнюю заметку — нажать булавку из сессии нечем.
    @objc private func togglePinNewestNote() {
        controller.debugTogglePinNewestNote()
    }

    /// Сценки кота — без ожидания в полчаса и без проверки условий:
    /// что мешало бы по-настоящему, пишется в журнал.
    @objc private func playCritter() { controller.debugCritter(nil) }
    @objc private func playCritterEyes() { controller.debugCritter(.eyes) }
    @objc private func playCritterTail() { controller.debugCritter(.tail) }
    @objc private func playCritterRun() { controller.debugCritter(.run) }
    @objc private func playCritterEars() { controller.debugCritter(.ears) }
    @objc private func playCritterPaw() { controller.debugCritter(.paw) }
    @objc private func playCritterSleep() { controller.debugCritter(.sleep) }
    @objc private func playCritterUpside() { controller.debugCritter(.upside) }
    @objc private func playCritterYarn() { controller.debugCritter(.yarn) }
    @objc private func playCritterAngry() { controller.debugCritter(.angry) }
    @objc private func playCritterFist() { controller.debugCritter(.fist) }
    @objc private func playCritterKiss() { controller.debugCritter(.kiss) }
    @objc private func playCritterChase() { controller.debugCritter(.chase) }
    @objc private func playCritterHunt() { controller.debugCritter(.hunt) }
    @objc private func playCritterCool() { controller.debugCritter(.cool) }
    @objc private func playCritterSmoke() { controller.debugCritter(.smoke) }
    @objc private func playCritterMouse() { controller.debugCritter(.mouse) }
    @objc private func playCritterBeach() { controller.debugCritter(.beach) }
    @objc private func playCritterBird() { controller.debugCritter(.bird) }
    @objc private func playCritterWatch() { controller.debugCritter(.watch) }
    @objc private func playCritterWinter() { controller.debugCritter(.winter) }
    @objc private func playCritterKittens() { controller.debugCritter(.kittens) }
    @objc private func playCritterFlowers() { controller.debugCritter(.flowers) }
    @objc private func playCritterTank() { controller.debugCritter(.tank) }
    @objc private func playCritterEaster() { controller.debugCritter(.easter) }
    @objc private func playCritterPumpkin() { controller.debugCritter(.pumpkin) }
    @objc private func playCritterValentine() { controller.debugCritter(.valentine) }
    @objc private func playCritterRibbon() { controller.debugCritter(.ribbon) }
    @objc private func playCritterDragon() { controller.debugCritter(.dragon) }
    @objc private func playCritterRocket() { controller.debugCritter(.rocket) }
    @objc private func playWeatherScene() { controller.debugWeatherScene(nil) }
    @objc private func playWeatherChange() { controller.debugWeatherScene(.rain) }
    @objc private func playWeatherHeavySnow() { controller.debugWeatherScene(.heavySnow) }
    @objc private func playWeatherBlizzard() { controller.debugWeatherScene(.blizzard) }
    @objc private func playWeatherSun() { controller.debugWeatherScene(.sun) }
    @objc private func playWeatherClouds() { controller.debugWeatherScene(.clouds) }
    @objc private func playWeatherFog() { controller.debugWeatherScene(.fog) }
    @objc private func playWeatherDrizzle() { controller.debugWeatherScene(.drizzle) }
    @objc private func playWeatherRain() { controller.debugWeatherScene(.rain) }
    @objc private func playWeatherSnow() { controller.debugWeatherScene(.snow) }
    @objc private func playWeatherThunder() { controller.debugWeatherScene(.thunder) }
    @objc private func playWeatherWind() { controller.debugWeatherScene(.wind) }

    /// Черновик заметки со списком с галочками.
    @objc private func showChecklist() {
        controller.debugChecklist()
    }

    @objc private func resetHome() {
        homePage = 0
        Settings.shared.resetHomeWidgets()
        DebugLog.write("главный экран: раскладка по умолчанию")
    }

    @objc private func showMonitor() {
        controller.debugToggleMonitor()
    }

    @objc private func showFeeds() { controller.openFeeds() }
    @objc private func showFeedsSites() {
        controller.feedsPanel.mode = .sites
        controller.openFeeds()
    }
    @objc private func runDigest() { controller.debugRunDigest() }
    @objc private func suggestDigestTopics() {
        controller.digest.suggestTopics(noteTitles: controller.notes.notes.map(\.title))
    }
    @objc private func testDigestPill() { controller.debugDigestPill() }
    @objc private func checkWatches() { controller.debugWatchCheck() }
    @objc private func probeWatch() { controller.debugWatchProbe() }
    @objc private func testWatchPill() { controller.debugWatchPill() }

    @objc private func showTimer() {
        controller.debugToggleTimer()
    }

    @objc private func runTimer() {
        controller.debugRunTimer()
    }

    @objc private func runStopwatch() {
        controller.debugRunStopwatch()
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

    // MARK: - Помощник

    @objc private func dictateIntoNote() { controller.dictateNote() }

    @objc private func askByVoice() { controller.debugAskByVoice("что я записывал про Trunook") }

    @objc private func dumpModelOffers() { controller.debugModelOffers() }
    @objc private func dumpEngine() { controller.debugEngine() }
    @objc private func startEngine() { controller.debugEngineStart() }
    @objc private func quitEngine() { controller.debugEngineQuit() }
    @objc private func verifyEngineImage() { controller.debugEngineVerify() }
    @objc private func installEngine() { controller.debugEngineInstall() }
    @objc private func pullEmbedModel() { controller.debugPullEmbed() }
    @objc private func pullModelPair() { controller.debugPullPair() }

    @objc private func dumpAgentTools() { controller.debugAgentTools() }
    @objc private func dumpAgentTime() { controller.debugAgentTime() }
    @objc private func showAgentSteps() { controller.debugAgentSteps() }

    @objc private func stepAnswerHighlight() { controller.debugAnswerHighlight(steps: 2) }

    @objc private func askFollowUp() { controller.debugFollowUp() }

    @objc private func askMonday() { controller.debugAskByVoice("а какие дела на понедельник?") }
    @objc private func showAgentCard() { controller.debugAgentCard(kind: .createEvent) }
    @objc private func showAgentCardNote() { controller.debugAgentCard(kind: .createNote) }
    @objc private func runAgentTimer() { controller.debugAgentAsk("поставь таймер на 10 минут") }
    @objc private func runAgentAgenda() { controller.debugAgentAsk("что у меня сегодня по плану") }
    /// Справка о приложении живьём: вопрос уходит модели, а она обязана
    /// сходить за ответом в справочник, а не рассказать о Trunook из головы.
    @objc private func askAppHelp() { controller.debugAgentAsk("какие функции есть в приложении?") }
    @objc private func askAppHelpSetting() { controller.debugAgentAsk("а как настроить новостную сводку?") }

    /// Список инструментов под полем — по нему снимается вёрстка.
    @objc private func showSlashList() { controller.debugSlashList() }

    /// Пример из задачи слово в слово: группа выбрана, вопрос уходит
    /// с одними её инструментами.
    @objc private func askWithSlash() {
        controller.debugSlashAsk("/настройки как включить уведомления о воде?")
    }

    /// Длинный ответ, оборванный через четыре секунды: кнопку «Остановить»
    /// из сессии не нажать.
    @objc private func askAndStop() {
        controller.debugStopAfter(4, question: "расскажи подробно, как устроен фотосинтез")
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

    @objc private func missingNote() {
        controller.debugMissingNote()
    }

    @objc private func showCalendar() {
        controller.debugCalendar()
    }

    @objc private func showWater() {
        controller.debugWater()
    }

    @objc private func showWaterPill() {
        controller.debugWaterPill()
    }

    @objc private func showWaterVessel() {
        controller.debugWaterVessel()
    }

    @objc private func showCalendarTimeline() {
        controller.debugCalendarTimeline()
    }

    @objc private func showQuickRing() {
        controller.debugQuickRing()
    }

    /// Имя с цифрой: `editNote` уже занято правкой заметки, а совпадение
    /// селекторов ловится не компилятором, а тишиной в ответ на событие.
    @objc private func editEvent2() {
        controller.debugEditEvent()
    }

    @objc private func composeEvent() {
        controller.debugComposeEvent()
    }

    @objc private func editSeries() {
        controller.debugEditSeries()
    }

    @objc private func editEventWithNotes() {
        controller.debugEditEventWithNotes()
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

    /// Список «@»: панель с набранной собакой в поле. Нажать её из сессии
    /// нечем, а без неё списка не увидеть вовсе.
    @objc private func mention() {
        controller.debugMention()
    }

    /// Весь круг с указанием: выбрать встречу и попросить перенести.
    /// Останавливается карточкой подтверждения — календарь не трогается.
    @objc private func mentionRun() {
        controller.debugMentionRun()
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

    /// Снимок полоски на чужом экране — в режиме «Все экраны».
    @objc private func shotMirror() {
        controller.snapshotMirror()
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

    /// Окна, кнопки и меню Zoom и Телемоста — по ним и пишется таблица
    /// подписей для родных приложений.
    @objc private func dumpMeetingApps() {
        controller.meeting.dumpApps()
    }

    /// Доходит ли нажатие: подпись кнопки читается до и после.
    ///
    /// Успех самого нажатия ничего не значит — на веб-встрече `AXPress`
    /// возвращал успех, а страница его не слышала. Меняется подпись —
    /// значит, дошло. Рука выбрана нарочно: она не трогает ни звук,
    /// ни камеру, и её видно в самом звонке.
    @objc private func probeMeetingPress() {
        // Рука — если она есть: она не трогает ни звук, ни камеру. У Zoom
        // её нет вовсе (в меню её не держат), и там проверяем микрофон.
        let action: MeetingAction = controller.meeting.availableActions.contains(.hand)
            ? .hand
            : .microphone
        controller.meeting.probePress(action)
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

    /// Проба захвата звука и расшифровки — тем процессом, который ими
    /// и пользуется. Из скрипта ответ был бы чужой: у него другая подпись.
    @objc private func audioProbe() {
        AudioProbe.run()
    }

    /// Список звуковых устройств в журнал: кнопки перебора в панели встречи
    /// нажать из сессии нечем, а увидеть, между чем они перебирают, нужно.
    @objc private func dumpAudioDevices() {
        DebugLog.write("звук: вывод — "
            + AudioDevices.outputs().map(\.name).joined(separator: ", "))
        DebugLog.write("звук: ввод — "
            + AudioDevices.inputs().map(\.name).joined(separator: ", "))
        DebugLog.write("звук: сейчас вывод \(AudioDevices.defaultOutput?.name ?? "—"), "
            + "ввод \(AudioDevices.defaultInput?.name ?? "—")")
    }

    /// Качает языковой набор расшифровки — тот же путь, что у кнопки
    /// «Скачать язык» в настройках. Нажать её из сессии нечем, а проверить
    /// надо: без набора расшифровка молча отдаёт пустой текст.
    @objc private func installLanguage() {
        guard #available(macOS 26, *) else { return }
        let locale = settings.transcribeLocale
        DebugLog.write("расшифровка: прошу набор для \(locale.identifier)")
        Task { @MainActor in
            do {
                try await Transcriber.install(for: locale) { share in
                    if Int(share * 100) % 20 == 0 {
                        DebugLog.write("расшифровка: \(Int(share * 100))%")
                    }
                }
                DebugLog.write("расшифровка: набор готов")
            } catch {
                DebugLog.write("расшифровка: набор не поставился — \(error)")
            }
        }
    }

    /// Расшифровывает последнюю сделанную запись, ничего не создавая.
    ///
    /// Проверять расшифровку новой записью значило бы класть в хранилище
    /// человека ещё одну заметку на каждый заход. Здесь берётся то, что уже
    /// записано, и результат уходит в журнал.
    @objc private func transcribeLast() {
        guard #available(macOS 26, *) else { return }
        guard let url = controller.recorder.newestRecording() else {
            DebugLog.write("расшифровка: записей не нашлось")
            return
        }
        DebugLog.write("расшифровка: беру \(url.lastPathComponent)")
        Task { @MainActor in
            do {
                let text = try await Transcriber.text(
                    of: url, locale: self.settings.transcribeLocale
                )
                DebugLog.write("расшифровка: вышло — «\(text.prefix(300))»")
            } catch {
                DebugLog.write("расшифровка: не вышла — \(error)")
            }
        }
    }

    /// Начинает запись встречи — микрофон и звук системы.
    @objc private func startRecording() {
        controller.recorder.start(withSystemAudio: true)
    }

    @objc private func stopRecording() {
        controller.recorder.stop()
    }

    /// Весь путь целиком: пишем десять секунд и останавливаемся сами.
    ///
    /// Десять секунд — чтобы успеть что-нибудь сказать и включить звук,
    /// а дальше проверяется всё остальное: сведение, расшифровка, пересказ
    /// и готовая заметка. Нажимать «стоп» из сессии нечем.
    @objc private func runRecording() {
        controller.recorder.start(withSystemAudio: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.controller.recorder.stop()
        }
    }

    @objc private func ollamaEcho() {
        controller.debugOllamaEcho()
    }

    @objc private func runSlot1() {
        controller.debugRunSlot(0)
    }

    @objc private func runCaptureCommand() {
        controller.debugCaptureRun()
    }

    @objc private func probePaste() {
        controller.debugPasteProbe()
    }

    @objc private func stepPasteRow() {
        controller.debugPasteRow()
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

    /// Панель блокировки клавиатуры.
    @objc private func showKeyboardLock() {
        controller.openKeyboardLock()
    }

    /// Заглушить клавиатуру на 30 секунд тем же путём, что и кнопка панели.
    @objc private func runKeyboardLock() {
        controller.openKeyboardLock()
        controller.lockKeyboard(seconds: 30)
    }

    @objc private func expireKeyboardLock() {
        controller.debugExpireKeyboardLock()
    }



    private func add(to menu: NSMenu, title: String, action: Selector, key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    /// Чем встретить этот запуск.
    ///
    /// Первый — окном знакомства: оно берёт на себя запрос доступов. Первый
    /// после обновления — залпом конфетти из чёлки и описанием выпуска: иначе
    /// обновление проходит совершенно незаметно, и о том, что изменилось,
    /// человек не узнаёт никогда.
    ///
    /// Задержка в обоих случаях — чтобы окно не выскочило раньше, чем система
    /// дорисует рабочий стол после входа в неё.
    private func greetLaunch() {
        let kind = LaunchKind.resolve(
            current: AppInfo.shortVersion,
            lastRun: settings.lastRunVersion,
            hasSeenWelcome: settings.hasSeenWelcome
        )
        // Запись сразу за чтением: дальше по коду запуск уже не «первый»,
        // а падение между показом и записью повторило бы залп на следующем
        // запуске — мелочь, но необъяснимая для того, кто её увидит.
        settings.lastRunVersion = AppInfo.shortVersion

        switch kind {
        case .ordinary:
            return
        case .firstEver:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.openWelcome()
            }
        case let .afterUpdate(from):
            DebugLog.write("запуск после обновления с \(from ?? "неизвестной версии")")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.celebrateUpdate()
            }
        }
    }

    /// Залп и описание выпуска. Окно открывается сразу за залпом, а не после
    /// него: конфетти летит поверх всего, и ждать его конца значило бы держать
    /// человека две секунды перед пустым экраном.
    private func celebrateUpdate() {
        confetti.fire(on: controller.notchScreen)
        openReleaseNotes()
    }

    @objc private func openWelcome() {
        showWelcome(mode: .tour)
    }

    /// Окно знакомства, открытое сразу описанием выпусков.
    @objc private func openReleaseNotes() {
        showWelcome(mode: .notes)
    }

    private func showWelcome(mode: WelcomeModel.Mode) {
        welcomeWindow.show(
            calendar: controller.calendar,
            launchAtLogin: launchAtLogin,
            weather: controller.weather,
            mode: mode,
            onHotKeysChanged: { [weak self] in self?.controller.installHotKeys() }
        )
    }

    /// Залп из чёлки без обновления: нажать кнопку и дождаться настоящего
    /// выпуска ради одной анимации — плохой цикл разработки.
    @objc private func testConfetti() {
        confetti.fire(on: controller.notchScreen)
    }

    /// Обход хранилища: сколько файлов видно и сколько из них свои.
    @objc private func obsidianScan() {
        guard let vault = controller.obsidian.vault else {
            DebugLog.write("Obsidian: папка не выбрана")
            return
        }
        guard vault.isReachable else {
            DebugLog.write("Obsidian: папка недоступна — \(vault.url.path)")
            return
        }
        let files = VaultScanner.files(in: vault)
        let own = files.filter { vault.isOwn($0.path) }.count
        DebugLog.write(
            "Obsidian: \(vault.url.path), файлов \(files.count), своих \(own), "
                + "хранилище=\(vault.looksLikeVault)"
        )
    }

    /// Полная сверка прямо сейчас.
    @objc private func obsidianSync() {
        controller.obsidian.sync(manual: true)
    }

    /// Пересчёт векторов и связей.
    @objc private func obsidianLinks() {
        controller.linker.refreshAll()
    }

    /// Снимок залпа в ~/Library/Logs/Trunook-confetti.png.
    @objc private func shotConfetti() {
        confetti.snapshotMidflight()
    }

    @objc private func openSettings() {
        settingsWindow.show(
            settings: settings,
            launchAtLogin: launchAtLogin,
            calendar: controller.calendar,
            clipboard: controller.clipboard,
            weather: controller.weather,
            notes: controller.notes,
            obsidian: controller.obsidian,
            linker: controller.linker,
            updates: controller.updates,
            digest: controller.digest,
            siteWatch: controller.siteWatch,
            onHotKeysChanged: { [weak self] in self?.controller.installHotKeys() },
            onLayoutChanged: { [weak self] in self?.controller.relayout() },
            onOpenWelcome: { [weak self] in self?.openWelcome() },
            onOpenReleaseNotes: { [weak self] in self?.openReleaseNotes() },
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
        controller.checkForUpdatesManually()
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
