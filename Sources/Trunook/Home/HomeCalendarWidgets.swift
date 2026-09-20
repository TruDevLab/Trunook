import SwiftUI
import TrunookXPC

// MARK: - Музыка

/// Трек и одна кнопка — «играть» или «пауза».
///
/// «Назад» и «вперёд» не добавлены и в широкой плитке: перематывают свайпом
/// двумя пальцами, а кнопки повторяли бы жест ценой места под название.
struct MusicWidget: View {
    let widget: HomeWidget
    @ObservedObject var music: MusicClient

    var body: some View {
        HomeTile(widget: widget) {
            switch widget.size {
            case .small:
                HStack(spacing: 6) {
                    artwork(side: 38)
                    Spacer(minLength: 0)
                    transport
                }
                .frame(maxHeight: .infinity)
            case .large:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        artwork(side: 64)
                        Spacer(minLength: 0)
                        transport
                    }
                    titles
                }
            default:
                HStack(spacing: 10) {
                    artwork(side: widget.size == .full ? 44 : 40)
                    titles
                    Spacer(minLength: 6)
                    transport
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// Играет ли что-нибудь на самом деле: в паузах между треками
    /// MediaRemote присылает запись с пустым названием.
    private var hasTrack: Bool { !(music.nowPlaying?.title ?? "").isEmpty }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hasTrack ? music.nowPlaying?.title ?? "" : t("Ничего не играет"))
                .font(.system(size: NotchStyle.font(12.5), weight: .semibold))
                .lineLimit(1)
            if hasTrack, let artist = music.nowPlaying?.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: NotchStyle.font(11)))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .lineLimit(1)
            }
        }
    }

    private func artwork(side: CGFloat) -> some View {
        Group {
            if let data = music.nowPlaying?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
    }

    private var transport: some View {
        let isPlaying = music.nowPlaying?.isPlaying == true
        return HomeTileButton(
            symbol: isPlaying ? "pause.fill" : "play.fill",
            hint: isPlaying ? t("Пауза") : t("Играть"),
            diameter: 30
        ) {
            music.send(.togglePlayPause)
        }
    }
}

// MARK: - Ближайшие встречи

/// Ближайшее время и то, что идёт следом.
///
/// В один ряд — одна встреча, в два — до трёх. Кнопка встречи стоит с трёх
/// колонок, ссылка рядом с ней — только во всю ширину: в узкой плитке они
/// отнимали бы место у названия, а название и отвечает на вопрос «что за
/// встреча».
struct ScheduleWidget: View {
    let widget: HomeWidget
    let events: [CalendarItem]
    let actions: HomeActions

    static var rowHeight: CGFloat { NotchStyle.scaled(34) }

    private var capacity: Int {
        let height = HomeTile<EmptyView>.inner(widget.size).height
        return max(1, Int((height + NotchStyle.rowSpacing) / (Self.rowHeight + NotchStyle.rowSpacing)))
    }

    private var visible: [CalendarItem] { Array(events.prefix(capacity)) }

