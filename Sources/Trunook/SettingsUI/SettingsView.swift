import SwiftUI

/// Выбранная вкладка настроек.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class SettingsSelection: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case general, commands, clipboard, shelf, calendar, weather, battery, info
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return t("Общие")
            case .commands: return t("Команды")
            case .clipboard: return t("Буфер")
            case .shelf: return t("Полка")
            case .calendar: return t("Календарь")
            case .weather: return t("Погода")
            case .battery: return t("Батарея")
            case .info: return t("Инфо")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .commands: return "square.grid.2x2.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .shelf: return "tray.full.fill"
            case .calendar: return "calendar"
            case .weather: return "cloud.sun.fill"
            case .battery: return "battery.100"
            case .info: return "info"
            }
        }

        /// Цвет плитки значка — по нему раздел узнаётся боковым зрением
        /// быстрее, чем по названию.
        var tint: Color {
            switch self {
            case .general: return Palette.neutral
            case .commands: return Palette.commands
            case .clipboard: return Palette.clipboard
            case .shelf: return Palette.shelf
            case .calendar: return Palette.calendar
            case .weather: return Palette.weather
            case .battery: return Palette.positive
            case .info: return Palette.welcome
            }
        }
    }

    @Published var tab: Tab = .general
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var calendar: CalendarService
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var models: OllamaModelList
    @ObservedObject var shortcuts: ShortcutsService
    @ObservedObject var browsers: BrowserList
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var weather: WeatherService
    /// Сочетания заданы пользователем, поэтому после правки их надо
    /// перерегистрировать в системе.
    let onHotKeysChanged: () -> Void

    static let sidebarWidth: CGFloat = 210
    static let size = CGSize(width: sidebarWidth + 460, height: 640)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(SettingsStyle.stroke)
                .frame(width: 1)
            detail
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(SettingsStyle.background)
        // Тёмная тема принудительно: вырез и знакомство тёмные всегда,
        // и окно настроек, открытое из чёрной панели, не должно вспыхивать
        // белым.
        .preferredColorScheme(.dark)
        .tint(Palette.cyan)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSelection.Tab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .frame(width: Self.sidebarWidth, alignment: .leading)
        .background(SettingsStyle.sidebar)
    }

    private func sidebarRow(_ tab: SettingsSelection.Tab) -> some View {
        let isSelected = selection.tab == tab
        return Button {
            selection.tab = tab
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tab.tint)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? SettingsStyle.title : SettingsStyle.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            // Выбранный раздел — светлой подложкой, а не заливкой акцентом:
            // цвет уже занят значком, и два цвета в одной строке спорят.
            .background(
                RoundedRectangle(cornerRadius: SettingsStyle.rowRadius, style: .continuous)
                    .fill(isSelected ? SettingsStyle.selection : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsStyle.rowRadius))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch selection.tab {
                case .general: generalSection
                case .commands: commandsSection
                case .clipboard: clipboardSection
                case .shelf: shelfSection
                case .calendar: calendarSection
                case .weather: weatherSection
                case .battery: batterySection
                case .info: infoSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generalSection: some View {
        Group {
                section(t("Общие"), icon: "gearshape") {
                    Picker(t("Язык интерфейса"), selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        ForEach(Language.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300, alignment: .leading)

                    Toggle(t("Запускать при входе в систему"), isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.isEnabled = $0 }
                    ))
                    Toggle(t("Раскрывать вырез при наведении"), isOn: settings.binding(\.expandOnHover))
                    Toggle(t("Виброотклик на трекпаде"), isOn: settings.binding(\.hapticsEnabled))
                    Toggle(t("Мурчание"), isOn: settings.binding(\.purrEnabled))
                    hint(t("Поводите курсором по чёлке из стороны в сторону — вырез замурчит."))
                }

                section(t("Музыка"), icon: "music.note") {
                    Toggle(t("Управление музыкой"), isOn: settings.binding(\.musicEnabled))
                    Toggle(t("Показывать смену трека"), isOn: settings.binding(\.showTrackChanges))
                        .disabled(!settings.musicEnabled)
                    hint(t("Сведения о треке читаются из системы, поэтому работают с любым плеером: Яндекс Музыка, Spotify, Apple Music, веб-плееры в браузере."))
                    hint(t("Свайп двумя пальцами по острову переключает трек."))
                }

        }
    }

    private var shelfSection: some View {
        Group {
            section(t("Полка"), icon: "tray.full") {
                Toggle(t("Принимать перетаскиваемые файлы"), isOn: Binding(
                    get: { settings.shelfEnabled },
                    set: { settings.shelfEnabled = $0; onHotKeysChanged() }
                ))
                hint(t("Ведите файлы на чёлку — вырез раскроется полкой. Оттуда их вытаскивают в любое окно."))

                HStack {
                    Text(t("Открыть полку"))
                    Spacer()
                    HotKeyRecorder(spec: Binding(
                        get: { settings.shelfHotKey },
                        set: { settings.shelfHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: 140, height: 24)
                }
                .disabled(!settings.shelfEnabled)
            }

            section(t("Как это работает"), icon: "arrow.up.and.down.and.arrow.left.and.right") {
                hint(t("Пока файл лежит на полке, он остаётся в своей папке. Когда вы вытаскиваете его с полки, он переезжает — в исходной папке его больше нет."))
                hint(t("После перезапуска полка пуста: это перевалочный пункт между двумя окнами, а не хранилище."))
                hint(t("Полоска приёма опускается ниже чёлки, чтобы файл не пришлось вести к самой кромке экрана — там система открывает Mission Control."))
            }
        }
    }

    private var clipboardSection: some View {
        Group {
            section(t("История буфера обмена"), icon: "doc.on.clipboard") {
                Toggle(t("Запоминать копирования"), isOn: settings.binding(\.clipboardEnabled))

                HStack {
                    Text(t("Открыть историю"))
                    Spacer()
                    HotKeyRecorder(spec: Binding(
                        get: { settings.clipboardHotKey },
                        set: { settings.clipboardHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: 140, height: 24)
                }
                .disabled(!settings.clipboardEnabled)

                Picker(t("Клавиши записей"), selection: Binding(
                    get: { settings.clipboardSlotModifiers },
                    set: { settings.clipboardSlotModifiers = $0; onHotKeysChanged() }
                )) {
                    ForEach(ClipboardSlotModifiers.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)
                .disabled(!settings.clipboardEnabled)

                hint(t("Цифра вставляет запись по её номеру в списке: первая — самая свежая. Работает и когда панель закрыта."))

                Toggle(t("Вставлять сразу"), isOn: settings.binding(\.clipboardPastes))
                    .disabled(!settings.clipboardEnabled)
                hint(t("Выключено — запись только ложится в буфер, вставить нужно самому."))

                Toggle(t("Показывать плашку при копировании"),
                       isOn: settings.binding(\.clipboardShowsChip))
                    .disabled(!settings.clipboardEnabled)
                hint(t("По плашке можно нажать — откроется история."))
            }


            section(t("Сколько хранить"), icon: "clock.arrow.circlepath") {
                Picker(t("Срок хранения"), selection: settings.binding(\.clipboardLifetimeHours)) {
                    Text(t("1 час")).tag(1)
                    Text(t("6 часов")).tag(6)
                    Text(t("сутки")).tag(24)
                    Text(t("3 дня")).tag(72)
                    Text(t("неделю")).tag(168)
                    Text(t("без ограничения")).tag(0)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)

                Picker(t("Не больше записей"), selection: settings.binding(\.clipboardLimit)) {
                    ForEach([20, 30, 50], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)

                Divider()

                HStack {
                    Text(tf("Сейчас записей: %d", clipboard.entries.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Очистить историю"), role: .destructive) {
                        clipboard.clear()
                    }
                    .disabled(clipboard.entries.isEmpty)
                }
            }

            section(t("Что не сохраняется"), icon: "lock") {
                hint(t("Пароли: менеджеры паролей помечают такое копирование флагом org.nspasteboard.ConcealedType, и запись пропускается."))
                hint(t("Служебные копирования с флагами TransientType и AutoGeneratedType — их ставят приложения для своих нужд."))
                hint(t("Изображения крупнее шести мегабайт: история должна оставаться лёгкой."))
            }
        }
    }

    private var weatherSection: some View {
        Group {
            section(t("Погода в вырезе"), icon: "cloud.sun") {
                Toggle(t("Показывать погоду"), isOn: Binding(
                    get: { settings.weatherEnabled },
                    set: { enabled in
                        settings.weatherEnabled = enabled
                        weather.restart()
                    }
                ))
                hint(t("В раскрытой панели значок и температура стоят в правом верхнем углу — там, где вырез и так пустой. Сама чёлка от этого не растёт."))

                Picker(t("Сообщать"), selection: Binding(
                    get: { settings.weatherAlertMode },
                    set: { settings.weatherAlertMode = $0 }
                )) {
                    ForEach(WeatherAlertMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300, alignment: .leading)
                .disabled(!settings.weatherEnabled)

                if settings.weatherAlertMode == .periodic {
                    Picker(t("Как часто"), selection: settings.binding(\.weatherPeriodHours)) {
                        ForEach([1, 3, 6, 12], id: \.self) { value in
                            Text(tf("%d ч", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300, alignment: .leading)
                    .disabled(!settings.weatherEnabled)
                } else {
                    hint(t("Плашка всплывает, когда меняется погода или когда в ближайшие часы ожидаются осадки — один раз на явление, а не каждую проверку."))
                }
            }

            section(t("Состояние"), icon: "location") {
                weatherStatus
            }

            section(t("Откуда берётся"), icon: "network") {
                hint(t("Прогноз запрашивается у open-meteo.com — без ключа и регистрации. Это единственное место, откуда приложение выходит в интернет."))
                hint(t("Наружу уходят только координаты, округлённые до сотой доли градуса: это примерно километр, и погоде точнее не нужно."))
                hint(t("WeatherKit от Apple подошёл бы лучше, но он привязан к платной учётной записи разработчика."))
            }
        }
    }

    @ViewBuilder
    private var weatherStatus: some View {
        switch weather.authorization {
        case .denied, .restricted:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(t("Доступ к геопозиции запрещён. Без него погоду не узнать."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(t("Открыть настройки конфиденциальности")) {
                WeatherService.openPrivacySettings()
            }
        case .notDetermined:
            Button(t("Разрешить доступ к геопозиции")) {
                weather.requestAccessIfNeeded()
            }
            .disabled(!settings.weatherEnabled)
        default:
            if let snapshot = weather.current {
                HStack(spacing: 10) {
                    Image(systemName: snapshot.condition.symbol)
                        .foregroundStyle(snapshot.condition.tint)
                    Text("\(snapshot.condition.title), \(snapshot.temperature)°")
                    Spacer()
                    Button(t("Обновить")) { weather.refresh() }
                }
                if let outlook = snapshot.outlook {
                    hint(tf("Через %d ч %@, вероятность %d%%",
                            outlook.inHours, outlook.condition.title.lowercased(), outlook.probability))
                }
            } else {
                HStack(spacing: 10) {
                    Text(weather.error ?? t("Прогноз ещё не загружен"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Обновить")) { weather.refresh() }
                }
            }
        }
    }

    private var batterySection: some View {
        section(t("Батарея"), icon: "battery.100") {
            Toggle(t("Показывать состояние питания"), isOn: settings.binding(\.batteryEnabled))
            Toggle(t("Предупреждать о низком заряде"), isOn: settings.binding(\.warnOnLowBattery))
                .disabled(!settings.batteryEnabled)
            Picker(t("Порог предупреждения"), selection: settings.binding(\.lowBatteryThreshold)) {
                ForEach([10, 15, 20, 25, 30], id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220, alignment: .leading)
            .disabled(!settings.batteryEnabled || !settings.warnOnLowBattery)
        }
    }

    private var commandsSection: some View {
        Group {
            section(t("Меню команд"), icon: "square.grid.2x2") {
                Toggle(t("Быстрые команды"), isOn: settings.binding(\.quickCommandsEnabled))

                HStack {
                    Text(t("Открыть меню"))
                    Spacer()
                    HotKeyRecorder(spec: Binding(
                        get: { settings.menuHotKey },
                        set: { settings.menuHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: 140, height: 24)
                }
                hint(t("Нажмите поле и задайте сочетание. Delete снимает назначенное, Esc отменяет запись. Сочетание без модификаторов не принимается: оно перехватывало бы обычный набор текста."))
            }

            section(t("Запросы к модели"), icon: "sparkles") {
                Toggle(t("Использовать Ollama"), isOn: settings.binding(\.ollamaEnabled))

                if settings.ollamaEnabled {
                    TextField(tf("Адрес (по умолчанию %@)", Settings.defaultOllamaURL),
                              text: settings.binding(\.ollamaURLRaw))

                    HStack {
                        Picker(t("Модель"), selection: settings.binding(\.ollamaModel)) {
                            if models.models.isEmpty {
                                Text(settings.ollamaModel).tag(settings.ollamaModel)
                            }
                            ForEach(models.models, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            models.refresh()
                        } label: {
                            if models.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(models.isLoading)
                        .help(t("Обновить список моделей"))
                    }

                    if let error = models.error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    Picker(t("Держать модель в памяти"), selection: settings.binding(\.ollamaKeepAlive)) {
                        Text(t("5 минут")).tag("5m")
                        Text(t("30 минут")).tag("30m")
                        Text(t("2 часа")).tag("2h")
                        Text(t("Постоянно")).tag("-1")
                    }
                    .pickerStyle(.menu)

                    hint(t("Ответ кладётся в буфер обмена. Место подстановки выделенного текста — {{selection}}. Загрузка модели в память занимает около минуты, поэтому её стоит держать загруженной; модель поменьше отвечает заметно быстрее."))
                }
            }

            ForEach(settings.quickCommands) { command in
                commandEditor(command)
            }
        }
    }

    private func commandEditor(_ command: QuickCommand) -> some View {
        section(tf("Слот %d", command.id + 1), icon: command.effectiveSymbol) {
            HStack(spacing: 8) {
                Toggle("", isOn: binding(command, \.isEnabled)).labelsHidden()
                TextField(t("Название"), text: binding(command, \.title))
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.quickCommands.first { $0.id == command.id }?.hotKey },
                        set: { spec in
                            guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                            else { return }
                            updated.hotKey = spec
                            settings.updateCommand(updated)
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Без клавиши")
                )
                .frame(width: 130, height: 24)
            }

            Picker(t("Действие"), selection: binding(command, \.kind)) {
                ForEach(QuickCommand.Kind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.menu)

            payloadEditor(command)
        }
    }

    /// Поле значения зависит от типа: путь выбирается диалогом, готовое
    /// действие — списком, и только промт и свой скрипт пишутся руками.
    @ViewBuilder
    private func payloadEditor(_ command: QuickCommand) -> some View {
        switch command.kind {
        case .shortcut:
            if ShortcutsService.isAvailable {
                HStack {
                    Picker(t("Команда"), selection: Binding(
                        get: {
                            settings.quickCommands.first { $0.id == command.id }?.payload ?? ""
                        },
                        set: { name in
                            applyChoice(to: command, payload: name, title: name)
                        }
                    )) {
                        if command.payload.isEmpty {
                            Text(t("Не выбрана")).tag("")
                        }
                        ForEach(shortcuts.names, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        shortcuts.refresh()
                    } label: {
                        if shortcuts.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(shortcuts.isLoading)
                    .help(t("Обновить список команд"))
                }
                Toggle(t("Передавать выделенный текст"), isOn: binding(command, \.passesSelection))
                hint(t("Если команда что-то возвращает, результат попадёт в буфер обмена."))
            } else {
                Text(t("Приложение «Команды» недоступно"))
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

        case .ollama:
            // Именно TextEditor, а не TextField: у поля ввода Return отправляет
            // форму, а не переносит строку, и промт нельзя было разбить
            // на абзацы — а промты пишут абзацами.
            multilineEditor(
                text: binding(command, \.payload),
                placeholder: t("Переведи на английский.\n\n{{selection}}"),
                minHeight: 76
            )

        case .openApp:
            pathRow(command, chooser: CommandPickers.chooseApplication, empty: t("Приложение не выбрано"))

        case .openPath:
            pathRow(command, chooser: CommandPickers.choosePath, empty: t("Путь не выбран"))

        case .openURL:
            TextField("https://example.com", text: binding(command, \.payload))

            Picker(t("Браузер"), selection: Binding(
                get: {
                    settings.quickCommands.first { $0.id == command.id }?.browserBundleID ?? ""
                },
                set: { bundleID in
                    guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                    else { return }
                    updated.browserBundleID = bundleID.isEmpty ? nil : bundleID
                    settings.updateCommand(updated)
                }
            )) {
                Text(browsers.defaultName.map { tf("По умолчанию — %@", $0) } ?? t("Браузер по умолчанию"))
                    .tag("")
                ForEach(browsers.items) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
                // Выбранный когда-то браузер мог исчезнуть из системы.
                // Без этого пункта список показал бы пустую строку, и было
                // бы неясно, что вообще выбрано.
                if let bundleID = command.browserBundleID,
                   !bundleID.isEmpty,
                   browsers.name(forBundleID: bundleID) == nil {
                    Text(tf("%@ — не найден", bundleID)).tag(bundleID)
                }
            }
            .pickerStyle(.menu)

            hint(t("Схему можно не писать: «ya.ru» откроется как «https://ya.ru»."))

        case .appleScript:
            Picker(t("Действие"), selection: Binding(
                get: { ScriptPreset.matching(command.payload)?.id ?? "custom" },
                set: { id in
                    guard let preset = ScriptPreset.all.first(where: { $0.id == id }) else {
                        // «Свой скрипт»: очищаем текст, название не трогаем.
                        guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                        else { return }
                        updated.payload = ""
                        settings.updateCommand(updated)
                        return
                    }
                    applyChoice(
                        to: command,
                        payload: preset.source,
                        title: preset.title,
                        symbol: preset.symbol
                    )
                }
            )) {
                ForEach(ScriptPreset.all) { preset in
                    Text(preset.title).tag(preset.id)
                }
                Text(t("Свой скрипт")).tag("custom")
            }
            .pickerStyle(.menu)

            if ScriptPreset.matching(command.payload) == nil {
                multilineEditor(
                    text: binding(command, \.payload),
                    placeholder: "tell application \"Finder\" to activate",
                    minHeight: 84,
                    isCode: true
                )
            }
        }
    }

    /// Записывает новый выбор в слот, подставляя название и значок.
    ///
    /// Название подставляется, только если пользователь его не менял сам.
    /// Признак этого — совпадение с тем, что подставилось бы для прежнего
    /// выбора: раньше проверялось лишь «поле пустое», и смена приложения
    /// оставляла подпись от предыдущего.
    private func applyChoice(
        to command: QuickCommand,
        payload: String,
        title: String,
        symbol: String? = nil
    ) {
        guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
        else { return }

        let previousTitle = Self.autoTitle(for: updated)
        let previousSymbol = Self.autoSymbol(for: updated)

        if updated.title.isEmpty || updated.title == previousTitle {
            updated.title = title
        }
        if let symbol, updated.symbol.isEmpty || updated.symbol == previousSymbol {
            updated.symbol = symbol
        }
        updated.payload = payload
        settings.updateCommand(updated)
    }

    /// Какое название подставилось бы для нынешнего содержимого слота.
    private static func autoTitle(for command: QuickCommand) -> String {
        switch command.kind {
        case .openApp:
            return (command.payload as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
        case .openPath:
            return (command.payload as NSString).lastPathComponent
        case .shortcut:
            return command.payload
        case .appleScript:
            return ScriptPreset.matching(command.payload)?.title ?? ""
        case .openURL, .ollama:
            // Название здесь не угадать: адрес набирают по буквам, и любой
            // догадке пришлось бы меняться на каждом нажатии клавиши.
            return ""
        }
    }

    private static func autoSymbol(for command: QuickCommand) -> String? {
        guard command.kind == .appleScript else { return nil }
        return ScriptPreset.matching(command.payload)?.symbol
    }

    private func pathRow(
        _ command: QuickCommand,
        chooser: @escaping () -> (path: String, name: String)?,
        empty: String
    ) -> some View {
        HStack(spacing: 10) {
            if let icon = CommandPickers.icon(forPath: command.payload) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }

            Text(command.payload.isEmpty ? empty : (command.payload as NSString).lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(command.payload.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(t("Выбрать…")) {
                guard let picked = chooser() else { return }
                applyChoice(to: command, payload: picked.path, title: picked.name)
            }
        }
    }

    /// Правка одного поля слота. Слоты хранятся набором, поэтому связывание
    /// идёт через поиск по идентификатору, а не по индексу: индекс сместился
    /// бы при любой перестановке.
    private func binding<Value>(
        _ command: QuickCommand,
        _ keyPath: WritableKeyPath<QuickCommand, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.quickCommands.first { $0.id == command.id }?[keyPath: keyPath]
                    ?? command[keyPath: keyPath]
            },
            set: { newValue in
                guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                else { return }
                updated[keyPath: keyPath] = newValue
                settings.updateCommand(updated)
            }
        )
    }

    private var calendarSection: some View {
        Group {
        section(t("Календарь и задачи"), icon: "calendar") {
            Toggle(t("Встречи из Календаря"), isOn: Binding(
                get: { settings.calendarEnabled },
                set: { enabled in
                    settings.calendarEnabled = enabled
                    if enabled { calendar.requestAccessIfNeeded() }
                }
            ))
            Toggle(t("Напоминания"), isOn: Binding(
                get: { settings.remindersEnabled },
                set: { enabled in
                    settings.remindersEnabled = enabled
                    if enabled { calendar.requestAccessIfNeeded() }
                }
            ))
            Toggle(t("Задачи Things 3"), isOn: settings.binding(\.thingsEnabled))

            Divider()

            Picker(t("Предупреждать за"), selection: settings.binding(\.eventLeadMinutes)) {
                Text(t("в момент начала")).tag(0)
                Text(t("5 минут")).tag(5)
                Text(t("10 минут")).tag(10)
                Text(t("15 минут")).tag(15)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 280, alignment: .leading)

            Toggle(t("Ещё раз в момент начала"), isOn: settings.binding(\.alertAtEventStart))
                .disabled(settings.eventLeadMinutes == 0)

            Toggle(t("Обратный отсчёт рядом с вырезом"), isOn: settings.binding(\.showCountdown))

            Picker(t("Отсчёт появляется за"), selection: settings.binding(\.countdownWindowMinutes)) {
                ForEach([5, 10, 15, 30], id: \.self) { value in
                    Text(tf("%d минут", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 280, alignment: .leading)
            .disabled(!settings.showCountdown)

            accessStatus
        }

        section(t("Управление встречей"), icon: "video") {
            Toggle(t("Кнопки встречи в вырезе"), isOn: settings.binding(\.meetingControlsEnabled))
            hint(t("Пока идёт встреча, наведение на вырез показывает микрофон, камеру, демонстрацию экрана, поднятие руки и выход. Работает с Телемостом, Google Meet, Zoom и Teams в браузере."))
            hint(t("Кнопки нажимаются прямо на странице встречи через систему универсального доступа — фокус на браузер не переключается."))
            hint(t("Вкладка встречи должна быть открыта: содержимое фоновых вкладок браузер наружу не отдаёт. Удобнее всего вытащить встречу в отдельное окно."))
        }

        if !calendar.availableCalendars.isEmpty {
            section(t("Какие календари показывать"), icon: "calendar.badge.checkmark") {
                sourcePicker(calendar.availableCalendars, keyPath: \.enabledCalendarIDs)
            }
        }

        if !calendar.availableReminderLists.isEmpty {
            section(t("Какие списки напоминаний показывать"), icon: "checklist") {
                sourcePicker(calendar.availableReminderLists, keyPath: \.enabledReminderListIDs)
            }
        }
        }
    }

    @ViewBuilder
    private var accessStatus: some View {
        if settings.calendarEnabled, calendar.eventsAccess != .fullAccess {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(calendar.eventsAccess == .denied
                     ? t("Доступ к Календарю запрещён. Выдайте его в Системных настройках.")
                     : t("Доступ к Календарю ещё не выдан."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(t("Открыть настройки конфиденциальности")) {
                CalendarService.openPrivacySettings()
            }
        }
    }

    /// Раздел «Инфо» — справка, а не учебник.
    ///
    /// Раньше здесь лежали два десятка блоков, пересказывающих окно
    /// знакомства и сами панели. Учебник у приложения один — знакомство;
    /// здесь остаётся то, что нужно подсмотреть, а не прочесть: жесты,
    /// честные ограничения и куда уходят данные.
    private var infoSection: some View {
        Group {
            section(t("О приложении"), icon: "app.badge") {
                HStack {
                    Text(t("Версия"))
                    Spacer()
                    Text(AppInfo.version)
                        .foregroundStyle(SettingsStyle.secondary)
                        .textSelection(.enabled)
                }
                hint(t("Вырез MacBook как центр управления: музыка, встречи, команды, буфер обмена и полка для файлов."))
            }

            section(t("Жесты"), icon: "hand.draw") {
                info(t("Наведение"), t("Мини-вид: что играет и когда ближайшая встреча."))
                info(t("Нажатие или свайп вниз"), t("Панель целиком. Свайп вверх сворачивает обратно."))
                info(t("Свайп вбок"), t("Предыдущий и следующий трек."))
                info(t("Правая кнопка"), t("Меню всех функций."))
                info(t("Поглаживание"), t("Поводите курсором из стороны в сторону — вырез замурчит."))
            }

            section(t("Что уходит наружу"), icon: "lock") {
                info(t("Погода"), t("Координаты, округлённые до километра, уходят на open-meteo.com. Это единственное обращение в интернет."))
                info(t("Модель"), t("Запросы идут в Ollama на вашем же компьютере. Наружу не уходит ничего."))
                info(t("Буфер и полка"), t("Хранятся только у вас: история — в файле приложения, полка — ссылками на ваши же файлы."))
            }

            section(t("Ограничения"), icon: "exclamationmark.triangle") {
                info(t("Только встроенный экран"), t("На внешних мониторах выреза нет."))
                info(t("Встреча — только в открытой вкладке"), t("Браузер не отдаёт содержимое фоновых вкладок. Вытащите встречу в отдельное окно, чтобы кнопки были всегда."))
                info("Things 3", t("Задачи видны списком, но напоминания по ним не работают: Things не отдаёт время напоминания наружу."))
            }
        }
    }

    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(SettingsStyle.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Список календарей или списков напоминаний с галочками.
    private func sourcePicker(
        _ sources: [CalendarSource],
        keyPath: ReferenceWritableKeyPath<Settings, Set<String>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { source in
                Toggle(isOn: Binding(
                    get: {
                        settings.isSourceEnabled(source.id, in: keyPath, all: sources.map(\.id))
                    },
                    set: { enabled in
                        settings.setSource(source.id, enabled: enabled, in: keyPath, all: sources.map(\.id))
                    }
                )) {
                    HStack(spacing: 8) {
                        Circle().fill(source.color).frame(width: 8, height: 8)
                        Text(source.title)
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsStyle.tertiary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous)
                    .fill(SettingsStyle.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsStyle.cardRadius, style: .continuous)
                            .strokeBorder(SettingsStyle.stroke, lineWidth: 1)
                    )
            )
        }
    }

    /// Многострочное поле: промт и сценарий пишут абзацами.
    @ViewBuilder
    private func multilineEditor(
        text: Binding<String>,
        placeholder: String,
        minHeight: CGFloat,
        isCode: Bool = false
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: isCode ? 11 : 12, design: isCode ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.system(size: isCode ? 11 : 12, design: isCode ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(SettingsStyle.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(SettingsStyle.stroke, lineWidth: 1)
                )
        )
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(SettingsStyle.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
