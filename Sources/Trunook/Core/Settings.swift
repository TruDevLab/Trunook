import SwiftUI

/// Настройки приложения поверх UserDefaults.
///
/// Свойства сделаны вычисляемыми, а не `@Published`: значение по умолчанию
/// тогда живёт ровно в одном месте — в геттере, и его не нужно дублировать
/// в инициализаторе. Для SwiftUI есть `binding(_:)`.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Общее

    // Автозапуск здесь намеренно отсутствует: его состояние хранит система,
    // см. LaunchAtLogin.

    /// Язык интерфейса. Смену применяет `Localization` — здесь только
    /// хранение, иначе настройки знали бы про загрузку таблиц перевода.
    var language: Language {
        get { Language(rawValue: defaults.string(forKey: "language") ?? "") ?? .system }
        set {
            store(newValue.rawValue, "language")
            Localization.shared.apply(newValue)
        }
    }

    var hapticsEnabled: Bool {
        get { flag("hapticsEnabled", default: true) }
        set { store(newValue, "hapticsEnabled") }
    }

    /// Окно знакомства показано хотя бы раз.
    ///
    /// До этого момента приложение не запрашивает доступы само: диалоги
    /// системы, выскочившие через секунду после первого запуска без всяких
    /// объяснений, — верный способ получить отказ, а он необратим.
    var hasSeenWelcome: Bool {
        get { flag("hasSeenWelcome", default: false) }
        set { store(newValue, "hasSeenWelcome") }
    }

    /// Мурчание в ответ на поглаживание чёлки.
    ///
    /// Отдельный переключатель, а не общий с виброоткликом: звук слышат
    /// окружающие, и выключать его хочется независимо от вибрации.
    var purrEnabled: Bool {
        get { flag("purrEnabled", default: true) }
        set { store(newValue, "purrEnabled") }
    }

    /// Раскрывать вырез по наведению курсора.
    var expandOnHover: Bool {
        get { flag("expandOnHover", default: true) }
        set { store(newValue, "expandOnHover") }
    }

    // MARK: - Музыка

    var musicEnabled: Bool {
        get { flag("musicEnabled", default: true) }
        set { store(newValue, "musicEnabled") }
    }

    /// Показывать всплывающую подсказку при смене трека.
    /// Свайп поперёк переключает трек в другую сторону.
    ///
    /// Отдельно от системной «естественной прокрутки»: ту уже учитывает сам
    /// расчёт направления, а это — про вкус. Одним «вперёд» кажется движение
    /// пальцев влево, как листают ленту, другим вправо, как переворачивают
    /// страницу, и спорить тут не о чем.
    var swipeInverted: Bool {
        get { flag("swipeInverted", default: false) }
        set { store(newValue, "swipeInverted") }
    }

    var showTrackChanges: Bool {
        get { flag("showTrackChanges", default: true) }
        set { store(newValue, "showTrackChanges") }
    }

    // MARK: - Быстрые команды

    /// Запросы к модели — отдельно от самих команд: остальные типы работают
    /// без всякой Ollama, и требовать её ради «открыть папку» неправильно.
    var ollamaEnabled: Bool {
        get { flag("ollamaEnabled", default: false) }
        set { store(newValue, "ollamaEnabled") }
    }

    /// Пустое поле означает адрес по умолчанию — так пользователю не нужно
    /// знать про localhost, чтобы всё заработало.
    var ollamaURL: String {
        get {
            let stored = defaults.string(forKey: "ollamaURL") ?? ""
            return stored.isEmpty ? Self.defaultOllamaURL : stored
        }
        set { store(newValue, "ollamaURL") }
    }

    static let defaultOllamaURL = "http://localhost:11434"

    /// Сырое значение для поля ввода: пустое так и остаётся пустым.
    var ollamaURLRaw: String {
        get { defaults.string(forKey: "ollamaURL") ?? "" }
        set { store(newValue, "ollamaURL") }
    }

    var menuHotKey: HotKeySpec? {
        get { hotKey("menuHotKey", default: .menu) }
        set { storeHotKey(newValue, "menuHotKey") }
    }

    var ollamaModel: String {
        get { defaults.string(forKey: "ollamaModel") ?? "gemma4:12b" }
        set { store(newValue, "ollamaModel") }
    }

    /// Сколько держать модель загруженной после запроса.
    var ollamaKeepAlive: String {
        get { defaults.string(forKey: "ollamaKeepAlive") ?? "30m" }
        set { store(newValue, "ollamaKeepAlive") }
    }

    var quickCommandsEnabled: Bool {
        get { flag("quickCommandsEnabled", default: true) }
        set { store(newValue, "quickCommandsEnabled") }
    }

    var quickCommands: [QuickCommand] {
        get { QuickCommands.load(from: defaults) }
        set {
            objectWillChange.send()
            QuickCommands.save(newValue, to: defaults)
        }
    }

    /// Изменение одного слота без перезаписи всего набора вручную.
    func updateCommand(_ command: QuickCommand) {
        var all = quickCommands
        guard let index = all.firstIndex(where: { $0.id == command.id }) else { return }
        all[index] = command
        quickCommands = all
    }

    // MARK: - Буфер обмена

    var clipboardEnabled: Bool {
        get { flag("clipboardEnabled", default: true) }
        set { store(newValue, "clipboardEnabled") }
    }

    var clipboardHotKey: HotKeySpec? {
        get { hotKey("clipboardHotKey", default: .clipboard) }
        set { storeHotKey(newValue, "clipboardHotKey") }
    }

    var clipboardSlotModifiers: ClipboardSlotModifiers {
        get {
            let raw = defaults.string(forKey: "clipboardSlotModifiers") ?? ""
            return ClipboardSlotModifiers(rawValue: raw) ?? .controlShift
        }
        set { store(newValue.rawValue, "clipboardSlotModifiers") }
    }

    /// Сколько записей держим. Потолок нужен не ради места, а ради списка:
    /// в вырезе всё равно видно несколько строк, а прокручивать сотню
    /// в поисках нужного бессмысленно — для архива есть отдельные программы.
    var clipboardLimit: Int {
        get { defaults.object(forKey: "clipboardLimit") as? Int ?? 30 }
        set { store(newValue, "clipboardLimit") }
    }

    /// Срок хранения в часах. Ноль — хранить, пока не вытеснится потолком.
    var clipboardLifetimeHours: Int {
        get { defaults.object(forKey: "clipboardLifetimeHours") as? Int ?? 24 }
        set { store(newValue, "clipboardLifetimeHours") }
    }

    var clipboardLifetime: TimeInterval {
        TimeInterval(clipboardLifetimeHours) * 3600
    }

    /// Вставлять выбранную запись в активное приложение, а не только класть
    /// её в буфер.
    var clipboardPastes: Bool {
        get { flag("clipboardPastes", default: true) }
        set { store(newValue, "clipboardPastes") }
    }

    /// Показывать плашку в вырезе при каждом копировании.
    var clipboardShowsChip: Bool {
        get { flag("clipboardShowsChip", default: true) }
        set { store(newValue, "clipboardShowsChip") }
    }

    // MARK: - Полка

    /// Полка занимает полоску приёма по самой чёлке, а та ест нажатия
    /// в своих границах. Кому она не нужна — выключает, и полоски нет вовсе.
    var shelfEnabled: Bool {
        get { flag("shelfEnabled", default: true) }
        set { store(newValue, "shelfEnabled") }
    }

    var shelfHotKey: HotKeySpec? {
        get { hotKey("shelfHotKey", default: .shelf) }
        set { storeHotKey(newValue, "shelfHotKey") }
    }

    // MARK: - Погода

    var monitorEnabled: Bool {
        get { flag("monitorEnabled", default: true) }
        set { store(newValue, "monitorEnabled") }
    }

    var monitorHotKey: HotKeySpec? {
        get { hotKey("monitorHotKey", default: .monitor) }
        set { storeHotKey(newValue, "monitorHotKey") }
    }

    var timerEnabled: Bool {
        get { flag("timerEnabled", default: true) }
        set { store(newValue, "timerEnabled") }
    }

    var timerSoundEnabled: Bool {
        get { flag("timerSoundEnabled", default: true) }
        set { store(newValue, "timerSoundEnabled") }
    }

    /// После работы сам заводится перерыв, после перерыва — снова работа.
    /// Помидор без перерыва — просто таймер, поэтому по умолчанию включено.
    /// Запускать перерыв служба всё равно не станет: решать, отдыхать ли
    /// сейчас, человеку.
    var pomodoroChainsRest: Bool {
        get { flag("pomodoroChainsRest", default: true) }
        set { store(newValue, "pomodoroChainsRest") }
    }

    var timerHotKey: HotKeySpec? {
        get { hotKey("timerHotKey", default: .timer) }
        set { storeHotKey(newValue, "timerHotKey") }
    }

    var weatherEnabled: Bool {
        get { flag("weatherEnabled", default: false) }
        set { store(newValue, "weatherEnabled") }
    }

    /// Когда показывать плашку с погодой.
    var weatherAlertMode: WeatherAlertMode {
        get { WeatherAlertMode(rawValue: defaults.string(forKey: "weatherAlertMode") ?? "") ?? .onChange }
        set { store(newValue.rawValue, "weatherAlertMode") }
    }

    /// Период для режима «по расписанию», в часах.
    var weatherPeriodHours: Int {
        get { defaults.object(forKey: "weatherPeriodHours") as? Int ?? 3 }
        set { store(newValue, "weatherPeriodHours") }
    }

    /// Откуда брать координаты. По умолчанию геопозиция — она точнее и сама
    /// следует за переездом. Но доступ к ней отдают не все, а погода нужна
    /// и им: город указывается руками, и тогда система про положение
    /// не спрашивается вовсе.
    // MARK: - Чашка кофе

    /// Через сколько минут удержание экрана снимается само. Ноль —
    /// не снимается вовсе.
    ///
    /// По умолчанию без ограничения: чашку включают осознанно и под конкретное
    /// дело, и приложение, само погасившее экран посреди этого дела, было бы
    /// хуже забытой включённой чашки. Кому нужен предохранитель — ставит срок
    /// в настройках.
    var caffeineLimitMinutes: Int {
        get { defaults.object(forKey: "caffeineLimitMinutes") as? Int ?? 0 }
        set { store(newValue, "caffeineLimitMinutes") }
    }

    /// Сроки на выбор. Ноль в конце — «без ограничения».
    static let caffeineLimits = [30, 60, 90, 120, 0]

    // MARK: - Телесуфлер

    var teleprompterHotKey: HotKeySpec? {
        get { hotKey("teleprompterHotKey", default: .teleprompter) }
        set { storeHotKey(newValue, "teleprompterHotKey") }
    }

    /// Скорость автопрокрутки в точках в секунду.
    ///
    /// В точках, а не в «строках в минуту»: строки в телесуфлере разной
    /// высоты — заголовок вдвое выше обычной, — и счёт по строкам дёргал бы
    /// текст на каждом заголовке.
    var teleprompterSpeed: Int {
        get { defaults.object(forKey: "teleprompterSpeed") as? Int ?? 40 }
        set { store(newValue, "teleprompterSpeed") }
    }

    // MARK: - Погода

    var weatherSource: WeatherSource {
        get {
            let stored = WeatherSource(rawValue: defaults.string(forKey: "weatherSource") ?? "")
            // Город, выбранный до появления переключателя, сам себя объявляет:
            // раз он есть, значит его и выбирали.
            return stored ?? (weatherPlace == nil ? .location : .place)
        }
        set { store(newValue.rawValue, "weatherSource") }
    }

    var weatherPlace: WeatherPlace? {
        get {
            guard let data = defaults.data(forKey: "weatherPlace") else { return nil }
            return try? JSONDecoder().decode(WeatherPlace.self, from: data)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "weatherPlace")
        }
    }

    // MARK: - Встречи

    var meetingControlsEnabled: Bool {
        get { flag("meetingControlsEnabled", default: true) }
        set { store(newValue, "meetingControlsEnabled") }
    }

    // MARK: - Календарь

    var calendarEnabled: Bool {
        get { flag("calendarEnabled", default: true) }
        set { store(newValue, "calendarEnabled") }
    }

    var remindersEnabled: Bool {
        get { flag("remindersEnabled", default: true) }
        set { store(newValue, "remindersEnabled") }
    }

    var thingsEnabled: Bool {
        get { flag("thingsEnabled", default: false) }
        set { store(newValue, "thingsEnabled") }
    }

    /// За сколько минут до начала предупреждать. Ноль — в момент события.
    var eventLeadMinutes: Int {
        get { defaults.object(forKey: "eventLeadMinutes") as? Int ?? 5 }
        set { store(newValue, "eventLeadMinutes") }
    }

    /// Дополнительно напомнить в сам момент начала.
    var alertAtEventStart: Bool {
        get { flag("alertAtEventStart", default: true) }
        set { store(newValue, "alertAtEventStart") }
    }

    /// Показывать обратный отсчёт рядом с вырезом, пока встреча близко.
    var showCountdown: Bool {
        get { flag("showCountdown", default: true) }
        set { store(newValue, "showCountdown") }
    }

    /// За сколько минут до начала появляется обратный отсчёт.
    var countdownWindowMinutes: Int {
        get { defaults.object(forKey: "countdownWindowMinutes") as? Int ?? 15 }
        set { store(newValue, "countdownWindowMinutes") }
    }

    /// Пустой набор означает «все календари», в том числе те, что появятся
    /// в системе позже.
    var enabledCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "enabledCalendarIDs") ?? []) }
        set { store(Array(newValue), "enabledCalendarIDs") }
    }

    /// То же для списков напоминаний.
    var enabledReminderListIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "enabledReminderListIDs") ?? []) }
        set { store(Array(newValue), "enabledReminderListIDs") }
    }

    /// Включён ли конкретный источник. Пустой набор значит «все включены»,
    /// поэтому снятие первой галочки означает «выбрать все, кроме этого».
    func isSourceEnabled(_ id: String, in keyPath: ReferenceWritableKeyPath<Settings, Set<String>>, all: [String]) -> Bool {
        let selected = self[keyPath: keyPath]
        return selected.isEmpty || selected.contains(id)
    }

    func setSource(_ id: String, enabled: Bool, in keyPath: ReferenceWritableKeyPath<Settings, Set<String>>, all: [String]) {
        var selected = self[keyPath: keyPath]
        if selected.isEmpty { selected = Set(all) }
        if enabled { selected.insert(id) } else { selected.remove(id) }
        // Если отмечено всё, возвращаемся к пустому набору: тогда новые
        // календари появятся сами, без похода в настройки.
        self[keyPath: keyPath] = selected == Set(all) ? [] : selected
    }

    // MARK: - Батарея

    var batteryEnabled: Bool {
        get { flag("batteryEnabled", default: true) }
        set { store(newValue, "batteryEnabled") }
    }

    var warnOnLowBattery: Bool {
        get { flag("warnOnLowBattery", default: true) }
        set { store(newValue, "warnOnLowBattery") }
    }

    var lowBatteryThreshold: Int {
        get { defaults.object(forKey: "lowBatteryThreshold") as? Int ?? 20 }
        set { store(newValue, "lowBatteryThreshold") }
    }

    // MARK: - Внутреннее

    private func flag(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func store(_ value: Any, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }

    // MARK: Сочетания клавиш
    //
    // Отдельной парой методов, а не пятью одинаковыми телами get/set. Тела
    // писались копированием образца, и две из пяти пар потеряли при этом
    // `objectWillChange.send()`: поле записи сочетания в настройках
    // не перерисовывалось, пока перерисоваться не заставит что-нибудь
    // постороннее. Строку, которую так легко забыть, надо писать один раз.

    private func hotKey(_ key: String, default fallback: HotKeySpec?) -> HotKeySpec? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(HotKeySpec.self, from: data)
    }

    private func storeHotKey(_ value: HotKeySpec?, _ key: String) {
        objectWillChange.send()
        defaults.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }

    /// Связывает настройку с элементом управления SwiftUI.
    /// Вычисляемые свойства не дают проекции `$`, поэтому делаем вручную.
    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }
}
