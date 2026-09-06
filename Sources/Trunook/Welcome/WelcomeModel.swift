import TrunookXPC
import AppKit
import EventKit

/// Состояние окна знакомства: текущий шаг и живое состояние доступов.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class WelcomeModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case intro, features, gestures, shortcuts, ai, permissions, done

        var id: Int { rawValue }

        /// Надпись над заголовком — она же метка шага в индикаторе.
        var eyebrow: String {
            switch self {
            case .intro: return t("ЗНАКОМСТВО")
            case .features: return t("ВОЗМОЖНОСТИ")
            case .gestures: return t("УПРАВЛЕНИЕ")
            case .shortcuts: return t("СОЧЕТАНИЯ")
            case .ai: return t("ПОМОЩНИК")
            case .permissions: return t("ДОСТУПЫ")
            case .done: return t("ГОТОВО")
            }
        }

        /// То же имя обычным регистром — для диктора.
        ///
        /// Не `eyebrow`: тот набран прописными, и VoiceOver читает такие
        /// строки по буквам, «эс-о-че-е-те-а-эн-и-я». Глазу разрядка
        /// и капитель нужны, уху — нет.
        var title: String {
            switch self {
            case .intro: return t("Знакомство")
            case .features: return t("Возможности")
            case .gestures: return t("Управление")
            case .shortcuts: return t("Сочетания клавиш")
            case .ai: return t("Помощник")
            case .permissions: return t("Доступы")
            case .done: return t("Готово")
            }
        }
    }

    /// Чем занято окно: рассказом о приложении или описанием выпусков.
    ///
    /// Режим, а не шестой шаг: шаги идут по порядку и ведут к «Начать»,
    /// а описание читают вразнобой и уходят из него обратно. Шестым шагом
    /// оно встало бы человеку поперёк знакомства, которое он и открыл.
    enum Mode: Equatable {
        case tour
        case notes
    }

    /// Раздел на шаге «Возможности».
    ///
    /// Сетка плиток на первом экране отвечает на «что это вообще умеет»
    /// одним взглядом — и больше ни на что: под словом «Полка» не угадать,
    /// что файлы на неё кладут перетаскиванием на чёлку. Плиток к тому же
    /// стало больше, чем помещается в ряд.
    ///
    /// Поэтому подробности — своим шагом, списком слева и описанием справа.
    /// Читают его вразнобой: человек ищет то, чего не понял, а не проходит
    /// подряд.
    enum Feature: String, CaseIterable, Identifiable {
        case music, calendar, meetings, capture, assistant, voice
        case notes, record, clipboard, shelf, timer, monitor
        case teleprompter, weather, battery, caffeine

        var id: String { rawValue }

        var title: String {
            switch self {
            case .music: return t("Музыка")
            case .calendar: return t("Календарь и задачи")
            case .meetings: return t("Встречи")
            case .capture: return t("Захват текста")
            case .assistant: return t("Помощник")
            case .voice: return t("Голос")
            case .notes: return t("Заметки")
            case .record: return t("Запись разговора")
            case .clipboard: return t("Буфер обмена")
            case .shelf: return t("Полка")
            case .timer: return t("Таймер")
            case .monitor: return t("Нагрузка")
            case .teleprompter: return t("Телесуфлер")
            case .weather: return t("Погода")
            case .battery: return t("Батарея")
            case .caffeine: return t("Чашка кофе")
            }
        }

        var symbol: String {
            switch self {
            case .music: return "music.note"
            case .calendar: return "calendar"
            case .meetings: return "video.fill"
            case .capture: return "text.viewfinder"
            case .assistant: return "sparkles"
            case .voice: return "waveform"
            case .notes: return "list.bullet.rectangle"
            case .record: return "waveform.circle.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .shelf: return "tray.full.fill"
            case .timer: return "timer"
            case .monitor: return "gauge.with.dots.needle.67percent"
            case .teleprompter: return "text.alignleft"
            case .weather: return "cloud.sun.fill"
            case .battery: return "bolt.fill"
            case .caffeine: return "cup.and.saucer.fill"
            }
        }

        /// Одна фраза о том, что это. Её видно рядом с названием в списке.
        var summary: String {
            switch self {
            case .music: return t("Что играет — прямо в вырезе")
            case .calendar: return t("Ближайшая встреча и задачи на сегодня")
            case .meetings: return t("Управление звонком, не переключаясь на вкладку")
            case .capture: return t("Выделенный текст — сразу в работу")
            case .assistant: return t("Вопрос модели без единого окна")
            case .voice: return t("Спросить вслух и услышать ответ")
            case .notes: return t("Записи с именем от модели и поиском по смыслу")
            case .record: return t("Разговор становится заметкой с задачами")
            case .clipboard: return t("История копирований под рукой")
            case .shelf: return t("Файлы на чёлке между окнами")
            case .timer: return t("Отсчёт виден, не занимая экрана")
            case .monitor: return t("Процессор, память и диск одним взглядом")
            case .teleprompter: return t("Текст у самой камеры")
            case .weather: return t("Предупреждает о дожде заранее")
            case .battery: return t("Заряд и питание без строки меню")
            case .caffeine: return t("Экран не гаснет, пока горит чашка")
            }
        }

        /// Подробности: два-четыре предложения. Здесь и живёт то, чего
        /// не угадать по названию.
        var detail: String {
            switch self {
            case .music:
                return t("Свёрнутый вырез показывает обложку и название трека. Свайп двумя пальцами поперёк острова переключает трек, не убирая курсор. Работает с Музыкой, Spotify и всем, что отдаёт сведения системе.")
            case .calendar:
                return t("Ближайшая встреча появляется в вырезе заранее, а перед началом остров раздвигается обратным отсчётом. Рядом задачи из Напоминаний и Things 3. Нажатие открывает запись в её приложении.")
            case .meetings:
                return t("Пока идёт встреча в браузере, наведение на вырез показывает кнопки: микрофон, камера, демонстрация, поднять руку, выйти. Там же переключение динамиков и микрофона и кнопка записи. Работает с Телемостом, Google Meet, Zoom и Teams.")
            case .capture:
                return t("⌃⌥C забирает выделенное в любом окне и открывает панель с ним. Ниже — список команд: перевести, исправить ошибки, пересказать. Команды свои, у каждой может быть своя модель и своя клавиша.")
            case .assistant:
                return t("Вопрос набирается прямо в вырезе, ответ идёт потоком. Модель местная — Ollama или совместимый сервер, — либо облачная по ключу. Ответ можно скопировать, вставить в текущее окно или сохранить заметкой.")
            case .voice:
                return t("Модификатор, нажатый дважды, начинает слушать. Панель при этом не раскрывается: она закрыла бы то, чем вы заняты, — вместо неё оживает сам остров. Речь распознаётся на компьютере и наружу не уходит.")
            case .notes:
                return t("⌃⌥Z открывает пустую заметку, ⌃⌥⇧Z записывает выделенное, не открывая ничего. Имя придумывает модель. Поиск идёт по смыслу, а не по словам, и умеет искать по хранилищу Obsidian, если синхронизация включена.")
            case .record:
                return t("Кнопка в панели встречи пишет и вас, и собеседников; ⌃⌥R — только вас. Сказанное переводится в текст на самом компьютере и ложится заметкой: название, пересказ и задачи отдельным списком. Запись прикладывается к заметке и играет прямо из списка.")
            case .clipboard:
                return t("Приложение помнит скопированное — текст, ссылки и картинки. ⌃⌥V открывает историю, цифры вставляют нужную запись. Пароли из менеджеров и служебные копирования не сохраняются.")
            case .shelf:
                return t("Ведите файлы на чёлку — вырез раскроется полкой и примет их. Оттуда их вытаскивают в любое окно. Удобно, когда файл нужно перенести между приложениями, а окна закрывают друг друга.")
            case .timer:
                return t("⌃⌥T открывает таймер и секундомер. Пока идёт отсчёт, чёлка раздвигается счётом — нажатие по нему возвращает панель. По окончании звучит сигнал и предлагается перерыв.")
            case .monitor:
                return t("⌃⌥M показывает загрузку процессора, занятую память и место на диске. Нажатие по плитке открывает Мониторинг системы.")
            case .teleprompter:
                return t("⌃⌥P разворачивает текст под чёлкой — там, где стоит камера. С оформлением и автопрокруткой: читая с середины экрана, смотришь мимо объектива, и это видно собеседнику.")
            case .weather:
                return t("Вырез предупреждает о дожде и снеге заранее. Место берётся по геопозиции или называется вручную; наружу уходят только округлённые координаты.")
            case .battery:
                return t("Подключение и отключение питания видно плашкой, низкий заряд — предупреждением. Порог настраивается.")
            case .caffeine:
                return t("Чашка не даёт экрану гаснуть заданный срок. Пока она горит, вырез раздвинут полоской с остатком времени.")
            }
        }
    }

    @Published var mode: Mode = .tour
    @Published var step: Step = .intro
    @Published var feature: Feature = .music
    @Published private(set) var accessibilityTrusted = AccessibilityAccess.isTrusted
    /// Проверяется опросом по той же причине: TCC своё решение не отдаёт,
    /// а в теле вида ходить на диск нельзя — вид перерисовывается постоянно.
    @Published private(set) var filesGranted = FilesAccess.isGranted
    /// Микрофон и распознавание речи. Опросом по той же причине, что
    /// и остальные: решение принимается в системном диалоге, а уведомления
    /// о нём приложению не приходит.
    @Published private(set) var microphoneAccess = VoiceAccess.microphone
    @Published private(set) var speechAccess = VoiceAccess.recognition

    private let calendar: CalendarService
    private let settings: Settings
    private var pollTimer: Timer?

    init(calendar: CalendarService, settings: Settings = .shared) {
        self.calendar = calendar
        self.settings = settings
    }

    // MARK: - Жизненный цикл

    /// Доступы выдаются в Системных настройках, за пределами приложения,
    /// и уведомления об этом не приходит. Пока окно открыто — опрашиваем.
    func start(mode: Mode = .tour) {
        self.mode = mode
        step = .intro
        // Отладочный вход: кликать по кнопкам из сессии нечем, а снимать
        // нужно все четыре шага.
        //   defaults write com.trunook.Trunook debugWelcomeStep 2
        if DebugLog.isEnabled,
           let forced = Step(rawValue: UserDefaults.standard.integer(forKey: "debugWelcomeStep")) {
            step = forced
        }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refresh() {
        let trusted = AccessibilityAccess.isTrusted
        if trusted != accessibilityTrusted {
            accessibilityTrusted = trusted
            DebugLog.write("универсальный доступ: \(trusted ? "выдан" : "снят")")
        }
        let files = FilesAccess.isGranted
        if files != filesGranted {
            filesGranted = files
            DebugLog.write("доступ к файлам: \(files ? "выдан" : "закрыт")")
        }
        refreshVoiceAccess()
        calendar.refreshAuthorization()
    }

    /// Перечитать доступы голоса.
    ///
    /// Отдельно от общего опроса ещё и потому, что их запрашивают кнопкой:
    /// ответ на системный диалог приходит замыканием, и ждать до секунды,
    /// пока строка обновится сама, значило бы показывать «не запрошен» уже
    /// после того, как доступ выдан.
    private func refreshVoiceAccess() {
        let microphone = VoiceAccess.microphone
        if microphone != microphoneAccess {
            microphoneAccess = microphone
            DebugLog.write("микрофон: \(microphone)")
        }
        let speech = VoiceAccess.recognition
        if speech != speechAccess {
            speechAccess = speech
            DebugLog.write("распознавание речи: \(speech)")
        }
    }

    // MARK: - Шаги

    /// Надпись над заголовком. В режиме описания она своя: шага там нет.
    var eyebrow: String {
        mode == .notes ? t("ОПИСАНИЕ") : step.eyebrow
    }

    func toggleNotes() {
        mode = mode == .notes ? .tour : .notes
        Haptics.tap()
    }

    var canGoBack: Bool { step != .intro }
    var isLastStep: Bool { step == .done }

    func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        go(to: following)
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    func go(to target: Step) {
        guard target != step else { return }
        step = target
        Haptics.tap()
    }

    // MARK: - Доступы

    /// Доступы, о которых стоит рассказать. Автоматизация для Things 3
    /// и музыкальных приложений сюда не входит: система спрашивает о ней
    /// в момент первого обращения и объясняет всё сама.
    enum Permission: String, CaseIterable, Identifiable {
        case calendar, reminders, accessibility, microphone, speech, files

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar: return t("Календарь")
            case .reminders: return t("Напоминания")
            case .accessibility: return t("Универсальный доступ")
            case .microphone: return t("Микрофон")
            case .speech: return t("Распознавание речи")
            case .files: return t("Файлы и папки")
            }
        }

        var icon: String {
            switch self {
            case .calendar: return "calendar"
            case .reminders: return "checklist"
            case .accessibility: return "hand.raised"
            case .microphone: return "mic"
            case .speech: return "waveform"
            case .files: return "folder"
            }
        }

        var explanation: String {
            switch self {
            case .calendar:
                return t("Встречи, обратный отсчёт и кнопка «Присоединиться».")
            case .reminders:
                return t("Напоминания со сроком — вырез предупредит заранее.")
            case .accessibility:
                return t("Выделенный текст для запросов к модели, кнопки онлайн-встречи и вызов голосового ассистента двойным нажатием.")
            case .microphone:
                return t("Голосовому ассистенту — чтобы услышать вопрос.")
            case .speech:
                return t("Перевод речи в текст. Идёт на самом компьютере: записи никуда не отправляются.")
            case .files:
                return t("Полке — чтобы показать миниатюру и размер файла с рабочего стола или из документов.")
            }
        }
    }

    enum PermissionState {
        case granted
        case notAsked
        case denied

        var label: String {
            switch self {
            case .granted: return t("выдан")
            case .notAsked: return t("не запрошен")
            case .denied: return t("закрыт")
            }
        }
    }

    func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .calendar: return Self.map(calendar.eventsAccess)
        case .reminders: return Self.map(calendar.remindersAccess)
        case .accessibility: return accessibilityTrusted ? .granted : .notAsked
        case .microphone: return Self.map(microphoneAccess)
        case .speech: return Self.map(speechAccess)
        case .files: return filesGranted ? .granted : .notAsked
        }
    }

    /// Состояние доступа голоса — в общий вид строки.
    ///
    /// Своё перечисление у `VoiceAccess` потому, что TCC у микрофона
    /// и у календаря разный: `EKAuthorizationStatus` знает про «полный»
    /// и «только запись», а у микрофона таких оттенков нет.
    private static func map(_ state: VoiceAccess.State) -> PermissionState {
        switch state {
        case .granted: return .granted
        case .notAsked: return .notAsked
        case .denied: return .denied
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Подпись кнопки в строке доступа. Универсальный доступ выдаётся руками
    /// в Системных настройках, поэтому «Запросить» там — это про диалог
    /// со ссылкой туда, а не про саму выдачу.
    func actionTitle(for permission: Permission) -> String {
        switch state(of: permission) {
        case .granted: return t("Выдан")
        case .notAsked:
            switch permission {
            case .accessibility, .files: return t("Открыть настройки")
            case .calendar, .reminders, .microphone, .speech: return t("Разрешить")
            }
        case .denied: return t("Открыть настройки")
        }
    }

    func act(on permission: Permission) {
        guard state(of: permission) != .granted else { return }
        let asked = state(of: permission) == .notAsked

        switch permission {
        case .calendar:
            if asked { calendar.requestEventsAccess() } else { CalendarService.openPrivacySettings(.calendars) }
        case .reminders:
            if asked { calendar.requestRemindersAccess() } else { CalendarService.openPrivacySettings(.reminders) }
        case .accessibility:
            // Диалог показывается один раз за запуск процесса, поэтому сразу
            // за ним открываем раздел настроек: на второе нажатие иначе
            // не произошло бы вообще ничего.
            AccessibilityAccess.request()
            AccessibilityAccess.openSettings()
        case .microphone:
            if asked {
                VoiceAccess.requestMicrophone { [weak self] _ in self?.refreshVoiceAccess() }
            } else {
                VoiceAccess.openMicrophoneSettings()
            }
        case .speech:
            if asked {
                VoiceAccess.requestRecognition { [weak self] _ in self?.refreshVoiceAccess() }
            } else {
                VoiceAccess.openRecognitionSettings()
            }
        case .files:
            // Первое же обращение к защищённой папке само вызывает системный
            // диалог. Если решение уже принято, диалога не будет — тогда
            // помогут только настройки, поэтому открываем их следом.
            _ = FilesAccess.isGranted
            FilesAccess.openSettings()
        }
        Haptics.tap()
    }

    /// Нужен ли доступ, чтобы включённые функции работали. По нему решаем,
    /// подсвечивать ли строку как незакрытую.
    func isRequired(_ permission: Permission) -> Bool {
        switch permission {
        case .calendar: return settings.calendarEnabled
        case .reminders: return settings.remindersEnabled
        // Голос сюда добавился не для полноты: вызов идёт глобальным
        // монитором событий, а тот без Универсального доступа нажатий
        // не получает вовсе.
        case .accessibility:
            return settings.quickCommandsEnabled
                || settings.meetingControlsEnabled
                || settings.voiceEnabled
        case .microphone, .speech: return settings.voiceEnabled
        case .files: return settings.shelfEnabled
        }
    }

    var pendingCount: Int {
        Permission.allCases.filter { isRequired($0) && state(of: $0) != .granted }.count
    }
}
