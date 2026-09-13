import SwiftUI

/// Что умеют плитки главного экрана.
///
/// Одной структурой, а не очередными параметрами `NotchView`: у виджетов
/// двадцать с лишним действий, и замыкания поштучно раздули бы и без того
/// самый длинный список параметров в приложении. Собирает её `NotchView`
/// из того, что уже получил от контроллера, — нового пути к службам нет.
struct HomeActions {
    let openSettings: () -> Void
    let openHub: () -> Void
    let openCalendar: () -> Void
    let openItem: (CalendarItem) -> Void
    let join: (URL) -> Void
    let copyLink: (URL) -> Void
    let openTasks: () -> Void
    /// `nil` — выключены и модель, и заметки: спросить некого и записать
    /// некуда.
    let ask: (() -> Void)?
    let dictateQuestion: () -> Void
    let openTimer: () -> Void
    let openMonitor: () -> Void
    let openAwake: () -> Void
    let chooseAwakeLimit: (Int) -> Void
    let disableAwake: () -> Void
    let openFeeds: (FeedsPanelState.Mode) -> Void
    let openClipboard: () -> Void
    let openShelf: () -> Void
    let openNotes: () -> Void
    let openNote: (Note) -> Void
    let newNote: () -> Void
    let startVoice: () -> Void
    let dictateNote: () -> Void
    let openTeleprompter: () -> Void
}

/// Службы, из которых плитки берут данные. Каждая плитка подписывается
/// на свою сама: вёрстка сверху передаёт ссылку, а ссылка на тот же объект
/// для SwiftUI — «ничего не поменялось», и без своей подписки плитка
/// застыла бы на первом кадре.
struct HomeServices {
    let music: MusicClient
    let planner: CalendarPlanner
    let things: ThingsService
    let timer: TimerService
    let monitor: MonitorService
    let weather: WeatherService
    let battery: BatteryMonitor
    let wake: WakeGuard
    let digest: DigestService
    let sites: SiteWatchService
    let clipboard: ClipboardService
    let shelf: ShelfStore
    let notes: NotesService
    let dictation: Dictation
}

/// Главный экран: плитки по раскладке из настроек.
struct HomePanel: View {
    @ObservedObject var settings: Settings
    @ObservedObject var weather: WeatherService
    @ObservedObject var wake: WakeGuard
    let services: HomeServices
    /// Встречи из снимка состояния, а не из календаря напрямую: вырез
    /// показывает тот же список, по которому решал, что показывать.
    let events: [CalendarItem]
    let metrics: NotchMetrics
    let actions: HomeActions

    var body: some View {
        let grid = HomeGrid.place(settings.homeWidgets)
        let placed = Set(grid.placements.map(\.widget.kind))
        NotchPanel(
            metrics: metrics,
            width: metrics.expanded(rows: 0).width,
            // Поле от чёрного тела: плитки тянутся во всю ширину, и вогнутое
            // плечо формы съедало бы у крайних три четверти бокового поля.
            bodyPadding: HomeGrid.bodyPadding
        ) {
            // Погода и чашка в крыле — только пока их нет плитками: одно
            // и то же в двух местах одного экрана человек читает как две
            // разные вещи.
            HStack(spacing: 6) {
                if settings.weatherEnabled, !placed.contains(.weather), let snapshot = weather.current {
                    WeatherCorner(snapshot: snapshot, notchHeight: metrics.notchHeight)
                }
                if settings.caffeineEnabled, !placed.contains(.caffeine) {
                    CaffeineButton(isOn: wake.isOn, action: actions.openAwake)
                }
            }
            .frame(height: metrics.notchHeight)
        } trailing: {
            HStack(spacing: 2) {
                // «Всё сразу» переехала сюда из строки музыки: музыка стала
                // плиткой, которой на экране может и не быть. Открывает она
                // кольцо кружков — единственное меню всех функций.
                NotchPanelButton(symbol: "circle.grid.cross.fill", hint: t("Всё сразу"), action: actions.openHub)
                if let ask = actions.ask, !placed.contains(.ask) {
                    NotchPanelButton(symbol: "sparkles", hint: t("Команды"), action: ask)
                }
                NotchPanelButton(symbol: "gearshape", hint: t("Настройки"), action: actions.openSettings)
            }
        } content: {
            ZStack(alignment: .topLeading) {
                ForEach(grid.placements) { placement in
                    let origin = HomeGrid.origin(of: placement)
                    HomeWidgetView(
                        widget: placement.widget,
                        settings: settings,
                        services: services,
                        events: events,
                        actions: actions
                    )
                    .offset(x: origin.x, y: origin.y)
                }
            }
            // Размер задан, а не выведен из плиток: высоту панели считает
            // расчёт состояния, и сетка обязана занять ровно столько же.
            .frame(
                width: HomeGrid.contentWidth,
                height: HomeGrid.contentHeight(rows: grid.rows),
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
        }
    }
}

// MARK: - Плитка

/// Подложка плитки: размер по раскладке, отклик на курсор, нажатие по телу.
///
/// Нажатие — жестом на подложке, а не кнопкой вокруг содержимого: кнопка,
/// вложенная в кнопку, нажатий не получает, а у плиток внутри свои кнопки —
/// пауза, пуск, «подключиться». Жест у родителя уступает кнопке ребёнка.
struct HomeTile<Content: View>: View {
    let widget: HomeWidget
    var onTap: (() -> Void)?
    /// Что откроет нажатие — подписью под чёлкой.
    var hint: String?
    @ViewBuilder var content: () -> Content

