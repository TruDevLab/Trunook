import SwiftUI

/// Выбранная вкладка настроек.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class SettingsSelection: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case general, commands, clipboard, shelf, timer, monitor, teleprompter, calendar, weather, battery, info
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return t("Общие")
            case .commands: return t("Команды")
            case .clipboard: return t("Буфер")
            case .shelf: return t("Полка")
            case .timer: return t("Таймер")
            case .monitor: return t("Нагрузка")
            case .teleprompter: return t("Телесуфлер")
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
            case .timer: return "timer"
            case .monitor: return "gauge.with.dots.needle.67percent"
            case .teleprompter: return "text.alignleft"
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
            case .timer: return Palette.timer
            case .monitor: return Palette.monitor
            case .teleprompter: return Palette.teleprompter
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
    /// Поиск города. Живёт снаружи, а не в теле вида: `@State` в этом SDK
    /// недоступен, а полю ввода и списку найденного где-то держаться надо.
    @ObservedObject var placeSearch: WeatherPlaceSearch
    /// «Уменьшить прозрачность»: из неё считаются плотности `SettingsStyle`.
    /// Наблюдается здесь, в корне окна, — оттуда перерисовка расходится
    /// по всем разделам.
    @ObservedObject private var motion = MotionPreference.shared
    /// Сочетания заданы пользователем, поэтому после правки их надо
    /// перерегистрировать в системе.
    let onHotKeysChanged: () -> Void
    /// Размеры панелей поменялись — окну выреза нужно пересчитать себя.
    ///
    /// Своим вызовом, а не наблюдением за настройками: окно строится один раз,
    /// и высота с шириной берутся из расчёта в тот момент. Без оповещения
    /// панель, выросшая вместе с текстом, обрезалась бы окном прежнего
    /// размера — молча, как и всё, что окно обрезает.
    let onLayoutChanged: () -> Void
    /// Окно знакомства открывается заново из настроек: оно показывается само
    /// только при первом запуске, а вернуться к нему хотят и позже —
    /// перечитать про жесты или переспросить доступы.
    let onOpenWelcome: () -> Void

    static var sidebarWidth: CGFloat { SettingsStyle.sidebarWidth }
    static var size: CGSize { SettingsStyle.windowSize }

    /// Окно устроено как «Системные настройки»: список разделов слева,
    /// содержимое справа.
    ///
    /// Раскладка своя, а не `NavigationSplitView`, и это не возврат к прежнему
    /// столбику кнопок. Список слева остался настоящим `List` с выбором —
    /// со всем, что к нему прилагается: ходом стрелками, выделением
    /// системного вида, признаком выбранного для диктора.
    ///
    /// `NavigationSplitView` пришлось снять из-за фона. Он подкладывает
    /// под полосу разделов `NSVisualEffectView` с материалом полосы, и тот
    /// закрашивает всё, что подложено средствами SwiftUI: слева окно упиралось
    /// в ровный серый прямоугольник, справа светилось. Погасить его не вышло
    /// ни через `scrollContentBackground`, ни обходом дерева окна — SwiftUI
    /// восстанавливает материал сам.
    ///
    /// Потеряна при этом одна вещь: перетаскиваемая граница между колонками.
    /// Полоса разделов и так была прибита к одной ширине.
    ///
    /// `NavigationSplitView` вместо `HStack` с прочерченной вручную линией —
    /// и разница не в одной линии. Родная раскладка приносит с собой всё,
    /// что к ней прилагается: полупрозрачную полосу разделов с подложкой
    /// окна, ход по списку стрелками, выделение системного вида,
    /// перетаскиваемую границу. Самодельная не приносила ничего из этого,
    /// и каждую мелочь пришлось бы дописывать по одной.
    ///
    /// Тёмное оформление задано окну целиком в `SettingsWindowController`,
    /// поэтому `preferredColorScheme` здесь больше нет: два места, где
    /// назначается тема, рано или поздно разойдутся.
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .tint(SettingsStyle.accent)
        // Тот же фон, что в окне знакомства, и по той же причине: оба окна
        // рассказывают про вырез, а вырез чёрный и живёт на обоях. Ровная
        // серая подложка читается как чужое приложение, открытое рядом.
        //
        // Фон подложен под всё окно, а полосе разделов и форме их собственные
        // подложки сняты, — иначе он был бы виден только по краям. Карточки
        // разделов свои подложки сохраняют: сквозь них читать нельзя,
        // а лежат они поверх плывущих пятен.
        .background(AuroraBackground(intensity: 0.4))
    }

    /// Полоса разделов.
    ///
    /// `List` с выбором, а не столбик кнопок: раньше каждая строка была
    /// `Button`, и всё, что список умеет сам, приходилось изображать —
    /// подложку выбранного, метку слева, признак для диктора. Ход по списку
    /// стрелками не изображался вовсе: кнопки не образуют списка, между ними
    /// нечем ходить.
    private var sidebar: some View {
        List(SettingsSelection.Tab.allCases, selection: $selection.tab) { tab in
            // `HStack` со своим зазором, а не `Label`: у того зазор системный
            // и по настройке не растёт. На ста пятидесяти процентах плитка
            // со значком выросла, зазор остался прежним, и название раздела
            // упёрлось в значок — тот же промах, что и с самой плиткой,
            // только на шаг дальше.
            HStack(spacing: SettingsStyle.scaled(8)) {
                // Значок в цветной плитке — тот же приём, что у Apple
                // в «Системных настройках»: раздел узнаётся боковым зрением
                // по цвету быстрее, чем по названию.
                RoundedRectangle(cornerRadius: SettingsStyle.glyphRadius, style: .continuous)
                    .fill(tab.tint)
                    .frame(width: SettingsStyle.glyphSide, height: SettingsStyle.glyphSide)
                    .overlay(
                        Image(systemName: tab.icon)
                            .font(.system(size: SettingsStyle.font(10), weight: .semibold))
                            .foregroundStyle(.black.opacity(0.85))
                    )
                Text(tab.title)
                    .font(.system(size: SettingsStyle.font(13)))
            }
            .tag(tab)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: Self.sidebarWidth)
    }

    /// Содержимое раздела.
    ///
    /// `Form` со сгруппированным стилем — то же, из чего собраны «Системные
    /// настройки» начиная с Ventura. Он сам даёт карточке подложку, поля,
    /// скругление и разделители между строками; раньше всё это рисовалось
    /// здесь вручную и совпасть с системой не могло — только отставать от неё
    /// на очередном обновлении.
    @ViewBuilder
    private var detail: some View {
        Form {
            Group {
                switch selection.tab {
                case .timer: timerSection
                case .monitor: monitorSection
                case .teleprompter: teleprompterSection
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Подпись варианта в списке сроков плашек.
    ///
    /// Словами, а не «в N раз дольше» с подстановкой: «в 3 раза» и «в 10 раз»
    /// склоняются по-разному, и одна строка формата дала бы «в 10 раза».
    static func activityHoldTitle(_ scale: Int) -> String {
        switch scale {
        case 0: return t("Пока не уберу")
        case 1: return t("Как обычно")
        case 3: return t("Втрое дольше")
        case 10: return t("Вдесятеро дольше")
        default: return tf("В %d раз дольше", scale)
        }
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
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)

                    Toggle(t("Запускать при входе в систему"), isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.isEnabled = $0 }
                    ))
                    Toggle(t("Раскрывать вырез при наведении"), isOn: settings.binding(\.expandOnHover))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t("Раскрыть панель"))
                            Spacer()
                            HotKeyRecorder(spec: Binding(
                                get: { settings.expandedHotKey },
                                set: { settings.expandedHotKey = $0; onHotKeysChanged() }
                            ))
                            .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                        }
                        hint(t("Музыка, расписание, погода и чашка — без мыши. Нажатие при раскрытой панели сворачивает её."))
                    }
                    Toggle(t("Виброотклик на трекпаде"), isOn: settings.binding(\.hapticsEnabled))
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Мурчание"), isOn: settings.binding(\.purrEnabled))
                        hint(t("Поводите курсором по чёлке из стороны в сторону — вырез замурчит."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(t("Размер текста"), selection: Binding(
                            get: { settings.textScale },
                            set: { settings.textScale = $0; onLayoutChanged() }
                        )) {
                            ForEach(Settings.textScales, id: \.self) { scale in
                                Text(tf("%d %%", scale)).tag(scale)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                        hint(t("В macOS нет общего размера текста, который приложение могло бы прочесть, — поэтому он свой. Действует в этом окне и в окне знакомства."))
                        hint(t("Панели выреза не растут: под чёлкой ровно столько места, сколько оставила вырезка."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(t("Держать плашки событий"), selection: settings.binding(\.activityHold)) {
                            ForEach(Settings.activityHolds, id: \.self) { scale in
                                Text(Self.activityHoldTitle(scale)).tag(scale)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                        hint(t("Плашки о смене трека, встрече, таймере и заряде уходят сами через несколько секунд. Здесь их можно растянуть."))
                        hint(t("«Пока не уберу» не запирает плашку навсегда: она уходит, стоит навести курсор на вырез."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t("Знакомство с вырезом"))
                            Spacer()
                            Button(t("Открыть")) { onOpenWelcome() }
                        }
                        hint(t("Окно с жестами, сочетаниями и доступами. Само показывается только при первом запуске."))
                    }
                }

                // Выбор срока отсюда ушёл: он появился в самой панели чашки —
                // там же, где отсчёт и кнопка «Выключить». Настройка «что
                // предлагать по умолчанию» пережила появление живого выбора
                // и стала лишней: решение одно, а мест, где его принимают,
                // стало два. Осталось то, чего в вырезе нет, — сам показ.
                section(t("Чашка кофе"), icon: "cup.and.saucer") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Показывать чашку"), isOn: settings.binding(\.caffeineEnabled))
                        hint(t("Пока чашка включена, экран не гаснет и не блокируется. Срок задаётся нажатием по самой чашке — там же виден отсчёт."))
                        hint(t("Когда срок выходит, вырез сообщает плашкой: погасший сам собой экран иначе выглядел бы поломкой."))
                        hint(t("Удержание не переживает перезапуск приложения."))
                    }
                }

                section(t("Музыка"), icon: "music.note") {
                    Toggle(t("Управление музыкой"), isOn: settings.binding(\.musicEnabled))
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Показывать смену трека"), isOn: settings.binding(\.showTrackChanges))
                            .disabled(!settings.musicEnabled)
                        hint(t("Сведения о треке читаются из системы, поэтому работают с любым плеером: Яндекс Музыка, Spotify, Apple Music, веб-плееры."))
                        hint(t("Свайп двумя пальцами по острову переключает трек."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Поменять стороны свайпа"), isOn: settings.binding(\.swipeInverted))
                            .disabled(!settings.musicEnabled)
                        hint(t("Кому-то «следующий» — движение влево, как листают ленту, кому-то вправо, как переворачивают страницу."))
                    }
                }

        }
    }

    private var teleprompterSection: some View {
        Group {
            section(t("Телесуфлер"), icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Открыть телесуфлер"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.teleprompterHotKey },
                            set: { settings.teleprompterHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Клавиша работает переключателем: нажали при открытой панели — панель убралась."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Скорость прокрутки"), selection: settings.binding(\.teleprompterSpeed)) {
                        ForEach([10, 20, 40, 60, 90, 120], id: \.self) { value in
                            Text(tf("%d т/с", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    hint(t("Точек в секунду, а не строк: строки разной высоты, и счёт по строкам дёргал бы текст на заголовках. То же значение есть ползунком в самой панели."))
                }
            }

            section(t("Как он устроен"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Панель открывается под самой чёлкой, где камера: читая с середины экрана, человек смотрит мимо объектива, и на записи это видно."))
                    hint(t("Панель не закрывается ни по уходу курсора, ни по нажатию мимо: пока читают вслух, в чужом окне работают. Убрать — крестиком или той же клавишей."))
                    hint(t("Текст не пропадает сам — ни при закрытии панели, ни при перезапуске. Убрать его можно только кнопкой «Очистить»."))
                    hint(t("Оформление: заголовок, полужирный, курсив, подчёркивание, ссылки и эмодзи. Набранный в тексте адрес становится ссылкой сам."))
                    hint(tf("Хранится в %@ — в формате RTF, вместе с оформлением.", TeleprompterStore.fileURL.path))
                }
            }
        }
    }

    private var monitorSection: some View {
        Group {
            section(t("Нагрузка на систему"), icon: "gauge.with.dots.needle.67percent") {
                Toggle(t("Показывать нагрузку"), isOn: Binding(
                    get: { settings.monitorEnabled },
                    set: { settings.monitorEnabled = $0; onHotKeysChanged() }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Открыть нагрузку"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.monitorHotKey },
                            set: { settings.monitorHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.monitorEnabled)

                    hint(t("Три показателя: процессор, память и диск. Нажмите по любому — откроется Мониторинг системы."))
                }
            }

            section(t("Что показано и чего нет"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Память считается так же, как в Мониторинге системы: приложений, зарезервированная ядром и сжатая. Иначе числа расходились бы с ним."))
                    hint(t("Диск — том с данными, а не системный: системный доступен только для чтения и занят целиком всегда."))
                    hint(t("Видеокарты нет: публичного способа узнать её загрузку в macOS не существует, а обходной отдаёт ноль даже под нагрузкой."))
                    hint(t("Система опрашивается, только пока панель открыта: иначе мониторинг сам стал бы нагрузкой."))
                }
            }
        }
    }

    private var timerSection: some View {
        Group {
            section(t("Таймер и секундомер"), icon: "timer") {
                Toggle(t("Показывать таймер"), isOn: Binding(
                    get: { settings.timerEnabled },
                    set: { settings.timerEnabled = $0; onHotKeysChanged() }
                ))

                HStack {
                    Text(t("Открыть таймер"))
                    Spacer()
                    HotKeyRecorder(spec: Binding(
                        get: { settings.timerHotKey },
                        set: { settings.timerHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.timerEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Сигнал по окончании"), isOn: settings.binding(\.timerSoundEnabled))
                        .disabled(!settings.timerEnabled)
                    hint(t("Один короткий колокольчик. Не будильник: таймер сообщает о факте, а не требует внимания."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("После работы заводить перерыв"),
                           isOn: settings.binding(\.pomodoroChainsRest))
                        .disabled(!settings.timerEnabled)
                    hint(t("Двадцать пять минут работы, пять перерыва — помидор. Перерыв заводится сам, но запускать его вам."))
                }
            }

            section(t("Как это устроено"), icon: "clock.arrow.circlepath") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Время считается от момента запуска, а не тиком: таймер не отстаёт, даже если ноутбук закрывали."))
                    hint(t("Пока таймер идёт, свёрнутая чёлка раздвигается полоской: значок слева, счёт справа."))
                }
            }
        }
    }

    private var shelfSection: some View {
        Group {
            section(t("Полка"), icon: "tray.full") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Принимать перетаскиваемые файлы"), isOn: Binding(
                        get: { settings.shelfEnabled },
                        set: { settings.shelfEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Ведите файлы на чёлку — вырез раскроется полкой. Оттуда их вытаскивают в любое окно."))
                }

                HStack {
                    Text(t("Открыть полку"))
                    Spacer()
                    HotKeyRecorder(spec: Binding(
                        get: { settings.shelfHotKey },
                        set: { settings.shelfHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.shelfEnabled)
            }

            section(t("Как это работает"), icon: "arrow.up.and.down.and.arrow.left.and.right") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Пока файл на полке, он остаётся в своей папке. Когда вытаскиваете — переезжает, в исходной папке его больше нет."))
                    hint(t("После перезапуска полка пуста: это перевалочный пункт между двумя окнами, а не хранилище."))
                    hint(t("Полоска приёма опускается ниже чёлки: у самой кромки экрана система открывает Mission Control."))
                }
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
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.clipboardEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Клавиши записей"), selection: Binding(
                        get: { settings.clipboardSlotModifiers },
                        set: { settings.clipboardSlotModifiers = $0; onHotKeysChanged() }
                    )) {
                        ForEach(ClipboardSlotModifiers.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.clipboardEnabled)

                    hint(t("Цифра вставляет запись по номеру: первая — самая свежая. Работает и когда панель закрыта."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Вставлять сразу"), isOn: settings.binding(\.clipboardPastes))
                        .disabled(!settings.clipboardEnabled)
                    hint(t("Выключено — запись только ложится в буфер, вставить нужно самому."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Показывать плашку при копировании"),
                           isOn: settings.binding(\.clipboardShowsChip))
                        .disabled(!settings.clipboardEnabled)
                    hint(t("По плашке можно нажать — откроется история."))
                }
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
                .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)

                Picker(t("Не больше записей"), selection: settings.binding(\.clipboardLimit)) {
                    ForEach([20, 30, 50], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)

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
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Пароли: менеджеры паролей помечают такое копирование особым флагом, и запись пропускается."))
                    hint(t("Служебные копирования, которые приложения делают для своих нужд."))
                    hint(t("Изображения крупнее шести мегабайт: история должна оставаться лёгкой."))
                }
            }
        }
    }

    private var weatherSection: some View {
        Group {
            section(t("Погода в вырезе"), icon: "cloud.sun") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Показывать погоду"), isOn: Binding(
                        get: { settings.weatherEnabled },
                        set: { enabled in
                            settings.weatherEnabled = enabled
                            weather.restart()
                        }
                    ))
                    hint(t("В раскрытой панели значок и температура стоят в правом верхнем углу. Сама чёлка от этого не растёт."))
                }

                Picker(t("Сообщать"), selection: Binding(
                    get: { settings.weatherAlertMode },
                    set: { settings.weatherAlertMode = $0 }
                )) {
                    ForEach(WeatherAlertMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                .disabled(!settings.weatherEnabled)

                if settings.weatherAlertMode == .periodic {
                    Picker(t("Как часто"), selection: settings.binding(\.weatherPeriodHours)) {
                        ForEach([1, 3, 6, 12], id: \.self) { value in
                            Text(tf("%d ч", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.weatherEnabled)
                } else {
                    hint(t("Плашка всплывает, когда меняется погода или когда в ближайшие часы ожидаются осадки — один раз на явление, а не каждую проверку."))
                }
            }

            section(t("Место"), icon: "mappin.and.ellipse") {
                Picker(t("Где смотреть погоду"), selection: Binding(
                    get: { settings.weatherSource },
                    set: { settings.weatherSource = $0; weather.placeChanged() }
                )) {
                    ForEach(WeatherSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!settings.weatherEnabled)

                if settings.weatherSource == .place {
                    placePicker
                } else {
                    hint(t("Приложение запросит доступ к геопозиции. Одна засечка на обновление."))
                }
            }

            section(t("Состояние"), icon: "location") {
                weatherStatus
            }

            section(t("Откуда берётся"), icon: "network") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Прогноз запрашивается у open-meteo.com — без ключа и регистрации. Это единственное место, откуда приложение выходит в интернет."))
                    hint(t("Наружу уходят только координаты, округлённые до сотой доли градуса — примерно до километра."))
                }
            }
        }
    }

    /// Выбор города: поле поиска и список найденного.
    ///
    /// Название сохраняется вместе с координатами, а не ищется заново перед
    /// каждым запросом: Ростовов два, Владимиров тоже, и повторный поиск
    /// однажды выбрал бы другой.
    @ViewBuilder
    private var placePicker: some View {
        if let place = settings.weatherPlace {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Palette.weather)
                Text(place.title)
                Spacer()
                // Поле поиска при выбранном городе не показывается вовсе:
                // город уже назван, и второе поле рядом с ним читается
                // как «а этот тогда что».
                Button(t("Сменить")) {
                    settings.weatherPlace = nil
                    placeSearch.reset()
                }
            }
        } else {
            placeField
        }

        hint(t("Город ищется у того же open-meteo.com. Наружу уходит только название — геопозиция не нужна."))
    }

    @ViewBuilder
    private var placeField: some View {
        HStack(spacing: 8) {
            TextField(t("Название города"), text: $placeSearch.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: SettingsStyle.searchFieldWidth)
                // Ввод с клавиатуры: искать по каждой букве значило бы слать
                // запрос на каждое нажатие.
                .onSubmit { placeSearch.search() }
            Button(t("Найти")) { placeSearch.search() }
                .disabled(placeSearch.query.trimmingCharacters(in: .whitespaces).count < 2)
            if placeSearch.isSearching { ProgressView().controlSize(.small) }
        }
        .disabled(!settings.weatherEnabled)

        if let message = placeSearch.message {
            hint(message)
        }

        ForEach(placeSearch.results) { found in
            Button {
                settings.weatherPlace = found
                settings.weatherSource = .place
                placeSearch.reset()
                weather.placeChanged()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mappin").foregroundStyle(.secondary)
                    Text(found.title)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var weatherStatus: some View {
        // При выбранном городе разрешение ни при чём: показывать «доступ
        // не запрошен» там, где он и не нужен, — значит пугать без причины.
        if settings.weatherSource == .place {
            weatherReading
        } else {
            locationStatus
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        switch weather.authorization {
        case .denied, .restricted:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
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
            weatherReading
        }
    }

    /// Сам прогноз — он одинаков, откуда бы ни взялись координаты.
    @ViewBuilder
    private var weatherReading: some View {
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
        } else if settings.weatherSource == .place, settings.weatherPlace == nil {
            hint(t("Город не выбран — прогноз запрашивать не для чего."))
        } else {
            HStack(spacing: 10) {
                Text(weather.error ?? t("Прогноз ещё не загружен"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(t("Обновить")) { weather.refresh() }
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
            .frame(maxWidth: SettingsStyle.resultWidth, alignment: .leading)
            .disabled(!settings.batteryEnabled || !settings.warnOnLowBattery)
        }
    }

    private var commandsSection: some View {
        Group {
            section(t("Меню команд"), icon: "square.grid.2x2") {
                Toggle(t("Быстрые команды"), isOn: settings.binding(\.quickCommandsEnabled))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Открыть меню"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.menuHotKey },
                            set: { settings.menuHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Нажмите поле и задайте сочетание. Delete снимает, Esc отменяет. Без модификаторов не принимается: перехватывало бы обычный набор."))
                }
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
                        // Имя рядом с подсказкой, а не вместо неё: `.help`
                        // в macOS кладёт текст в подсказку элемента, а имя
                        // оставляет пустым — кнопка из одного значка так
                        // и остаётся для диктора безымянной.
                        .help(t("Обновить список моделей"))
                        .accessibilityLabel(t("Обновить список моделей"))
                    }

                    if let error = models.error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Palette.warning)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(t("Держать модель в памяти"), selection: settings.binding(\.ollamaKeepAlive)) {
                            Text(t("5 минут")).tag("5m")
                            Text(t("30 минут")).tag("30m")
                            Text(t("2 часа")).tag("2h")
                            Text(t("Постоянно")).tag("-1")
                        }
                        .pickerStyle(.menu)

                        hint(t("Ответ кладётся в буфер обмена. {{selection}} — место подстановки выделенного текста. Модель стоит держать загруженной: загрузка занимает около минуты, а модель поменьше отвечает быстрее."))
                    }
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
                // Подпись есть, но скрыта: на экране её заменяет заголовок
                // раздела, а в дереве доступности заменить нечем. С пустой
                // строкой девять выключателей слотов подряд звучали
                // одинаково — «выключатель», и никак их не различить.
                Toggle(tf("Слот %d", command.id + 1), isOn: binding(command, \.isEnabled))
                    .labelsHidden()
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
                .frame(width: SettingsStyle.hotKeyFieldNarrow.width,
                       height: SettingsStyle.hotKeyFieldNarrow.height)
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
                    .accessibilityLabel(t("Обновить список команд"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Передавать выделенный текст"), isOn: binding(command, \.passesSelection))
                    hint(t("Если команда что-то возвращает, результат попадёт в буфер обмена."))
                }
            } else {
                Text(t("Приложение «Команды» недоступно"))
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
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
                Image(nsImage: icon).resizable().frame(width: SettingsStyle.scaled(20), height: SettingsStyle.scaled(20))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsStyle.scaled(20), height: SettingsStyle.scaled(20))
            }

            Text(command.payload.isEmpty ? empty : (command.payload as NSString).lastPathComponent)
                .font(.system(size: SettingsStyle.font(12)))
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

            Picker(t("Предупреждать за"), selection: settings.binding(\.eventLeadMinutes)) {
                Text(t("в момент начала")).tag(0)
                Text(t("5 минут")).tag(5)
                Text(t("10 минут")).tag(10)
                Text(t("15 минут")).tag(15)
            }
            .pickerStyle(.menu)
            .frame(maxWidth: SettingsStyle.scaled(280), alignment: .leading)

            Toggle(t("Ещё раз в момент начала"), isOn: settings.binding(\.alertAtEventStart))
                .disabled(settings.eventLeadMinutes == 0)

            Toggle(t("Обратный отсчёт рядом с вырезом"), isOn: settings.binding(\.showCountdown))

            Picker(t("Отсчёт появляется за"), selection: settings.binding(\.countdownWindowMinutes)) {
                ForEach([5, 10, 15, 30], id: \.self) { value in
                    Text(tf("%d минут", value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: SettingsStyle.scaled(280), alignment: .leading)
            .disabled(!settings.showCountdown)

            accessStatus
        }

        section(t("Управление встречей"), icon: "video") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Кнопки встречи в вырезе"), isOn: settings.binding(\.meetingControlsEnabled))
                hint(t("Во время встречи наведение на вырез показывает микрофон, камеру, демонстрацию, поднятие руки и выход. Работает с Телемостом, Google Meet, Zoom и Teams в браузере."))
                hint(t("Кнопки нажимаются прямо на странице встречи через универсальный доступ — фокус на браузер не переключается."))
                hint(t("Вкладка встречи должна быть открыта: содержимое фоновых вкладок браузер не отдаёт. Удобнее вытащить встречу в отдельное окно."))
            }
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
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.warning)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Версия"))
                        Spacer()
                        Text(AppInfo.version)
                            .foregroundStyle(SettingsStyle.secondary)
                            .textSelection(.enabled)
                    }
                    hint(t("Вырез MacBook как центр управления: музыка, встречи, команды, ответ модели, буфер, полка, таймер, нагрузка и телесуфлер."))
                }
            }

            section(t("Жесты"), icon: "hand.draw") {
                info(t("Наведение"), t("Мини-вид: что играет и когда ближайшая встреча."))
                info(t("Нажатие или свайп вниз"), t("Панель целиком. Свайп вверх сворачивает обратно."))
                info(t("Свайп вбок"), t("Предыдущий и следующий трек."))
                info(t("Правая кнопка"), t("Меню всех функций."))
                info(t("Поглаживание"), t("Поводите курсором из стороны в сторону — вырез замурчит."))
                info(t("Нажатие по счёту таймера"), t("Пока таймер или секундомер идёт, чёлка раздвигается счётом. Нажмите по нему — откроется панель."))
                info(t("Нажатие по отсчёту до встречи"), t("Пока встреча близко, чёлка раздвигается обратным отсчётом. Нажмите по нему — раскроется главная панель."))
            }

            section(t("Что уходит наружу"), icon: "lock") {
                info(t("Погода"), t("Координаты, округлённые до километра, уходят на open-meteo.com. Это единственное обращение в интернет."))
                info(t("Модель"), t("Запросы идут в Ollama на вашем же компьютере. Наружу не уходит ничего."))
                info(t("Буфер и полка"), t("Хранятся только у вас: история — в файле приложения, полка — ссылками на ваши же файлы."))
                info(t("Телесуфлер"), t("Текст лежит в файле приложения, в формате RTF. Наружу не уходит ничего."))
            }

            section(t("Ограничения"), icon: "exclamationmark.triangle") {
                info(t("Только встроенный экран"), t("На внешних мониторах выреза нет."))
                info(t("Встреча — только в открытой вкладке"), t("Браузер не отдаёт содержимое фоновых вкладок. Вытащите встречу в отдельное окно, чтобы кнопки были всегда."))
                info("Things 3", t("Задачи видны списком, но напоминания по ним не работают: Things не отдаёт время напоминания наружу."))
                info(t("Нагрузка без видеокарты"), t("Публичного способа узнать загрузку GPU в macOS нет, а обходной отдаёт ноль даже под нагрузкой. Пустая шкала хуже, чем никакой."))
            }
        }
    }

    private func info(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: SettingsStyle.font(12), weight: .semibold))
            Text(text)
                .font(.system(size: SettingsStyle.font(11.5)))
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
                        Circle().fill(source.color).frame(width: SettingsStyle.scaled(8), height: SettingsStyle.scaled(8))
                        Text(source.title)
                    }
                }
            }
        }
    }

    /// Карточка раздела.
    ///
    /// Настоящая `Section` внутри `Form`, а не нарисованная подложка
    /// со своей обводкой и своим скруглением. Значок в заголовке остался —
    /// он в этом окне единственное, что отличает одну карточку от другой
    /// при беглом взгляде.
    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
                // Подложка карточки. Системная ушла вместе с фоном формы —
                // а без неё строки лежали прямо на плывущих пятнах, и текст
                // читался тем хуже, чем ярче пятно под ним.
                //
                // Полупрозрачная, а не глухая: сквозь неё фон виден, но уже
                // приглушённым — ровно настолько, чтобы связь с окном
                // знакомства осталась, а строка перестала спорить с пятном.
                .listRowBackground(
                    Color(nsColor: .controlBackgroundColor).opacity(0.72)
                )
        } header: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: SettingsStyle.font(11), weight: .semibold))
                    .foregroundStyle(SettingsStyle.tertiary)
                Text(title)
                    .font(.system(size: SettingsStyle.font(12), weight: .semibold))
                    .foregroundStyle(SettingsStyle.secondary)
            }
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
                    .font(.system(size: SettingsStyle.font(isCode ? 11 : 12),
                                  design: isCode ? .monospaced : .default))
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(.system(size: SettingsStyle.font(isCode ? 11 : 12),
                              design: isCode ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        // Рамка системная. Своя была нарисована двумя прямоугольниками,
        // и обводка у неё выходила 1.26:1 к подложке карточки при норме 3:1
        // для границ элементов управления: поле для промта выглядело
        // как пустое место в карточке. Системная норму держит по определению
        // и сама показывает фокус — тем же способом, что все прочие поля.
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    /// Пояснение под настройкой.
    ///
    /// Во всю ширину строки, а не по содержимому: в `Form` строка занимает
    /// всю карточку, и текст, прижатый к центру, читался бы как подпись
    /// к соседнему элементу управления, а не как пояснение к своему.
    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: SettingsStyle.font(11.5)))
            .foregroundStyle(SettingsStyle.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Линия сверху убрана: пояснение относится к настройке над ним,
            // а разделитель отрезал его от неё и приклеивал к следующей.
            // Снизу линия остаётся — она и отделяет пару «настройка
            // с пояснением» от того, что идёт дальше.
            .listRowSeparator(.hidden, edges: .top)
    }
}
