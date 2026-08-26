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

    /// Раскрыть основную панель.
    var expandedHotKey: HotKeySpec? {
        get { hotKey("expandedHotKey", default: .expanded) }
        set { storeHotKey(newValue, "expandedHotKey") }
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

    /// Показывать ли чашку в раскрытой панели.
    ///
    /// Единственная настройка, которая чашке осталась. Срок раньше выбирали
    /// здесь; теперь он выбирается нажатием по самой чашке — там же, где
    /// виден отсчёт и кнопка «Выключить». Настройка «по умолчанию предлагать
    /// столько-то» пережила появление живого выбора и стала лишней: место,
    /// где решение принимают, и место, где его подготавливают, разошлись
    /// по разным окнам, а решение одно.
    var caffeineEnabled: Bool {
        get { defaults.object(forKey: "caffeineEnabled") as? Bool ?? true }
        set { store(newValue, "caffeineEnabled") }
    }

    /// Через сколько минут удержание экрана снимается само. Ноль —
    /// не снимается вовсе.
    ///
    /// По умолчанию без ограничения: чашку включают осознанно и под конкретное
    /// дело, и приложение, само погасившее экран посреди этого дела, было бы
    /// хуже забытой включённой чашки. Кому нужен предохранитель — выбирает
    /// срок нажатием по чашке.
    ///
    /// Хранится по-прежнему: панель чашки помнит выбранный срок между
    /// запусками, иначе его пришлось бы задавать каждый раз заново.
    var caffeineLimitMinutes: Int {
        get { defaults.object(forKey: "caffeineLimitMinutes") as? Int ?? 0 }
        set { store(newValue, "caffeineLimitMinutes") }
    }

    /// Сроки на выбор. Ноль в конце — «без ограничения».
    static let caffeineLimits = [30, 60, 90, 120, 0]

    // MARK: - Сколько держатся плашки событий

    /// Во сколько раз дольше обычного висят плашки. Ноль — «пока не уберу».
    ///
    /// Сроки у плашек короткие — от двух до девяти секунд, — и подобраны они
    /// под того, кто в этот момент смотрит на экран. Тому, кто читает медленнее,
    /// или тому, кто перевёл взгляд на секунду позже, девяти секунд на то,
    /// чтобы прочесть название встречи и попасть в «Подключиться», не хватает,
    /// а продлить их было нечем: таймер одноразовый и ни на что не смотрит.
    ///
    /// Убирается плашка в любом случае наведением на вырез — поэтому вариант
    /// «пока не уберу» не запирает её навсегда.
    var activityHold: Int {
        get { defaults.object(forKey: "activityHold") as? Int ?? 1 }
        set { store(newValue, "activityHold") }
    }

    // MARK: - Размер текста

    /// Размер текста в процентах от обычного.
    ///
    /// Своя настройка, а не системная, и это не самодеятельность: в macOS нет
    /// общесистемного размера текста, который читало бы приложение, — есть
    /// увеличение всего экрана, а оно к тексту отношения не имеет. Значит
    /// средство изменить размер обязано быть в самом приложении.
    ///
    /// Считается от ста: сто — как было.
    var textScale: Int {
        get { defaults.object(forKey: "textScale") as? Int ?? 100 }
        set { store(newValue, "textScale") }
    }

    /// Размеры на выбор. Двести — не для ровного счёта: столько требует
    /// критерий доступности от средства изменения размера текста.
    static let textScales = [100, 125, 150, 200]

    /// Во сколько раз растягивать. Ноль — «пока не уберу», единица —
    /// «как обычно». Десятка есть не для ровного счёта: столько требует
    /// критерий доступности от настройки, которая заменяет собой отсутствие
    /// предупреждения о том, что время вышло.
    static let activityHolds = [1, 3, 10, 0]

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

    // MARK: - Заметки

    /// Заметки живут в панели модели и без неё: набрать и сохранить можно
    /// с выключенной Ollama. Поэтому выключатель свой, а не общий с Ollama.
    var notesEnabled: Bool {
        get { flag("notesEnabled", default: true) }
        set { store(newValue, "notesEnabled") }
    }

    var notesHotKey: HotKeySpec? {
        get { hotKey("notesHotKey", default: .notes) }
        set { storeHotKey(newValue, "notesHotKey") }
    }

    /// Выделенный текст сразу в заметки — ничего не открывая.
    ///
    /// Отдельно от `notesHotKey`, потому что это разные действия, а не одно
    /// с оговоркой: то открывает пустую заметку, чтобы её набрали, это
    /// записывает уже написанное чужой рукой и не показывает ничего, кроме
    /// подтверждения.
    var noteSelectionHotKey: HotKeySpec? {
        get { hotKey("noteSelectionHotKey", default: .noteSelection) }
        set { storeHotKey(newValue, "noteSelectionHotKey") }
    }

    /// Имя заметке придумывает модель.
    ///
    /// Отдельно от `ollamaEnabled`: модель может быть нужна для команд
    /// и вопросов, а тратить её на именование каждой заметки — нет.
    var notesTitleByModel: Bool {
        get { flag("notesTitleByModel", default: true) }
        set { store(newValue, "notesTitleByModel") }
    }

    // MARK: - Голос

    var voiceEnabled: Bool {
        get { flag("voiceEnabled", default: true) }
        set { store(newValue, "voiceEnabled") }
    }

    /// Чем зовут обычный голосовой вопрос — модификатор, нажатый дважды.
    var voiceTrigger: VoiceTrigger {
        get { VoiceTrigger(rawValue: defaults.string(forKey: "voiceTrigger") ?? "") ?? .control }
        set { store(newValue.rawValue, "voiceTrigger") }
    }

    /// Чем зовут голосовой вопрос по заметкам.
    var voiceNotesTrigger: VoiceTrigger {
        get {
            VoiceTrigger(rawValue: defaults.string(forKey: "voiceNotesTrigger") ?? "") ?? .option
        }
        set { store(newValue.rawValue, "voiceNotesTrigger") }
    }

    /// Язык распознавания. Пусто — язык интерфейса.
    ///
    /// Отдельно от языка интерфейса, потому что это разные вещи: интерфейс
    /// держат на одном языке, а говорить могут на другом, и заставлять
    /// человека переключать всё приложение ради одного вопроса незачем.
    var voiceLanguage: Language? {
        get { Language(rawValue: defaults.string(forKey: "voiceLanguage") ?? "") }
        set { store(newValue?.rawValue ?? "", "voiceLanguage") }
    }

    /// Голос озвучки. Пусто — лучший из установленных для этого языка.
    var voiceIdentifier: String? {
        get {
            let stored = defaults.string(forKey: "voiceIdentifier") ?? ""
            return stored.isEmpty ? nil : stored
        }
        set { store(newValue ?? "", "voiceIdentifier") }
    }

    /// Скорость чтения ступенями от обычной, см. `SpeechSpeaker.rate(forStep:)`.
    var voiceRateStep: Int {
        get { defaults.object(forKey: "voiceRateStep") as? Int ?? 0 }
        set {
            let limit = SpeechSpeaker.rateSteps
            store(min(limit, max(-limit, newValue)), "voiceRateStep")
        }
    }

    /// Сколько тишины считается концом фразы, в десятых долях секунды.
    ///
    /// В десятых, а не дробным числом: `UserDefaults` дробные хранит, но
    /// в `Picker` их пришлось бы сравнивать на равенство — а это ровно тот
    /// случай, когда 1.5 не равно 1.5.
    var voiceSilenceTenths: Int {
        get { defaults.object(forKey: "voiceSilenceTenths") as? Int ?? 15 }
        set { store(max(5, min(40, newValue)), "voiceSilenceTenths") }
    }

    var voiceSilence: TimeInterval { TimeInterval(voiceSilenceTenths) / 10 }

    /// Сколько символов заметок уходит в контекст **голосового** вопроса.
    ///
    /// Свой потолок, меньше текстового, и это не мелочь. Ответа в тексте
    /// ждут глазами и терпят; голосового ждут ушами, и полминуты тишины
    /// человек читает как «не сработало». Контекст — главное, за что платят
    /// временем, поэтому у голоса он свой.
    var voiceNotesContextLimit: Int {
        get { defaults.object(forKey: "voiceNotesContextLimit") as? Int ?? 6_000 }
        set { store(max(1_000, newValue), "voiceNotesContextLimit") }
    }

    /// Сколько символов заметок уходит в контекст модели при поиске по ним.
    ///
    /// В символах, а не в токенах: токенов не сосчитать без самой модели,
    /// а разные модели считают их по-разному. Для кириллицы 24 000 символов —
    /// это примерно 10 000 токенов, и в окно любой ходовой модели такое
    /// влезает с запасом.
    var notesContextLimit: Int {
        get { defaults.object(forKey: "notesContextLimit") as? Int ?? 24_000 }
        set { store(max(2_000, newValue), "notesContextLimit") }
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
