import AVFoundation
import SwiftUI

/// Выбранная вкладка настроек.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class SettingsSelection: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        // Порядок — тот, в каком приложение настраивают сверху вниз:
        // общее, сам вырез, то, что он показывает (музыка, погода, календарь),
        // главный экран, который собирает плитки из этого, затем модель и то,
        // что на ней держится, — команды, голос, заметки, сводки, — и в конце
        // инструменты и справка. Музыка и календарь стояли девятым и восьмым
        // разделами, хотя это главное, ради чего вырез открывают.
        //
        // «Уведомления» — сразу за вырезом: всё, что всплывает под чёлкой,
        // собрано в одном месте. Раньше плашки жили в «Вырезе», предупреждения
        // о встречах — в «Календаре», перерывы — в «Инструментах», а звонок
        // попал в «Календарь» просто потому, что рядом стояли встречи, —
        // пользователь сразу сказал, что звонки к календарю отношения не имеют.
        case general, notch, notifications, inNotch, calendar, home, model, commands, voice, notes, feeds, tools, info
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return t("Основные")
            case .notch: return t("Вырез")
            case .notifications: return t("Уведомления")
            case .home: return t("Главный экран")
            case .commands: return t("Команды")
            case .model: return t("ИИ")
            case .voice: return t("Голос")
            case .notes: return t("Заметки")
            case .feeds: return t("Сводки")
            case .calendar: return t("Календарь")
            case .inNotch: return t("Музыка и погода")
            case .tools: return t("Инструменты")
            case .info: return t("Инфо")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            // Вырез своей формой: раздел про него самого.
            case .notch: return "macbook.gen2"
            case .notifications: return "bell.badge.fill"
            case .home: return "square.grid.3x2.fill"
            case .commands: return "square.grid.2x2.fill"
            case .model: return "sparkles"
            case .voice: return "waveform"
            case .notes: return "list.bullet.rectangle"
            case .feeds: return "newspaper.fill"
            case .calendar: return "calendar"
            case .inNotch: return "music.note"
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
            case .notch: return Palette.clipboard
            case .notifications: return Palette.warning
            case .home: return Palette.welcome
            case .commands: return Palette.commands
            case .model: return Palette.assistant
            case .voice: return Palette.voice
            case .notes: return Palette.notes
            case .feeds: return Palette.feeds
            case .calendar: return Palette.calendar
            case .inNotch: return Palette.voice
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

    /// Над какой плиткой главного экрана держат перетаскиваемую — и какая
    /// выделена. Здесь по той же причине, что и подсветка цели у команд.
    @Published var homeDropTarget: Int?
    @Published var homeSelected: Int?

    /// Раскрыт ли раздел «Дополнительно» с адресами и ключами.
    ///
    /// В объекте, а не в настройке напрямую: `@State` в этом тулчейне
    /// недоступен, а раскрытие обязано пережить перерисовку. Настройка
    /// хранит его между запусками — здесь живёт то, что видно сейчас.
    @Published var showsAdvancedProviders = Settings.shared.showsAdvancedProviders

    /// У какой команды открыт выбор значка. `nil` — ни у какой.
    ///
    /// Здесь по той же причине, что и подсветка цели: `@State` в этом
    /// тулчейне недоступен, а `popover` нужен `Binding<Bool>`, переживающий
    /// перерисовку.
    @Published var symbolPickerFor: Int?

    /// Набранное в полях добавления темы и сайта — по той же причине.
    @Published var newDigestTopic = ""
    /// Отмеченные галочкой темы из подсказки модели.
    @Published var chosenTopicSuggestions: Set<String> = []
    @Published var newSiteURL = ""
    @Published var newSiteTarget = ""
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
    @ObservedObject var installer = ModelInstaller.shared
    @ObservedObject var engine = OllamaEngine.shared
    /// Языковые наборы расшифровки: что установлено и как поставить.
    @ObservedObject var transcripts = TranscriptAssets()
    /// Обновления: строка состояния и подпись кнопки живут от её состояния.
    @ObservedObject var updates: UpdateService
    /// Сводки и слежка: состояние последней сборки и найденные значения.
    @ObservedObject var digest: DigestService
    @ObservedObject var siteWatch: SiteWatchService
    /// Доступы — общим узлом со знакомством.
    @ObservedObject var permissions: PermissionCenter
    /// Поиск города. Живёт снаружи, а не в теле вида: `@State` в этом SDK
    /// недоступен, а полю ввода и списку найденного где-то держаться надо.
    @ObservedObject var placeSearch: WeatherPlaceSearch
    /// «Уменьшить прозрачность»: из неё считаются плотности `SettingsStyle`.
    /// Наблюдается здесь, в корне окна, — оттуда перерисовка расходится
    /// по всем разделам.
    @ObservedObject var motion = MotionPreference.shared
    @ObservedObject var power = PowerPreference.shared
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
    /// Показать образец вопроса от программы — чтобы было видно, о чём
    /// вообще настройка, до того как её включать.
    let onPreviewNotice: () -> Void

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
    var sidebar: some View {
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
    var detail: some View {
        Form {
            Group {
                switch selection.tab {
                case .general: generalSection
                case .notch: notchSection
                case .notifications: notificationsSection
                case .home: homeSection
                case .model: modelSection
                case .commands: commandsSection
                case .voice: voiceSection
                case .notes: notesSection
                case .feeds: feedsSection
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

    // MARK: - Запись и расшифровка

    /// Что вырез показывает **сам**, без спроса: трек, погода, питание.
    ///
    /// Признак деления назван словами, и в этом весь смысл перестройки:
    /// пятнадцать разделов делились по функциям, то есть ни по чему —
    /// предсказать, где искать музыку, было нельзя, её приходилось помнить.
    // MARK: - Главный экран

    // MARK: - Вырез

    // MARK: - Сводки и сайты

    // MARK: - Движок моделей

    // MARK: - Модели к скачиванию

    // MARK: - Дополнительно

    /// Функция раздела держится на модели, а модель выключена. Сказано
    /// здесь, а не только в «ИИ»: человек ищет причину там, где не работает.
    func modelRequiredCard(_ text: String) -> some View {
        section(t("Нужна модель"), icon: "exclamationmark.triangle") {
            HStack {
                Text(text)
                    .foregroundStyle(SettingsStyle.secondary)
                Spacer()
                Button(t("Открыть «ИИ»")) { selection.tab = .model }
            }
        }
    }

    // MARK: - Доступы и сочетания

    /// Карточка раздела.
    ///
    /// Настоящая `Section` внутри `Form`, а не нарисованная подложка
    /// со своей обводкой и своим скруглением. Значок в заголовке остался —
    /// он в этом окне единственное, что отличает одну карточку от другой
    /// при беглом взгляде.
    /// То же, но со значком провайдера вместо системного символа.
    func section<Content: View>(
        _ title: String,
        mark provider: AIProvider,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, icon: nil, mark: provider, content: content)
    }

    func section<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        section(title, icon: icon, mark: nil, content: content)
    }

    func section<Content: View>(
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
    func multilineEditor(
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
    func hint(_ text: String) -> some View {
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
