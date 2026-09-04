import AVFoundation
import SwiftUI

/// Выбранная вкладка настроек.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class SettingsSelection: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        // Порядок — от общего к частному, и «ИИ» стоит вторым не по алфавиту:
        // на модели держатся и команды, и заметки, и голос. Человек, у которого
        // не работает ни одно из трёх, ищет причину там, где её включают, —
        // а раздел был третьим, за командами, то есть за одним из следствий.
        case general, model, commands, voice, notes, calendar, inNotch, tools, info
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return t("Основные")
            case .commands: return t("Команды")
            case .model: return t("ИИ")
            case .voice: return t("Голос")
            case .notes: return t("Заметки")
            case .calendar: return t("Календарь")
            case .inNotch: return t("В вырезе")
            case .tools: return t("Инструменты")
            case .info: return t("Инфо")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .commands: return "square.grid.2x2.fill"
            case .model: return "sparkles"
            case .voice: return "waveform"
            case .notes: return "list.bullet.rectangle"
            case .calendar: return "calendar"
            // Вырез своей формой: раздел про то, что показывает он сам.
            case .inNotch: return "macbook.gen2"
            // Ящик с инструментом — то, за чем тянутся рукой.
            case .tools: return "wrench.and.screwdriver.fill"
            case .info: return "info"
            }
        }

        /// Цвет плитки значка — по нему раздел узнаётся боковым зрением
        /// быстрее, чем по названию.
        var tint: Color {
            switch self {
            case .general: return Palette.neutral
            case .commands: return Palette.commands
            case .model: return Palette.assistant
            case .voice: return Palette.voice
            case .notes: return Palette.notes
            case .calendar: return Palette.calendar
            case .inNotch: return Palette.clipboard
            case .tools: return Palette.shelf
            case .info: return Palette.neutral
            }
        }
    }

    @Published var tab: Tab = .general

    /// Над какой командой сейчас держат перетаскиваемую. `nil` — ни над какой.
    ///
    /// Живёт здесь, а не в самой карточке: `@State` в этом тулчейне
    /// недоступен, а подсветка цели обязана пережить перерисовку. Одна на всё
    /// окно — целей одновременно всё равно не бывает двух.
    @Published var commandDropTarget: Int?

    /// У какой команды открыт выбор значка. `nil` — ни у какой.
    ///
    /// Здесь по той же причине, что и подсветка цели: `@State` в этом
    /// тулчейне недоступен, а `popover` нужен `Binding<Bool>`, переживающий
    /// перерисовку.
    @Published var symbolPickerFor: Int?
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var calendar: CalendarService
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var models: ModelList
    @ObservedObject var shortcuts: ShortcutsService
    @ObservedObject var browsers: BrowserList
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var weather: WeatherService
    /// Заметки: их число показывается в разделе, а очистка идёт через службу.
    @ObservedObject var notes: NotesService
    @ObservedObject var obsidian: ObsidianService
    let linker: NoteLinker
    @ObservedObject private var installer = ModelInstaller.shared
    /// Обновления: строка состояния и подпись кнопки живут от её состояния.
    @ObservedObject var updates: UpdateService
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
    /// Открыть описание выпуска — ту же страницу окна знакомства, что
    /// показывается сама после обновления.
    let onOpenReleaseNotes: () -> Void
    /// Прочитать образец выбранным голосом. Выбирать его иначе нечем:
    /// у голосов случайные имена, а разница между ними — только на слух.
    let onPreviewVoice: () -> Void
    /// Подержать вырез раскрытым, пока человек смотрит на то, что настраивает.
    ///
    /// Ползунок прозрачности меняет вид выреза, а живёт в другом окне: панель
    /// раскрывается по наведению, и курсор в этот миг держит ползунок —
    /// настройку крутили бы вслепую.
    let onPreviewNotch: (TimeInterval) -> Void

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
                case .general: generalSection
                case .model: modelSection
                case .commands: commandsSection
                case .voice: voiceSection
                case .notes: notesSection
                case .calendar: calendarSection
                case .inNotch: inNotchSection
                case .tools: toolsSection
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

    /// Состояние проверки и кнопка рядом с ним.
    ///
    /// Текст и подпись кнопки приходят из одной `UpdateStatusText.line(for:)`:
    /// «Готово к установке» рядом с кнопкой «Проверить» было бы не опечаткой,
    /// а обещанием, которого приложение не выполнит.
    @ViewBuilder
    private var updateStatusRow: some View {
        let line = UpdateStatusText.line(for: updates.state)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(line.text).foregroundStyle(.secondary)
                // Раньше здесь стояла ссылка на страницу GitHub, и появлялась
                // она только у скачанного обновления. В остальное время
                // карточка обновлений не отзывалась ни на что — а «что там
                // нового» спрашивают как раз чаще до загрузки, чем после.
                // Теперь кнопка стоит всегда и ведёт не в браузер, а в окно
                // знакомства: описание выпусков приложение показывает само.
                Button(t("Что нового")) { onOpenReleaseNotes() }
                    .buttonStyle(.link)
                Spacer()
                switch line.action {
                case .check:
                    Button(t("Проверить")) { updates.check(manual: true) }
                case .install:
                    Button(t("Обновить")) { updates.install() }
                case .busy:
                    Button(t("Проверить")) {}.disabled(true)
                }
            }
            if case .install = line.action {
                hint(t("Приложение перезапустится. Доступы останутся выданными."))
            }
        }
    }

    private var generalSection: some View {
        Group {
                // Первой карточкой: с обновлением человек приходит сюда
                // по плашке из выреза, и искать его среди мурчания и размера
                // текста ему незачем.
                section(t("Обновления"), icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Проверять обновления"), isOn: settings.binding(\.autoUpdateEnabled))
                        hint(t("Раз в сутки спрашивает GitHub и скачивает новую версию фоном."))
                    }
                    HStack {
                        Text(t("Версия"))
                        Spacer()
                        Text(AppInfo.version).textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    updateStatusRow
                }

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
                            Text(t("Прозрачность выреза"))
                            Spacer()
                            // Слово рядом с ползунком: доля сама по себе
                            // ничего не значит, мнение бывает о «матовее»,
                            // а не о «шестидесяти процентах».
                            Text(Surface.DensityScale.title(for: settings.notchDensity))
                                .foregroundStyle(SettingsStyle.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.notchDensity) },
                                set: {
                                    settings.notchDensity = Int($0.rounded())
                                    // Вырез раскрывается на время правки:
                                    // иначе прозрачность настраивают вслепую —
                                    // панель показывается по наведению,
                                    // а курсор держит ползунок.
                                    //
                                    // Срок короткий и продлевается каждым
                                    // движением: отпустил — через пару секунд
                                    // вырез сам вернётся к своему делу.
                                    onPreviewNotch(2)
                                }
                            ),
                            in: 0...Double(Surface.DensityScale.opaque),
                            // Шаг, а не плавный ход: соседние доли на глаз
                            // не различаются, и плавный ползунок обещал бы
                            // разницу, которой нет.
                            step: 5,
                            // Раскрыть и в тот миг, когда ползунок только
                            // взяли: человек мог взяться и держать, ничего
                            // ещё не сдвинув, — а смотреть уже начал.
                            onEditingChanged: { editing in
                                if editing { onPreviewNotch(4) }
                            }
                        )
                        .frame(maxWidth: SettingsStyle.pickerWidth)
                        hint(t("До упора вправо — сплошной чёрный вырез, как было."))
                    }
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
                        hint(t("Открывает главную панель. Повторное нажатие сворачивает."))
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
                        hint(t("Действует в этом окне и в окне знакомства."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(t("Держать плашки событий"), selection: settings.binding(\.activityHold)) {
                            ForEach(Settings.activityHolds, id: \.self) { scale in
                                Text(Self.activityHoldTitle(scale)).tag(scale)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                        hint(t("Как долго держатся плашки событий."))
                        hint(t("Наведение на вырез убирает плашку в любом случае."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t("Знакомство с вырезом"))
                            Spacer()
                            Button(t("Открыть")) { onOpenWelcome() }
                        }
                        hint(t("Жесты, сочетания и доступы."))
                    }
                }
        }
    }

    private var voiceSection: some View {
        Group {
            section(t("Голосовой ассистент"), icon: "waveform") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Голосовой ассистент"), isOn: Binding(
                        get: { settings.voiceEnabled },
                        set: { settings.voiceEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Вопрос голосом, ответ вслух. Панель не раскрывается — вырез светится."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Спросить голосом"), selection: Binding(
                        get: { settings.voiceTrigger },
                        set: { settings.voiceTrigger = $0; onHotKeysChanged() }
                    )) {
                        ForEach(VoiceTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled)

                    Picker(t("Спросить по заметкам"), selection: Binding(
                        get: { settings.voiceNotesTrigger },
                        set: { settings.voiceNotesTrigger = $0; onHotKeysChanged() }
                    )) {
                        ForEach(VoiceTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled || !settings.notesEnabled)

                    hint(t("Модификатор, нажатый дважды подряд, без других клавиш между нажатиями."))
                    hint(t("Нужен Универсальный доступ."))
                    if settings.voiceTrigger == settings.voiceNotesTrigger,
                       settings.voiceTrigger != .off {
                        hint(t("Оба вызова на одном модификаторе — сработает только первый."))
                    }
                }
            }

            section(t("Как слушать"), icon: "mic") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Язык распознавания"), selection: Binding(
                        get: { settings.voiceLanguage },
                        set: { settings.voiceLanguage = $0 }
                    )) {
                        Text(t("Как в интерфейсе")).tag(Language?.none)
                        ForEach(Language.allCases) { language in
                            Text(language.title).tag(Language?.some(language))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled)
                    hint(t("Можно говорить не на языке интерфейса."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Пауза до конца фразы"), selection: settings.binding(\.voiceSilenceTenths)) {
                        ForEach([8, 12, 15, 20, 30], id: \.self) { tenths in
                            Text(tf("%@ с", Self.seconds(tenths))).tag(tenths)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled)
                    hint(t("Сколько молчания считается концом вопроса."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Заметок в голосовой вопрос"), selection: settings.binding(\.voiceNotesContextLimit)) {
                        ForEach([2_000, 4_000, 6_000, 12_000, 24_000], id: \.self) { value in
                            Text(tf("%d тыс. знаков", value / 1_000)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled || !settings.notesEnabled)
                    hint(t("Меньше, чем в тексте: голосового ответа ждут ушами."))
                }
            }

            section(t("Как отвечать"), icon: "speaker.wave.2") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Голос"), selection: Binding(
                        get: { settings.voiceIdentifier },
                        set: { settings.voiceIdentifier = $0 }
                    )) {
                        Text(t("Лучший из установленных")).tag(String?.none)
                        ForEach(voices, id: \.identifier) { voice in
                            Text(SpeechSpeaker.title(for: voice))
                                .tag(String?.some(voice.identifier))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled)

                    HStack {
                        Spacer()
                        Button(t("Прослушать")) { onPreviewVoice() }
                            .disabled(!settings.voiceEnabled)
                    }
                    // Выбирать голос глазами нельзя: имена у них случайные —
                    // системный премиальный русский зовётся «Голос 2»,
                    // и по названию не понять о нём ничего. Слышно только
                    // на слух, значит слушать надо прямо здесь.
                    hint(t("Новые голоса — в «Универсальный доступ» → «Чтение вслух». Компактные звучат роботом."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Скорость чтения"), selection: settings.binding(\.voiceRateStep)) {
                        ForEach(-SpeechSpeaker.rateSteps...SpeechSpeaker.rateSteps, id: \.self) { step in
                            Text(Self.rateTitle(step)).tag(step)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.voiceEnabled)
                }
            }
        }
    }

    /// Голоса, установленные для языка, на котором будут отвечать.
    private var voices: [AVSpeechSynthesisVoice] {
        SpeechSpeaker.voices(for: settings.voiceLanguage ?? Localization.shared.resolved)
    }

    /// Скорость подписью, а не числом: «−2» человеку ничего не говорит.
    private static func rateTitle(_ step: Int) -> String {
        switch step {
        case 0: return t("Обычная")
        case ..<0: return tf("Медленнее на %d", -step)
        default: return tf("Быстрее на %d", step)
        }
    }

    /// Десятые доли секунды словами: «1,5» вместо «15».
    private static func seconds(_ tenths: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: Double(tenths) / 10)) ?? "\(tenths)"
    }

    private var notesSection: some View {
        Group {
            section(t("Заметки"), icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Заметки"), isOn: Binding(
                        get: { settings.notesEnabled },
                        set: { settings.notesEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Живут в панели модели. Работают и с выключенной Ollama."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Новая заметка"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.notesHotKey },
                            set: { settings.notesHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.notesEnabled)
                    hint(t("Открывает пустую заметку. Список — кнопкой в той же панели."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Выделенное в заметки"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.noteSelectionHotKey },
                            set: { settings.noteSelectionHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.notesEnabled)
                    hint(t("Записывает выделенный текст, ничего не открывая."))
                    hint(t("Нужен Универсальный доступ."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Скопированное в заметки"))
                    hint(t("Кнопка есть в истории буфера и на плашке о копировании."))
                    hint(t("Только для текста."))
                }
                .disabled(!settings.notesEnabled || !settings.clipboardEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Имя заметке придумывает модель"), isOn: settings.binding(\.notesTitleByModel))
                        .disabled(!settings.notesEnabled || !settings.ollamaEnabled)
                    hint(t("Сразу ставится из даты и первой строки, потом модель уточняет."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Искать по смыслу"), isOn: Binding(
                        get: { settings.notesVectorSearch },
                        set: { settings.notesVectorSearch = $0; linker.refreshAll() }
                    ))
                    hint(t("Модели уходят только подходящие заметки, а не все подряд."))
                }
                .disabled(!settings.notesEnabled || !settings.ollamaEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Заметок под вопрос"), selection: settings.binding(\.notesVectorCount)) {
                        ForEach([4, 6, 10, 15, 20], id: \.self) { value in
                            Text(tf("%d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    hint(t("Сколько подходящих заметок отдавать модели."))
                }
                .disabled(!settings.notesEnabled || !settings.ollamaEnabled || !settings.notesVectorSearch)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Заметок в контекст модели"), selection: settings.binding(\.notesContextLimit)) {
                        ForEach([8_000, 16_000, 24_000, 48_000, 96_000], id: \.self) { value in
                            Text(tf("%d тыс. знаков", value / 1_000)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    .disabled(!settings.notesEnabled || !settings.ollamaEnabled)
                    hint(t("Сколько заметок уходит модели. Больше — дольше ответ."))
                }
            }

            section(t("Что с ними делать"), icon: "square.and.arrow.up") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tf("Заметок сейчас: %d", notes.total))
                        Spacer()
                        Button(t("Очистить все"), role: .destructive, action: clearNotes)
                            .disabled(notes.total == 0)
                    }
                    hint(tf("Хранятся в %@. Выгрузка в Markdown — кнопкой в самом списке заметок.", NotesStore.defaultURL.path))
                }
            }

            obsidianSection
            linksSection
        }
    }

    /// Карточка связей.
    ///
    /// Связи ищут векторами: совпадение слов на вопрос «о том же ли» не
    /// отвечает. Запись в файлы — отдельным переключателем: одно дело
    /// показать связи, другое — писать в личные файлы человека.
    private var linksSection: some View {
        section(t("Связи между заметками"), icon: "point.3.filled.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Искать связи"), isOn: Binding(
                    get: { settings.obsidianLinksEnabled },
                    set: { settings.obsidianLinksEnabled = $0; linksChanged() }
                ))
                hint(t("Модель находит заметки об одном и том же, даже когда общих слов в них нет."))
            }
            .disabled(!settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                embedModelPicker
                hint(t("Отдельная модель: она не отвечает словами, а считает смысл."))
                installRow(RecommendedModel.embed)
            }
            .disabled(!settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Насколько близкими считать"), selection: settings.binding(\.obsidianLinkThreshold)) {
                    ForEach([60, 70, 80, 90], id: \.self) { value in
                        Text(tf("%d%%", value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                hint(t("Ниже — связей больше, но случайных тоже."))
            }
            .disabled(!settings.obsidianLinksEnabled || !settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Только у новых заметок"), isOn: settings.binding(\.linksOnlyNew))
                hint(t("У большого архива первый проход — часы работы модели."))
                if settings.linksOnlyNew, settings.linksSince != nil {
                    Button(t("Связать и старые")) {
                        settings.linksSince = nil
                        linker.refreshAll()
                    }
                }
            }
            .disabled(!settings.obsidianLinksEnabled || !settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Дописывать связи в файлы Obsidian"), isOn: settings.binding(\.obsidianLinksToFiles))
                hint(t("Отдельным блоком между невидимыми метками — в графе они станут настоящими ссылками."))
            }
            .disabled(!settings.obsidianLinksEnabled || !settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Button(t("Убрать блоки связей из файлов"), action: obsidian.removeAllLinkBlocks)
                    .disabled(!settings.obsidianEnabled)
                hint(t("Снимает их подчистую. Остальной текст файлов не трогает."))
            }
        }
    }

    /// Выбор модели, считающей векторы.
    ///
    /// Список тот же, что и у обычных моделей, — Ollama не разделяет их
    /// у себя, — но выбранное показывается даже когда список не пришёл:
    /// пустое поле выглядело бы как «модель не выбрана», а она выбрана,
    /// просто сервер сейчас молчит.
    private var embedModelPicker: some View {
        let provider = settings.aiProvider
        let found = models.models(of: provider, kind: .embedding)
        let current = ModelRef.parse(settings.embedModel, fallback: provider)?.name ?? ""
        return HStack {
            Picker(t("Модель для векторов"), selection: Binding(
                get: { current },
                set: { settings.embedModel = ModelRef(provider: provider, name: $0).stored }
            )) {
                if !found.contains(where: { $0.name == current }) {
                    Text(current.isEmpty ? t("не выбрана") : current).tag(current)
                }
                ForEach(found, id: \.self) { model in
                    Text(model.name).tag(model.name)
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
            .help(t("Обновить список"))
            .accessibilityLabel(t("Обновить список"))
        }
    }

    /// Строка «этой модели нет — скачать».
    ///
    /// Показывается только когда модели и правда нет: у того, у кого она уже
    /// стоит, кнопка была бы предложением сделать сделанное. Пока идёт
    /// загрузка, на её месте полоса — модель весит гигабайты, и кнопка
    /// без отклика читалась бы как несработавшая.
    @ViewBuilder
    private func installRow(_ name: String) -> some View {
        if installer.isInstalling(name) {
            HStack(spacing: 8) {
                ProgressView(value: installedShare).controlSize(.small)
                Text(tf("Качаю %@ — %d%%", name, Int(installedShare * 100)))
                    .foregroundStyle(SettingsStyle.tertiary)
                Button(t("Отменить"), action: installer.cancel)
            }
        } else if !isInstalled(name), settings.aiProvider == .ollama {
            HStack(spacing: 8) {
                Button(tf("Скачать %@", name)) { installer.install(name) }
                    .disabled(installer.isBusy)
                if case .failed(let text) = installer.state {
                    Text(text)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Есть ли такая модель. Для векторной достаточно **любой** векторной:
    /// человек мог скачать не рекомендованную, а другую, и предлагать ему
    /// вторую такую же незачем.
    private func isInstalled(_ name: String) -> Bool {
        if name == RecommendedModel.embed {
            return !models.models(of: settings.aiProvider, kind: .embedding).isEmpty
        }
        return RecommendedModel.isInstalled(name, among: models.models(of: .ollama))
    }

    private var installedShare: Double {
        if case .pulling(let share) = installer.state { return share }
        return 0
    }

    /// Выключенные связи не оставляют за собой ничего: ни векторов, ни связей.
    private func linksChanged() {
        guard settings.obsidianLinksEnabled else {
            settings.linksSince = nil
            linker.clearLinks()
            return
        }
        // Граница «новизны» ставится в тот миг, когда связи включили:
        // всё, что человек запишет после, — новое.
        if settings.linksSince == nil { settings.linksSince = Date() }
        linker.refreshAll()
    }

    /// Карточка Obsidian.
    ///
    /// Стоит внутри «Заметок», а не отдельным разделом слева: разделов
    /// и так девять, а это по существу заметки. Всё, кроме переключателя,
    /// гаснет при выключенной синхронизации — прячется только выбор папки,
    /// потому что без него остальное бессмысленно.
    private var obsidianSection: some View {
        section(t("Obsidian"), icon: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Синхронизация с Obsidian"), isOn: Binding(
                    get: { settings.obsidianEnabled },
                    set: { settings.obsidianEnabled = $0; obsidian.settingsChanged() }
                ))
                hint(t("Заметки лягут в хранилище файлами, а его заметки найдутся поиском."))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vaultPathTitle)
                        .foregroundStyle(settings.obsidianVaultPath.isEmpty
                            ? SettingsStyle.tertiary : SettingsStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button(t("Выбрать папку…"), action: chooseVault)
                }
                hint(vaultHint)
            }
            .disabled(!settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                field(
                    t("Папка для заметок"),
                    prompt: Vault.defaultFolder,
                    text: Binding(
                        get: { settings.obsidianFolder },
                        set: { settings.obsidianFolder = $0 }
                    )
                )
                hint(t("Внутри хранилища. Можно вложенную: «Заметки/Trunook»."))
            }
            .disabled(!settings.obsidianEnabled)
            .onSubmit { obsidian.folderChanged() }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Искать и по заметкам хранилища"), isOn: Binding(
                    get: { settings.obsidianIndexVault },
                    set: { settings.obsidianIndexVault = $0; obsidian.sync(manual: true) }
                ))
                hint(t("Они появляются в поиске и уходят в контекст модели. Править их можно только в Obsidian."))
            }
            .disabled(!settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(obsidianStateText)
                        .foregroundStyle(obsidianStateColor)
                    Spacer()
                    Button(t("Синхронизировать"), action: { obsidian.sync(manual: true) })
                        .disabled(!settings.obsidianEnabled || settings.obsidianVaultPath.isEmpty)
                }
                hint(tf("Свои заметки лежат в подпапке «%@». Остальное хранилище приложение только читает.", settings.obsidianFolder))
            }
            .disabled(!settings.obsidianEnabled)
        }
    }

    private var vaultPathTitle: String {
        let path = settings.obsidianVaultPath
        return path.isEmpty ? t("Папка не выбрана") : (path as NSString).abbreviatingWithTildeInPath
    }

    /// Предупреждения — короткой фразой и только по делу: папка не выбрана,
    /// папка пропала, папка не похожа на хранилище.
    private var vaultHint: String {
        guard !settings.obsidianVaultPath.isEmpty else {
            return t("У Obsidian нет постоянного места — папку называете вы.")
        }
        guard let vault = obsidian.vault else { return t("У Obsidian нет постоянного места — папку называете вы.") }
        if !vault.isReachable { return t("Папка не читается: диск отключён или её переименовали.") }
        if !vault.looksLikeVault { return t("Внутри нет папки .obsidian — на хранилище не похоже.") }
        return t("Приложение пишет в эту папку. Удаляет только в Корзину.")
    }

    private var obsidianStateText: String {
        switch obsidian.state {
        case .off: return t("Выключено")
        case .noFolder: return t("Папка не выбрана")
        case .unreachable: return t("Папка недоступна — ничего не тронуто")
        case .emptied: return t("Файлов вдруг стало меньше — сверка остановлена")
        case .syncing: return t("Сверяю…")
        case .never: return t("Сверки ещё не было")
        case .synced(let date): return tf("Сверено в %@", Self.timeText(date))
        }
    }

    private var obsidianStateColor: Color {
        switch obsidian.state {
        case .unreachable, .emptied: return Palette.warning
        default: return SettingsStyle.secondary
        }
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter.string(from: date)
    }

    /// Папку называет человек. Ни одного предположения о том, где хранилище
    /// лежит, в коде нет: у Obsidian нет постоянного места, и угаданный путь
    /// однажды оказался бы не тем.
    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("Выбрать")
        panel.message = t("Где лежит хранилище Obsidian")
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        settings.obsidianVaultPath = folder.path
        obsidian.settingsChanged()
        obsidian.sync(manual: true)
    }

    /// Очистка спрашивает подтверждение: это единственный способ потерять
    /// все заметки разом, а мимо кнопки в настройках попадают так же,
    /// как и везде.
    private func clearNotes() {
        let alert = NSAlert()
        alert.messageText = t("Удалить все заметки?")
        alert.informativeText = t("Вернуть их будет нельзя. Выгрузите их в папку, если они ещё пригодятся.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: t("Удалить"))
        alert.addButton(withTitle: t("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        notes.clearAll()
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
                    hint(t("Нажатие при открытой панели закрывает её."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Скорость прокрутки"), selection: settings.binding(\.teleprompterSpeed)) {
                        ForEach([10, 20, 40, 60, 90, 120], id: \.self) { value in
                            Text(tf("%d т/с", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)
                    hint(t("Точек в секунду. То же есть ползунком в самой панели."))
                }
            }

            section(t("Как он устроен"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Не закрывается щелчком мимо. Убрать — крестиком или клавишей."))
                    hint(t("Текст сохраняется до кнопки «Очистить»."))
                    hint(t("Заголовок, начертания, ссылки и эмодзи."))
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

                    hint(t("Процессор, память и диск. Нажатие открывает Мониторинг системы."))
                }
            }

            section(t("Что показано и чего нет"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Считается как в Мониторинге системы."))
                    hint(t("Том с данными, не системный."))
                    hint(t("Видеокарты нет: macOS не отдаёт её загрузку."))
                    hint(t("Опрашивается только при открытой панели."))
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
                    hint(t("Один короткий сигнал, не будильник."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("После работы заводить перерыв"),
                           isOn: settings.binding(\.pomodoroChainsRest))
                        .disabled(!settings.timerEnabled)
                    hint(t("Двадцать пять минут работы, пять перерыва."))
                }
            }

            section(t("Как это устроено"), icon: "clock.arrow.circlepath") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: 8) {
                    hint(t("Пока таймер идёт, чёлка показывает счёт."))
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
                    hint(t("Файл остаётся в своей папке, пока его не вытащат."))
                    hint(t("После перезапуска полка пуста."))
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

                    hint(t("Цифра вставляет запись по номеру. Работает и при закрытой панели."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Вставлять сразу"), isOn: settings.binding(\.clipboardPastes))
                        .disabled(!settings.clipboardEnabled)
                    hint(t("Выключено — запись только ложится в буфер."))
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
                    hint(t("Пароли: менеджеры помечают их, и запись пропускается."))
                    hint(t("Служебные копирования, которые приложения делают для своих нужд."))
                    hint(t("Изображения крупнее шести мегабайт."))
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
                    hint(t("Значок и температура в углу раскрытой панели."))
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
                    hint(t("Один раз на явление, а не каждую проверку."))
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
                    hint(t("Приложение запросит доступ к геопозиции."))
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
                    hint(t("Прогноз берётся у open-meteo.com."))
                    hint(t("Наружу уходят координаты, округлённые до километра."))
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

        hint(t("Наружу уходит только название города."))
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

    /// Чашка кофе. Живёт в «Инструментах»: её включают руками, как таймер
    /// и полку, — а стояла она в «Общих» просто потому, что туда попала.
    private var caffeineCard: some View {
        Group {
                // Выбор срока отсюда ушёл: он появился в самой панели чашки —
                // там же, где отсчёт и кнопка «Выключить». Настройка «что
                // предлагать по умолчанию» пережила появление живого выбора
                // и стала лишней: решение одно, а мест, где его принимают,
                // стало два. Осталось то, чего в вырезе нет, — сам показ.
                section(t("Чашка кофе"), icon: "cup.and.saucer") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Показывать чашку"), isOn: settings.binding(\.caffeineEnabled))
                        hint(t("Пока включена, экран не гаснет. Срок задаётся нажатием по чашке."))
                        hint(t("Удержание не переживает перезапуск приложения."))
                    }
                }
        }
    }

    /// Музыка. Живёт в «В вырезе»: вырез показывает трек сам, без спроса.
    private var musicCard: some View {
        Group {
                section(t("Музыка"), icon: "music.note") {
                    Toggle(t("Управление музыкой"), isOn: settings.binding(\.musicEnabled))
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Показывать смену трека"), isOn: settings.binding(\.showTrackChanges))
                            .disabled(!settings.musicEnabled)
                        hint(t("Работает с любым плеером: сведения читаются из системы."))
                        hint(t("Свайп двумя пальцами по острову переключает трек."))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Поменять стороны свайпа"), isOn: settings.binding(\.swipeInverted))
                            .disabled(!settings.musicEnabled)
                    }
                }
        }
    }

    /// Что вырез показывает **сам**, без спроса: трек, погода, питание.
    ///
    /// Признак деления назван словами, и в этом весь смысл перестройки:
    /// пятнадцать разделов делились по функциям, то есть ни по чему —
    /// предсказать, где искать музыку, было нельзя, её приходилось помнить.
    private var inNotchSection: some View {
        Group {
            musicCard
            weatherSection
            batterySection
        }
    }

    /// Что **вызывают руками**: буфер, полка, таймер, нагрузка, телесуфлер,
    /// чашка.
    ///
    /// Шесть карточек — не перегрузка: у каждой один-два переключателя
    /// и сочетание клавиш. Вместе выходит короче прежних «Общих», где было
    /// десять переключателей и двенадцать пояснений.
    private var toolsSection: some View {
        Group {
            clipboardSection
            shelfSection
            timerSection
            monitorSection
            teleprompterSection
            caffeineCard
        }
    }

    private var commandsSection: some View {
        Group {
            section(t("Команды"), icon: "square.grid.2x2") {
                Toggle(t("Показывать список команд"), isOn: settings.binding(\.quickCommandsEnabled))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Спросить о выделенном"))
                        Spacer()
                        HotKeyRecorder(spec: Binding(
                            get: { settings.assistantHotKey },
                            set: { settings.assistantHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Захватывает выделенное и открывает разговор с моделью."))
                }

                // Про подстановку сказано здесь, а не в разделе модели:
                // `{{selection}}` — свойство самой команды, а не модели,
                // и человек ищет его там, где пишет промт.
                hint(t("{{selection}} — место захваченного текста."))
                hint(t("Сочетание команды переезжает вместе с ней, а не остаётся за строкой."))
                hint(t("Модель меняется и в вырезе: Tab или нажатие по её имени в строке."))

                if !settings.ollamaEnabled {
                    // Сказать прямо, а не гасить весь раздел: команды,
                    // которым модель не нужна, работают как работали,
                    // и правят их здесь же.
                    Label(
                        t("Модель выключена — запросы к ней в список не попадают. Остальные команды работают."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
                }
            }

            ForEach(Array(settings.quickCommands.enumerated()), id: \.element.id) { index, command in
                commandEditor(command, at: index)
            }

            section(t("Ещё команда"), icon: "plus") {
                Button(t("Добавить команду")) { settings.addCommand() }
            }
        }
    }

    /// Настройки модели — своим разделом, а не внутри команд.
    ///
    /// Внутри команд они и лежали, пока модель была нужна только им. Теперь
    /// на ней держатся ещё и заметки: имя записи, поиск по всему архиву,
    /// разговор в панели. Настройка, спрятанная в разделе одной из функций,
    /// выглядит её частью — и человек, у которого не работают заметки, ищет
    /// причину где угодно, кроме раздела «Команды».
    /// Кто отвечает: основной провайдер среди включённых.
    ///
    /// Основной отвечает на свободный вопрос и на команды, у которых своей
    /// модели нет. Выбирается он **только среди включённых**: назначить
    /// основным выключенного значило бы отправлять вопрос туда, где его
    /// никто не ждёт, и понять это по экрану было бы нельзя.
    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(t("Основной"), selection: Binding(
                get: { settings.aiProvider },
                set: { settings.aiProvider = $0; models.refresh() }
            )) {
                ForEach(settings.enabledProviders) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: SettingsStyle.pickerWidth, alignment: .leading)

            hint(t("Ему уходят свободный вопрос и команды без своей модели."))
        }
    }

    /// Настройки одного провайдера: адрес, ключ, модель.
    ///
    /// Своим разделом на каждого, а не общими полями на всех. Общими они были
    /// ровно одну версию, и этого хватило: ключ от прежнего провайдера
    /// оставался в поле нового, уходил с запросом и получал отказ, в котором
    /// виноватым выглядел новый сервер.
    private func providerSection(_ provider: AIProvider) -> some View {
        // Заголовок — маркой самого провайдера, той же, что стоит в строке
        // команды. Две разные картинки на одного означали бы, что связать
        // раздел настроек со строкой в вырезе можно только по названию.
        section(provider.title, mark: provider) {
            if provider.isRemote {
                // Сказано прямо и с предупреждающим знаком: это единственное
                // место в приложении, где вопрос и захваченный текст уходят
                // с машины. Промолчать об этом было бы обманом умолчанием.
                Label(
                    t("Вопросы и захваченный текст уходят в интернет этому сервису."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(Palette.warning)
            }

            field(
                t("Адрес"),
                prompt: provider == .ollama
                    ? Settings.defaultOllamaURL
                    : (provider.presetURL ?? "https://…/v1"),
                text: Binding(
                    get: { settings.apiURLRaw(for: provider) },
                    set: { settings.setAPIURL($0, for: provider) }
                )
            )

            if provider.usesKey {
                VStack(alignment: .leading, spacing: 4) {
                    field(
                        t("Ключ доступа"),
                        prompt: "sk-…",
                        text: Binding(
                            get: { settings.apiKey(for: provider) },
                            set: { settings.setAPIKey($0, for: provider) }
                        ),
                        isSecret: true
                    )
                    hint(t("Хранится в настройках приложения, не в связке ключей."))
                }
            }

            providerModelPicker(provider)

            // Удержание модели в памяти — свойство Ollama, а не разговора:
            // у прочих этим распоряжается сервер, и настройка, показанная
            // рядом, обещала бы влияние, которого у неё нет.
            // Пустой список моделей у свежепоставленной Ollama — обычное
            // дело: сервер есть, моделей в нём нет. Раньше это был тупик
            // с уходом в терминал; теперь рядом кнопка.
            if provider == .ollama {
                installRow(RecommendedModel.chat)
            }

            if provider == .ollama {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Держать модель в памяти"), selection: settings.binding(\.ollamaKeepAlive)) {
                        Text(t("5 минут")).tag("5m")
                        Text(t("30 минут")).tag("30m")
                        Text(t("2 часа")).tag("2h")
                        Text(t("Постоянно")).tag("-1")
                    }
                    .pickerStyle(.menu)

                    hint(t("Первый запрос после простоя ждёт загрузки модели — около минуты."))
                }
            }

            // Основного не убрать: без него запрос уходить некуда. Кнопка
            // остаётся видимой и погашенной — исчезнувшая читалась бы как
            // «этого провайдера убрать нельзя вообще», хотя достаточно
            // назначить основным другого.
            HStack {
                Spacer()
                Button(t("Убрать провайдера"), role: .destructive) {
                    settings.setProvider(provider, enabled: false)
                    models.refresh()
                }
                .disabled(provider == settings.aiProvider)
            }
        }
    }

    private func providerModelPicker(_ provider: AIProvider) -> some View {
        // Векторные модели сюда не попадают: они не отвечают словами вовсе,
        // и выбранная по ошибке молчала бы на каждый вопрос.
        let found = models.models(of: provider, kind: .chat)
        let current = settings.apiModel(for: provider)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker(t("Модель"), selection: Binding(
                    get: { current },
                    set: { settings.setAPIModel($0, for: provider) }
                )) {
                    // Выбранное показываем, даже когда список не пришёл:
                    // иначе поле выглядит пустым, будто модель не выбрана
                    // вовсе, — а она выбрана, просто сервер сейчас молчит.
                    if !found.contains(where: { $0.name == current }) {
                        Text(current.isEmpty ? t("не выбрана") : current).tag(current)
                    }
                    ForEach(found, id: \.self) { model in
                        // Имя провайдера здесь не нужно: раздел уже его,
                        // и повторять было бы шумом. Марка остаётся —
                        // по ней строка узнаётся боковым зрением.
                        Label {
                            Text(model.name)
                        } icon: {
                            ProviderIcon(provider: provider, size: SettingsStyle.font(13))
                        }
                        .tag(model.name)
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
                // Имя рядом с подсказкой, а не вместо неё: `.help` в macOS
                // кладёт текст в подсказку элемента, а имя оставляет пустым —
                // кнопка из одного значка так и остаётся для диктора
                // безымянной.
                .help(t("Обновить список моделей"))
                .accessibilityLabel(t("Обновить список моделей"))
            }
        }
    }

    /// Чего ещё нет в списке.
    ///
    /// Меню, а не длинный список переключателей: провайдеров дюжина,
    /// а держат обычно один-два, и одиннадцать выключенных строк заняли бы
    /// весь раздел, ничего о себе не сообщая.
    private var addProviderMenu: some View {
        let rest = AIProvider.allCases.filter { !settings.isProviderEnabled($0) }
        return Menu(t("Добавить провайдера")) {
            Section(t("На этом компьютере")) {
                ForEach(rest.filter(\.isLocal)) { provider in
                    Button(provider.title) { add(provider) }
                }
            }
            Section(t("В интернете")) {
                ForEach(rest.filter { $0.isRemote }) { provider in
                    Button(provider.title) { add(provider) }
                }
            }
            if rest.contains(.custom) {
                Section {
                    Button(AIProvider.custom.title) { add(.custom) }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(rest.isEmpty)
    }

    private func add(_ provider: AIProvider) {
        settings.setProvider(provider, enabled: true)
        // Список моделей перечитывается сразу: у нового провайдера он свой,
        // и без запроса его модели не появятся в выборе ни у одной команды.
        models.refresh()
    }

    /// Поле ввода с подписью над ним.
    ///
    /// Подпись сверху, а не слева, и рамка обязательна. Без рамки поле
    /// не видно вовсе: `Form` рисует значение простым текстом у правого края,
    /// и пустое поле выглядит просто отсутствующим — строка «Ключ доступа»
    /// стояла с пустотой справа, и вписать в неё что-либо человек
    /// не догадывался. Длинная подпись вдобавок переносилась на две строки
    /// и отжимала поле к краю.
    private func field(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        isSecret: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(SettingsStyle.secondary)

            Group {
                if isSecret {
                    SecureField(title, text: text, prompt: Text(prompt))
                } else {
                    TextField(title, text: text, prompt: Text(prompt))
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: SettingsStyle.pickerWidth)
        }
    }

    /// Настройки модели — своим разделом, а не внутри команд.
    ///
    /// Внутри команд они и лежали, пока модель была нужна только им. Теперь
    /// на ней держатся ещё и заметки: имя записи, поиск по всему архиву,
    /// разговор в панели. Настройка, спрятанная в разделе одной из функций,
    /// выглядит её частью — и человек, у которого не работают заметки, ищет
    /// причину где угодно, кроме раздела «Команды».
    private var modelSection: some View {
        Group {
            section(t("Запросы к модели"), icon: "sparkles") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Использовать модель"), isOn: settings.binding(\.ollamaEnabled))
                    hint(t("Нужна командам, разговору и заметкам."))
                }

                if settings.ollamaEnabled, settings.enabledProviders.count > 1 {
                    providerPicker
                }

                if let error = models.error, settings.ollamaEnabled {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Palette.warning)
                }
            }

            if settings.ollamaEnabled {
                ForEach(settings.enabledProviders) { provider in
                    providerSection(provider)
                }

                section(t("Ещё провайдер"), icon: "plus") {
                    addProviderMenu
                }
            }
        }
    }

    /// Одна команда: заголовок с её местом в списке, поля и перестановка.
    ///
    /// Место команды показано номером в заголовке, а меняется перетаскиванием
    /// за ручку в первой строке — см. `dragHandle`.
    private func commandEditor(_ command: QuickCommand, at index: Int) -> some View {
        section(tf("%d. %@", index + 1, sectionTitle(for: command)), icon: command.effectiveSymbol) {
            // Всё, что опознаёт команду, — одной строкой: ручка, выключатель,
            // значок, название, клавиша, удаление. Порознь это занимало три
            // строки на карточку, а карточек столько же, сколько команд, —
            // до нижних приходилось прокручивать полэкрана.
            HStack(spacing: 8) {
                dragHandle(command)

                // Подпись есть, но скрыта: на экране её заменяет заголовок
                // раздела, а в дереве доступности заменить нечем. С пустой
                // строкой все выключатели команд подряд звучали одинаково —
                // «выключатель», и никак их не различить.
                Toggle(sectionTitle(for: command), isOn: binding(command, \.isEnabled))
                    .labelsHidden()

                symbolButton(command)

                // Подпись скрыта: в узкой строке она встаёт **над** полем
                // и карточка растёт на строку — ровно то, от чего уходили.
                // Приглашение внутри поля говорит то же самое, а диктору
                // остаётся имя.
                TextField(text: binding(command, \.title), prompt: Text(t("Название"))) {
                    Text(t("Название"))
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)

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

                Button {
                    settings.removeCommand(id: command.id)
                    // Сочетание уходит вместе с командой: оставленное
                    // зарегистрированным, оно молча срабатывало бы в пустоту
                    // до следующего перезапуска.
                    onHotKeysChanged()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(t("Удалить команду"))
                .accessibilityLabel(tf("Удалить команду «%@»", sectionTitle(for: command)))
            }

            // Действие и модель — в одну строку: обе отвечают на «чем это
            // выполнить», и стоять им порознь незачем.
            HStack(spacing: 12) {
                Picker(t("Действие"), selection: binding(command, \.kind)) {
                    ForEach(QuickCommand.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                if command.kind.usesModel { modelPicker(command) }
            }

            payloadEditor(command)
        }
        // Приглушённая карточка — та же мысль, что и предупреждение выше,
        // но у конкретной команды: эта в список сейчас не попадает.
        // Не `disabled`: править её никто не запрещал, а починить настройку
        // из погашенного поля было бы нечем.
        .opacity(command.kind.usesModel && !settings.ollamaEnabled ? 0.55 : 1)
    }

    /// Название раздела команды.
    ///
    /// У новой команды названия ещё нет, а заголовок «2.» без ничего не даёт
    /// понять, что это за раздел и почему он пуст.
    private func sectionTitle(for command: QuickCommand) -> String {
        command.title.isEmpty ? t("Новая команда") : command.title
    }

    /// Ручка перетаскивания — значок в начале первой строки карточки.
    ///
    /// Перетаскивание вместо кнопок «выше» и «ниже»: кнопками порядок из семи
    /// команд меняется десятком нажатий, и после каждого список
    /// перерисовывается — ту же карточку приходится искать глазами заново.
    ///
    /// Ручкой, а не всей карточкой: раздел собран из `Section` внутри `Form`,
    /// а модификатор, повешенный на `Section`, достаётся **каждой её строке**
    /// порознь. Перетаскивалось бы тогда поле промта, переключатель и выбор
    /// модели — по отдельности и каждое само по себе.
    ///
    /// Переносится строка с номером, а не сама команда: `Transferable`
    /// у `QuickCommand` означал бы, что её можно вытащить наружу приложения,
    /// где она никому не нужна и ничего не значит.
    private func dragHandle(_ command: QuickCommand) -> some View {
        let isTarget = selection.commandDropTarget == command.id
        return Image(systemName: "line.3.horizontal")
            .foregroundStyle(isTarget ? Color.accentColor : .secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isTarget ? Color.accentColor.opacity(0.18) : .clear)
            )
            .draggable(String(command.id)) {
                Label(sectionTitle(for: command), systemImage: command.effectiveSymbol)
                    .padding(6)
            }
            .dropDestination(for: String.self) { items, _ in
                selection.commandDropTarget = nil
                guard let raw = items.first, let moved = Int(raw) else { return false }
                settings.moveCommand(id: moved, onto: command.id)
                return true
            } isTargeted: { targeted in
                // Своё — только своё: курсор уже мог перейти на соседнюю
                // карточку, и та успела записаться раньше, чем эта сообщила
                // об уходе.
                if targeted {
                    selection.commandDropTarget = command.id
                } else if selection.commandDropTarget == command.id {
                    selection.commandDropTarget = nil
                }
            }
            .animation(.easeOut(duration: 0.12), value: isTarget)
            .help(t("Перетащите, чтобы поменять порядок"))
            .accessibilityLabel(tf("Переставить команду «%@»", sectionTitle(for: command)))
    }

    /// Значок команды — тот, что стоит в её строке под чёлкой.
    ///
    /// Кнопкой с текущим значком, а не разложенной палитрой: тридцать шесть
    /// значков занимали в карточке шесть строк — больше, чем всё остальное
    /// вместе взятое, — и это в разделе, где карточек столько же, сколько
    /// команд. Выбирают значок один раз, а прокручивают мимо него каждый раз.
    ///
    /// Палитрой, а не полем для имени символа: имя пришлось бы знать наизусть
    /// («text.badge.checkmark»), опечатка в нём давала бы пустое место
    /// в строке под чёлкой, а свериться было бы негде — приложение SF Symbols
    /// ставится вместе с Xcode, которого на этой машине нет.
    private func symbolButton(_ command: QuickCommand) -> some View {
        Button {
            selection.symbolPickerFor = command.id
        } label: {
            Image(systemName: command.effectiveSymbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .help(t("Значок"))
        .accessibilityLabel(t("Значок"))
        .popover(
            isPresented: Binding(
                get: { selection.symbolPickerFor == command.id },
                set: { shown in
                    if !shown, selection.symbolPickerFor == command.id {
                        selection.symbolPickerFor = nil
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            symbolGrid(command)
        }
    }

    private func symbolGrid(_ command: QuickCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Значок"))
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 34), spacing: 6)],
                spacing: 6
            ) {
                symbolChoice(command, symbol: "", isDefault: true)
                ForEach(CommandSymbols.all, id: \.self) { symbol in
                    symbolChoice(command, symbol: symbol, isDefault: false)
                }
            }
            .frame(width: 280)

            Text(t("Первый — как у действия: меняется вместе с ним."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private func symbolChoice(
        _ command: QuickCommand,
        symbol: String,
        isDefault: Bool
    ) -> some View {
        let isOn = command.symbol == symbol
        let shown = isDefault ? command.kind.defaultSymbol : symbol
        return Button {
            guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
            else { return }
            updated.symbol = symbol
            settings.updateCommand(updated)
            selection.symbolPickerFor = nil
        } label: {
            Image(systemName: shown)
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                )
                .overlay(
                    // Пунктиром — «как у действия»: он не выбран из палитры,
                    // а взят у вида, и рисовать его наравне с остальными
                    // значило бы прятать разницу.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isDefault && !isOn ? 0.25 : 0),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        // Имя постоянное, состояние отдельным значением: меняющееся имя
        // диктор прочтёт как другую кнопку.
        .accessibilityLabel(isDefault ? t("Как у действия") : shown)
        .accessibilityValue(isOn ? t("выбрано") : "")
        .help(isDefault ? t("Как у действия") : shown)
    }

    /// Какой моделью выполнять эту команду.
    ///
    /// Отдельно от общей модели в разделе «Модель»: там задают ту, которой
    /// отвечают все, здесь — исключение для одной команды. «Как в настройках»
    /// первым пунктом и есть отсутствие исключения.
    private func modelPicker(_ command: QuickCommand) -> some View {
        // Без пояснения рядом: оно одно и то же у всех команд, а места
        // в строке отнимало столько, что оба выпадающих списка сжимались
        // до «Запрос к м…» и «Как в настро…». Сказано один раз, сверху.
        Picker(t("Модель"), selection: Binding(
            get: { settings.quickCommands.first { $0.id == command.id }?.model ?? "" },
            set: { name in
                guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                else { return }
                updated.model = name.isEmpty ? nil : name
                settings.updateCommand(updated)
            }
        )) {
            Text(tf("Как в настройках (%@)", settings.defaultModel.shortName)).tag("")
            // Выбранная когда-то модель могла исчезнуть с сервера — или
            // сам сервер выключили. Без этого пункта список показал бы
            // пустую строку, и было бы неясно, что вообще выбрано.
            if let stored = command.model, !known.contains(stored) {
                Text(tf("%@ — не найдена", stored)).tag(stored)
            }
            ForEach(models.models, id: \.self) { model in
                // Марка провайдера и его имя: в окне настроек места хватает
                // обоим, а одно и то же имя модели бывает у двух серверов
                // сразу — выбор из двух одинаковых строк не выбор.
                Label {
                    Text(CommandRows.full(model))
                } icon: {
                    ProviderIcon(provider: model.provider, size: SettingsStyle.font(13))
                }
                .tag(model.stored)
            }
        }
        .pickerStyle(.menu)
    }

    /// Сохранённые имена моделей — чтобы отличить исчезнувшую от найденной.
    private var known: Set<String> { Set(models.models.map(\.stored)) }



    /// Поле значения зависит от типа: путь выбирается диалогом, готовое
    /// действие — списком, и только промт и свой скрипт пишутся руками.
    @ViewBuilder
    private func payloadEditor(_ command: QuickCommand) -> some View {
        switch command.kind {
        case .saveToNotes:
            // Заполнять нечего: команда работает с захваченным текстом,
            // а не со своим содержимым. Пустое поле здесь предлагало бы
            // вписать то, чего у неё нет.
            hint(t("Кладёт захваченный текст заметкой, без модели."))

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
        case .saveToNotes:
            return QuickCommand.Kind.saveToNotes.title
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
                hint(t("Микрофон, камера, демонстрация, рука и выход. Телемост, Meet, Zoom, Teams."))
                hint(t("Вкладка встречи должна быть открыта."))
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
                    hint(t("Вырез MacBook как центр управления: музыка, встречи, команды, модель с заметками, буфер, полка, таймер, нагрузка и телесуфлер."))
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
                info(t("Погода"), t("Координаты, округлённые до километра, уходят на open-meteo.com."))
                info(t("Обновления"), t("Раз в сутки приложение спрашивает у github.com, нет ли новой версии. Проверку можно выключить."))
                info(t("Модель"), t("Запросы идут туда, чей адрес задан в разделе «ИИ». По умолчанию — на ваш же компьютер."))
                info(t("Заметки"), t("Лежат в файле приложения. При поиске по ним текст уходит той же Ollama на вашем компьютере — и больше никуда."))
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
    /// То же, но со значком провайдера вместо системного символа.
    private func section<Content: View>(
        _ title: String,
        mark provider: AIProvider,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, icon: nil, mark: provider, content: content)
    }

    private func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, icon: icon, mark: nil, content: content)
    }

    private func section<Content: View>(
        _ title: String,
        icon: String?,
        mark provider: AIProvider?,
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
                Group {
                    if let provider {
                        ProviderIcon(provider: provider, size: SettingsStyle.font(13))
                    } else {
                        Image(systemName: icon ?? "circle")
                            .font(.system(size: SettingsStyle.font(11), weight: .semibold))
                    }
                }
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