    private var showsJoin: Bool { widget.size.columns >= 3 }
    private var showsCopy: Bool { widget.size.columns == HomeGrid.columns }

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openCalendar, hint: t("Открыть календарь")) {
            if visible.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCaption(kind: widget.kind)
                    HomeEmpty(text: t("Встреч нет"))
                }
            } else {
                // В один ряд строка встаёт по центру плитки, в два — сверху:
                // список, повисший посередине, читается как недогруженный.
                VStack(alignment: .leading, spacing: NotchStyle.rowSpacing) {
                    ForEach(visible) { event in
                        row(event)
                    }
                }
                .frame(maxHeight: .infinity, alignment: widget.size.rows == 1 ? .center : .top)
            }
        }
    }

    private func row(_ event: CalendarItem) -> some View {
        HStack(spacing: 8) {
            Button { actions.openItem(event) } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: NotchStyle.font(12)))
                            .lineLimit(1)
                        Text(event.isAllDay ? event.timeLabel : "\(event.timeLabel) · \(event.countdown())")
                            .font(.system(size: NotchStyle.font(10), weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchActionHint(t("Открыть в Календаре"))

            if showsJoin, let link = event.link {
                if showsCopy {
                    Button { actions.copyLink(link.url) } label: {
                        Image(systemName: "link")
                            .font(.system(size: NotchStyle.font(11), weight: .semibold))
                            .padding(7)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                    .buttonStyle(PressableStyle())
                    .notchHint(t("Скопировать ссылку"))
                }

                Button { actions.join(link.url) } label: {
                    Label(link.provider.title, systemImage: link.provider.symbol)
                        .font(.system(size: NotchStyle.font(11), weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
            }
        }
    }
}

// MARK: - Месяц

/// Сетка месяца: сегодня выделено, дни со встречами ярче пустых.
struct MonthWidget: View {
    let widget: HomeWidget
    @ObservedObject var planner: CalendarPlanner
    let actions: HomeActions

    var body: some View {
        let grid = planner.grid
        HomeTile(widget: widget, onTap: actions.openCalendar, hint: t("Открыть календарь")) {
            VStack(alignment: .leading, spacing: 2) {
                HomeCaption(kind: widget.kind, title: Self.monthTitle(grid.anchor))
                VStack(spacing: 0) {
                    ForEach(grid.weeks) { week in
                        HStack(spacing: 0) {
                            ForEach(week.days) { day in
                                cell(day)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        // Разметку дней планировщик держит только для открытого месяца:
        // открываем его здесь, иначе после листания в календаре плитка
        // показала бы тот месяц, на котором календарь закрыли.
        .onAppear { planner.open() }
    }

    private func cell(_ day: CalendarMonth.Day) -> some View {
        let isToday = planner.isToday(day.date)
        let marked = planner.hasEvents(day.date)
        return Text("\(day.number)")
            .font(.system(size: NotchStyle.font(9.5), weight: isToday || marked ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(
                !day.isInMonth ? 0.2 : (isToday || marked ? NotchStyle.primaryOpacity : 0.5)
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Circle()
                    .fill(Palette.calendar.opacity(isToday ? 0.55 : 0))
                    .frame(width: 16, height: 16)
            )
    }

    /// «Сентябрь» — месяц отдельно, без числа и в именительном падеже.
    static func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter.string(from: date).capitalizedFirst
    }
}

// MARK: - Задачи

struct TasksWidget: View {
    let widget: HomeWidget
    @ObservedObject var things: ThingsService
    let actions: HomeActions

    var body: some View {
        let tasks = things.todayTitles
        let capacity = HomeListRow.capacity(widget.size)
        let shown = Array(tasks.prefix(capacity))
        HomeTile(widget: widget, onTap: actions.openTasks, hint: t("Открыть в Things")) {
            VStack(alignment: .leading, spacing: 4) {
                HomeCaption(
                    kind: widget.kind,
                    trailing: tasks.count > shown.count ? "+\(tasks.count - shown.count)" : nil
                )
                if tasks.isEmpty {
                    HomeEmpty(text: t("Задач на сегодня нет"))
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, task in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.system(size: NotchStyle.font(8), weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                HomeListRow(text: task)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Вопрос к ИИ

/// Плитка, похожая на поле ввода.
///
/// Набирать прямо в ней нельзя, и это не упрощение: вырез фокуса не отбирает,
/// пока его не попросят, — на этом держится «выделил, спросил, вставил
/// обратно». Нажатие открывает разговор с фокусом в настоящем поле.
struct AskWidget: View {
    let widget: HomeWidget
    @ObservedObject var settings: Settings
    let actions: HomeActions

    var body: some View {
        HomeTile(widget: widget, onTap: actions.ask, hint: t("Команды")) {
            if widget.size == .small { compact } else { field }
        }
    }

    /// Плитки шире клетки: полоса, похожая на поле набора.
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: NotchStyle.font(12), weight: .semibold))
                .foregroundStyle(widget.kind.tint)
            Text(settings.ollamaEnabled ? t("Спросить…") : t("Команды и заметки…"))
                .font(.system(size: NotchStyle.font(12.5)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let dictate {
                HomeTileButton(symbol: "mic.fill", hint: t("Надиктовать вопрос"), action: dictate)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
    }

    /// Плитка 1×1: кнопка диктовки и название.
    ///
    /// Без рамки поля и без «Спросить…»: в клетку они встали бы обрезанным
    /// обещанием набора, которого здесь всё равно нет. Остаётся то, за чем
    /// к плитке тянутся, — голос под пальцем; нажатие мимо кнопки открывает
    /// команды, как и у плиток пошире.
    private var compact: some View {
        VStack(spacing: 3) {
            if let dictate {
                HomeTileButton(symbol: "mic.fill", hint: t("Надиктовать вопрос"), action: dictate)
            } else {
                // Голос выключен — на месте кнопки значок функции: иначе
                // плитка осталась бы пустой клеткой с одной подписью.
                Image(systemName: widget.kind.symbol)
                    .font(.system(size: NotchStyle.font(16), weight: .medium))
                    .foregroundStyle(widget.kind.tint)
                    .frame(height: NotchStyle.scaled(26))
            }
            Text(widget.kind.title)
                .font(.system(size: NotchStyle.font(10.5), weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Надиктовать вопрос: открыть команды и сразу начать запись.
    ///
    /// Пусто, когда голос выключен: кнопка, которая ответит «включите
    /// в настройках», в плитке 1×1 была бы единственной.
    private var dictate: (() -> Void)? {
        guard settings.voiceEnabled, let ask = actions.ask else { return nil }
        return {
            ask()
            actions.dictateQuestion()
        }
    }
}
