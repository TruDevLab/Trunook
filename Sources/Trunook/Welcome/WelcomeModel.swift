import TrunookXPC
import AppKit
import EventKit

/// Состояние окна знакомства: текущий шаг и живое состояние доступов.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class WelcomeModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case intro, gestures, shortcuts, permissions, done

        var id: Int { rawValue }

        /// Надпись над заголовком — она же метка шага в индикаторе.
        var eyebrow: String {
            switch self {
            case .intro: return t("ЗНАКОМСТВО")
            case .gestures: return t("УПРАВЛЕНИЕ")
            case .shortcuts: return t("СОЧЕТАНИЯ")
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
            case .gestures: return t("Управление")
            case .shortcuts: return t("Сочетания клавиш")
            case .permissions: return t("Доступы")
            case .done: return t("Готово")
            }
        }
    }

    @Published var step: Step = .intro
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
    func start() {
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
