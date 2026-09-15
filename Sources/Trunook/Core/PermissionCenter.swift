import TrunookXPC
import AppKit
import Combine
import CoreLocation
import EventKit

/// Доступы приложения: какой выдан, какой нужен и что нажать, чтобы выдать.
///
/// Одна модель на два окна — знакомство и настройки. Жила внутри
/// `WelcomeModel`, и в настройках доступов не было вовсе: отказанный Календарь
/// или геопозиция обнаруживались по пустым панелям. Вынесена, а не повторена:
/// два расчёта одного и того же расходятся первыми.
final class PermissionCenter: ObservableObject {
    enum Permission: String, CaseIterable, Identifiable {
        case calendar, reminders, accessibility, microphone, speech, files, location

        var id: String { rawValue }

        /// В знакомстве — без геопозиции: её спрашивают только у того, кто
        /// выбрал погоду по положению, и объяснять её каждому незачем.
        static var onboarding: [Permission] { allCases.filter { $0 != .location } }

        var title: String {
            switch self {
            case .calendar: return t("Календарь")
            case .reminders: return t("Напоминания")
            case .accessibility: return t("Универсальный доступ")
            case .microphone: return t("Микрофон")
            case .speech: return t("Распознавание речи")
            case .files: return t("Файлы и папки")
            case .location: return t("Геопозиция")
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
            case .location: return "location"
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
            case .location:
                return t("Погоде по положению. Наружу уходят координаты, округлённые до километра.")
            }
        }
    }

    enum State {
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

    @Published private(set) var accessibilityTrusted = AccessibilityAccess.isTrusted
    /// Проверяется опросом: TCC своё решение не отдаёт, а в теле вида ходить
    /// на диск нельзя — вид перерисовывается постоянно.
    @Published private(set) var filesGranted = FilesAccess.isGranted
    /// Микрофон и распознавание речи. Опросом по той же причине: решение
    /// принимается в системном диалоге, а уведомления о нём не приходит.
    @Published private(set) var microphoneAccess = VoiceAccess.microphone
    @Published private(set) var speechAccess = VoiceAccess.recognition

    private let calendar: CalendarService
    private let weather: WeatherService?
    private let settings: Settings
    private var pollTimer: Timer?
    /// Сколько окон сейчас смотрят на доступы: опрос живёт, пока хоть одно.
    private var watchers = 0
    private var forwarding: [AnyCancellable] = []

    init(calendar: CalendarService, weather: WeatherService? = nil, settings: Settings = .shared) {
        self.calendar = calendar
        self.weather = weather
        self.settings = settings
        // Календарь и погода публикуют свои доступы сами — строки
        // перерисовываются вслед за ними.
        forwarding.append(calendar.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        if let weather {
            forwarding.append(weather.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        }
    }

    // MARK: - Опрос

    /// Доступы выдаются в Системных настройках, за пределами приложения,
    /// и уведомления об этом не приходит. Пока окно открыто — опрашиваем.
    func start() {
        watchers += 1
        refresh()
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
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

    /// Отдельно от общего опроса: доступы голоса запрашивают кнопкой,
    /// и ждать до секунды, пока строка обновится сама, значило бы показывать
    /// «не запрошен» уже после того, как доступ выдан.
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

    // MARK: - Состояние

    func state(of permission: Permission) -> State {
        switch permission {
        case .calendar: return Self.map(calendar.eventsAccess)
        case .reminders: return Self.map(calendar.remindersAccess)
        case .accessibility: return accessibilityTrusted ? .granted : .notAsked
        case .microphone: return Self.map(microphoneAccess)
        case .speech: return Self.map(speechAccess)
        case .files: return filesGranted ? .granted : .notAsked
        case .location:
            switch weather?.authorization ?? CLLocationManager().authorizationStatus {
            case .authorized, .authorizedAlways: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        }
    }

    private static func map(_ state: VoiceAccess.State) -> State {
        switch state {
        case .granted: return .granted
        case .notAsked: return .notAsked
        case .denied: return .denied
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> State {
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
            case .calendar, .reminders, .microphone, .speech, .location: return t("Разрешить")
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
        case .location:
            if asked, let weather { weather.requestAccessIfNeeded() } else { WeatherService.openPrivacySettings() }
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
        // не получает вовсе. Раскладка окон двигает чужие окна им же.
        case .accessibility:
            return settings.quickCommandsEnabled
                || settings.meetingControlsEnabled
                || settings.voiceEnabled
                || settings.windowSnapEnabled
        case .microphone, .speech: return settings.voiceEnabled
        case .files: return settings.shelfEnabled
        case .location: return settings.weatherEnabled && settings.weatherSource == .location
        }
    }

    /// Сколько нужных доступов не выдано — в знакомстве.
    var pendingCount: Int {
        Permission.onboarding.filter { isRequired($0) && state(of: $0) != .granted }.count
    }
}