    static var inset: CGFloat { NotchStyle.scaled(10) }
    static var verticalInset: CGFloat { NotchStyle.scaled(8) }

    /// Место под содержимое: плитка за вычетом полей.
    static func inner(_ size: HomeWidgetSize) -> CGSize {
        let outer = HomeGrid.size(of: size)
        return CGSize(width: outer.width - 2 * inset, height: outer.height - 2 * verticalInset)
    }

    var body: some View {
        let size = HomeGrid.size(of: widget.size)
        NotchTile(
            id: "home-\(widget.id)",
            radius: NotchStyle.cardRadius,
            role: onTap == nil ? .card : .tile
        ) {
            content()
                .padding(.horizontal, Self.inset)
                .padding(.vertical, Self.verticalInset)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous))
                .onTapGesture {
                    guard let onTap else { return }
                    Haptics.tap(.levelChange)
                    onTap()
                }
                .notchActionHint(hint ?? widget.kind.title)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(widget.kind.title)
                .accessibilityAction { onTap?() }
        }
    }
}

/// Подпись плитки: значок цвета функции и название.
struct HomeCaption: View {
    let kind: HomeWidgetKind
    var title: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: kind.symbol)
                .font(.system(size: NotchStyle.font(9.5), weight: .semibold))
                .foregroundStyle(kind.tint)
            Text(title ?? kind.title)
                .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: NotchStyle.scaled(14))
    }
}

/// Круглая кнопка внутри плитки.
struct HomeTileButton: View {
    let symbol: String
    let hint: String
    var diameter: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(.white)
                .symbolSwap(symbol)
        }
        .buttonStyle(NotchButtonStyle(diameter: diameter))
        .notchHint(hint)
    }
}

/// Крупное значение: градусы, проценты, остаток таймера.
struct HomeValue: View {
    let text: String
    var size: CGFloat = 20

    var body: some View {
        Text(text)
            .font(.system(size: NotchStyle.font(size), weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Строка пустоты: «встреч нет», «сводок ещё не было».
struct HomeEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: NotchStyle.font(11)))
            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            .lineLimit(2)
    }
}

/// Строка списка в плитке: значок или точка, текст, подпись справа.
struct HomeListRow: View {
    let text: String
    var detail: String?
    var dot: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let dot {
                Circle().fill(dot).frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: NotchStyle.font(11.5)))
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.system(size: NotchStyle.font(10.5), weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: HomeListRow.height)
    }

    static var height: CGFloat { NotchStyle.scaled(17) }

    /// Сколько строк списка встанет под подписью в плитке этого размера.
    static func capacity(_ size: HomeWidgetSize, captioned: Bool = true) -> Int {
        let available = HomeTile<EmptyView>.inner(size).height
            - (captioned ? NotchStyle.scaled(14) + 4 : 0)
        return max(1, Int((available + 1) / (height + 1)))
    }
}

// MARK: - Выбор вёрстки

/// Плитка нужного вида.
struct HomeWidgetView: View {
    let widget: HomeWidget
    @ObservedObject var settings: Settings
    let services: HomeServices
    let events: [CalendarItem]
    let actions: HomeActions

    var body: some View {
        // Выключенная функция не пропадает с экрана, а остаётся
        // приглушённой — так же, как кружок в кольце.
        if widget.kind.isEnabled(settings) {
            content
        } else {
            HomeTile(widget: widget) {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCaption(kind: widget.kind)
                        .opacity(0.5)
                    HomeEmpty(text: t("Выключено"))
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .music:
            MusicWidget(widget: widget, music: services.music)
        case .schedule:
            ScheduleWidget(widget: widget, events: events, actions: actions)
        case .month:
            MonthWidget(widget: widget, planner: services.planner, actions: actions)
        case .tasks:
            TasksWidget(widget: widget, things: services.things, actions: actions)
        case .ask:
            AskWidget(widget: widget, settings: settings, actions: actions)
        case .timer:
            TimerWidget(widget: widget, timer: services.timer, actions: actions)
        case .weather:
            WeatherWidget(widget: widget, weather: services.weather)
        case .monitor:
            MonitorWidget(widget: widget, monitor: services.monitor, actions: actions)
        case .battery:
            BatteryWidget(widget: widget, battery: services.battery)
        case .caffeine:
            CaffeineWidget(widget: widget, wake: services.wake, settings: settings, actions: actions)
        case .news:
            NewsWidget(widget: widget, digest: services.digest, actions: actions)
        case .sites:
            SitesWidget(widget: widget, sites: services.sites, settings: settings, actions: actions)
        case .clipboard:
            ClipboardWidget(widget: widget, clipboard: services.clipboard, actions: actions)
        case .shelf:
            ShelfWidget(widget: widget, shelf: services.shelf, actions: actions)
        case .notes:
            NotesWidget(widget: widget, notes: services.notes, actions: actions)
        case .voice:
            LauncherWidget(widget: widget, action: actions.startVoice)
        case .dictation:
            LauncherWidget(widget: widget, action: actions.dictateNote)
        case .teleprompter:
            LauncherWidget(widget: widget, action: actions.openTeleprompter)
        }
    }
}
