import SwiftUI
import TrunookXPC

final class NotchState: ObservableObject {
    @Published var isHovered = false
    /// Нажатие фиксирует панель раскрытой, пока курсор не ушёл.
    @Published var isPinnedOpen = false
    @Published var swipe: SwipeDirection?
    /// Свайп идёт прямо сейчас: куда ведут пальцы и насколько далеко увели,
    /// от нуля до единицы. Значок перелистывания проявляется по этой доле,
    /// а сам трек переключается только когда она дошла до единицы.
    @Published var pendingSwipe: SwipeDirection?
    @Published var swipeProgress: Double = 0
    /// Момент наведения — точка отсчёта для бегущей строки в мини-виде.
    @Published var hoverStartedAt = Date()
    /// Встреча, до которой показывается обратный отсчёт. Решение о том,
    /// показывать ли его, принимает контроллер — вёрстка только рисует.
    @Published var chipItem: CalendarItem?
    /// Что вызвано поверх выреза клавишей. Одновременно — только одно:
    /// меню команд и история буфера занимают одно и то же место.
    @Published var overlay: Overlay?

    enum Overlay: Equatable, CaseIterable {
        case commands
        case clipboard
        case assistant
        case shelf
        case hub
    }

    var isCommandsOpen: Bool { overlay == .commands }
    var isClipboardOpen: Bool { overlay == .clipboard }
    var isAssistantOpen: Bool { overlay == .assistant }
    var isShelfOpen: Bool { overlay == .shelf }
    var isHubOpen: Bool { overlay == .hub }

    /// Файлы ведут над зоной приёма прямо сейчас. Держится отдельно
    /// от `overlay`: полка бывает открыта и без перетаскивания, а подсветка
    /// нужна только пока над ней что-то держат.
    @Published var isShelfDropTarget = false

    /// С полки тащат файл наружу. Пока это так, накладку закрывать нельзя:
    /// вытащить файл — это и значит увести курсор за её границы.
    @Published var isDraggingOut = false

    /// Чёлку гладят — она мурчит и подрагивает.
    @Published var isPurring = false

    /// Смещение острова при мурчании.
    ///
    /// Считается таймером в контроллере, а не `TimelineView` в самой вёрстке.
    /// Ветвление «мурчит — не мурчит» внутри тела вида меняло его тождество,
    /// и в момент, когда курсор уходил, SwiftUI пересобирал поддерево вместо
    /// того чтобы доиграть схлопывание: остров будто отрывался от кромки.
    /// Смещение, которое всегда на месте и просто равно нулю, тождества
    /// не трогает.
    @Published var tremble: CGSize = .zero
}

struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var activities: ActivityCenter
    @ObservedObject var music: MusicClient
    @ObservedObject var calendar: CalendarService
    @ObservedObject var things: ThingsService
    @ObservedObject var meeting: MeetingService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var assistant: AssistantSession
    @ObservedObject var weather: WeatherService
    @ObservedObject var shelf: ShelfStore
    /// Настройки наблюдаются, а не передаются снимком: слоты команд правятся
    /// в окне настроек, и без наблюдения вырез показывал бы набор, каким тот
    /// был на момент запуска.
    @ObservedObject var settings: Settings

    let metrics: NotchMetrics
    let onTap: () -> Void
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void
    let onRunCommand: (QuickCommand) -> Void
    let onCopyLink: (URL) -> Void
    let onOpenItem: (CalendarItem) -> Void
    let onOpenCommands: () -> Void
    let onCloseCommands: () -> Void
    let onOpenClipboard: () -> Void
    let onUseClipboard: (ClipboardEntry) -> Void
    let onDeleteClipboard: (ClipboardEntry) -> Void
    let onClearClipboard: () -> Void
    let onCopyAnswer: () -> Void
    let onPasteAnswer: () -> Void
    let onComposeFollowUp: () -> Void
    let onSendFollowUp: (String) -> Void
    let onCloseAssistant: () -> Void
    let onRemoveFromShelf: (ShelfItem) -> Void
    let onOpenShelfItem: (ShelfItem) -> Void
    let onRevealShelfItem: (ShelfItem) -> Void
    let onClearShelf: () -> Void
    let onBeginShelfDragOut: () -> Void
    let onEndShelfDragOut: () -> Void
    let onOpenShelf: () -> Void
    let onDismissActivity: () -> Void
    let onOpenHub: () -> Void
    let onOpenExpanded: () -> Void
    let onAskAssistant: () -> Void

    private var commands: [QuickCommand] { settings.quickCommands }

    private var nextEvent: CalendarItem? { calendar.upcoming.first }

    /// Плитки меню всех функций: состав задаёт `HubEntry`, здесь к нему
    /// добавляются только действия. Раньше состав жил здесь, а его длина —
    /// отдельной константой в контроллере, и они разошлись бы при первой
    /// же правке.
    private var hubItems: [HubPanel.Item] {
        HubEntry.allCases.map { entry in
            HubPanel.Item(
                id: entry.id,
                title: entry.title,
                symbol: entry.symbol,
                tint: entry.tint,
                isEnabled: entry.isEnabled(settings),
                hint: entry.hint(settings),
                action: { run(entry) }
            )
        }
    }

    private func run(_ entry: HubEntry) {
        switch entry {
        case .expanded: onOpenExpanded()
        case .commands: onOpenCommands()
        case .clipboard: onOpenClipboard()
        case .shelf: onOpenShelf()
        }
    }

    private var snapshot: NotchSnapshot {
        NotchInputs(
            overlay: state.overlay,
            swipe: state.swipe,
            pendingSwipe: state.pendingSwipe,
            swipeProgress: state.swipeProgress,
            isHovered: state.isHovered,
            isPinnedOpen: state.isPinnedOpen,
            chip: state.chipItem,
            activity: activities.current,
            track: music.nowPlaying,
            event: nextEvent,
            taskCount: things.todayTitles.count,
            meetingActions: meeting.availableActions.count,
            clipboardRows: clipboard.entries.count,
            assistantAnswer: assistant.answer,
            assistantIsStreaming: assistant.isStreaming,
            shelfCount: shelf.items.count,
            hubCount: HubEntry.count
        ).resolve()
    }

    private var content: NotchContent { snapshot.content }
    private var presentation: NotchPresentation { snapshot.presentation }

    private var size: CGSize { snapshot.size(metrics: metrics) }

    private var isOpen: Bool { presentation != .collapsed }

    /// Полоса воспроизведения нужна там, где виден сам трек.
    private var showsProgress: Bool {
        presentation == .preview || presentation == .expanded
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isOpen ? NotchStyle.shoulderInset : 8,
            bottomRadius: {
                switch presentation {
                case .expanded, .commands, .clipboard, .assistant, .shelf, .hub: return 22
                case .preview, .activity: return 20
                case .swiping: return 14
                case .chip, .collapsed: return 12
                }
            }()
        )
    }

    /// Форма ведёт, содержимое догоняет. При закрытии наоборот: сначала
    /// гаснет содержимое, потом схлопывается форма.
    private var shapeAnimation: Animation { .spring(response: 0.28, dampingFraction: 0.82) }
    private var contentAnimation: Animation {
        .easeOut(duration: 0.14).delay(isOpen ? 0.10 : 0)
    }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(.black)

            // Внутри ZStack, а не поверх: обрезка формой съедает внешнюю
            // половину обводки и оставляет ровную линию по краю острова.
            if showsProgress {
                NotchProgressRing(track: music.nowPlaying, shape: shape)
            }

            panel
                .opacity(isOpen ? 1 : 0)
                .animation(contentAnimation, value: presentation)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: swipeAlignment) {
            // Значок проявляется вместе с движением пальцев, а не вспыхивает
            // по факту переключения: так видно, что жест засчитывается,
            // и насколько ещё вести.
            if presentation == .swiping, let direction = effectiveSwipe {
                SwipeIndicator(direction: direction)
                    // Вогнутый уголок формы съедает крайние точки, поэтому
                    // отступаем на его радиус — иначе значок обрезается.
                    .padding(direction == .previous ? .leading : .trailing, 12)
                    .opacity(swipeVisibility)
                    // Подъезжает из-за края: одна лишь прозрачность читается
                    // как мигание, а смещение — как движение.
                    .offset(x: swipeSlide(direction))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.swipeProgress)
        // Обрезаем по той же форме: пока чёлка не раскрылась, содержимое
        // физически не может вылезти за её края.
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        // Дрожь поверх обрезки: трясётся весь остров целиком, а не его
        // содержимое внутри неподвижной формы.
        .offset(x: state.tremble.width, y: state.tremble.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(shapeAnimation, value: presentation)
        .animation(.easeOut(duration: 0.12), value: state.swipe)
    }

    /// Куда указывает значок: по свершившемуся переключению, а пока его нет —
    /// по направлению текущего жеста.
    private var effectiveSwipe: SwipeDirection? {
        state.swipe ?? (state.swipeProgress > 0.02 ? state.pendingSwipe : nil)
    }

    /// Свершившийся свайп показывается целиком, идущий — по своей доле,
    /// пересчитанной от порога раскрытия: к моменту, когда полоса открылась,
    /// значок уже должен начать проявляться, а не ждать своей очереди.
    private var swipeVisibility: Double {
        guard state.swipe == nil else { return 1 }
        let start = NotchInputs.swipingEnterProgress
        return min(1, max(0, (state.swipeProgress - start) / (1 - start)))
    }

    private func swipeSlide(_ direction: SwipeDirection) -> CGFloat {
        guard state.swipe == nil else { return 0 }
        let remaining = CGFloat(1 - min(1, state.swipeProgress))
        return (direction == .previous ? -1 : 1) * remaining * 10
    }

    private var swipeAlignment: Alignment {
        effectiveSwipe == .previous ? .leading : .trailing
    }

    /// Куда ведёт нажатие по плашке, по которой можно нажать.
    private func openInteractive(_ activity: Activity) {
        switch activity.kind {
        case .shelf: onOpenShelf()
        default: onOpenClipboard()
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch presentation {
        case .collapsed, .swiping:
            EmptyView()
        case .commands:
            CommandsPanel(
                commands: commands,
                metrics: metrics,
                onRun: onRunCommand,
                onOpenSettings: onOpenSettings,
                // Кнопка возврата нужна только когда панель была раскрыта
                // до перехода: вызванное клавишей меню закрывать некуда.
                onBack: state.isPinnedOpen ? onCloseCommands : nil
            )
        case .assistant:
            AssistantPanel(
                session: assistant,
                metrics: metrics,
                onCopy: onCopyAnswer,
                onPaste: onPasteAnswer,
                onCompose: onComposeFollowUp,
                onSend: onSendFollowUp,
                onClose: onCloseAssistant
            )
        case .clipboard:
            ClipboardPanel(
                entries: clipboard.entries,
                metrics: metrics,
                slotHint: settings.clipboardSlotModifiers.hint,
                onUse: onUseClipboard,
                onDelete: onDeleteClipboard,
                onClear: onClearClipboard,
                onOpenSettings: onOpenSettings
            )
        case .hub:
            HubPanel(
                metrics: metrics,
                items: hubItems,
                onOpenSettings: onOpenSettings
            )
        case .shelf:
            ShelfPanel(
                items: shelf.items,
                thumbnail: { shelf.thumbnails[$0.url] ?? shelf.icon(for: $0) },
                metrics: metrics,
                isDropTarget: state.isShelfDropTarget,
                onRemove: onRemoveFromShelf,
                onOpen: onOpenShelfItem,
                onRevealInFinder: onRevealShelfItem,
                onClear: onClearShelf,
                onBeginDragOut: onBeginShelfDragOut,
                onEndDragOut: onEndShelfDragOut
            )
        case .chip:
            if let chip = state.chipItem {
                ChipView(item: chip, metrics: metrics)
            }
        case .activity:
            if let activity = activities.current {
                let view = ActivityView(
                    activity: activity,
                    track: music.nowPlaying,
                    metrics: metrics,
                    onJoin: onJoin,
                    onDismiss: onDismissActivity,
                    onOpen: { openInteractive(activity) }
                )
                .frame(
                    width: ActivityView
                        .layout(for: activity.kind, track: music.nowPlaying, metrics: metrics)
                        .panelWidth
                )
                // Нажатие обрабатывает сама плашка: у неё есть ещё крестик,
                // а кнопка, вложенная в кнопку, нажатий не получает.
                view
            }
        case .preview where !meeting.availableActions.isEmpty:
            MeetingControlsView(meeting: meeting, metrics: metrics)

        case .preview:
            PreviewPanel(
                track: music.nowPlaying,
                event: nextEvent,
                metrics: metrics,
                startDate: state.hoverStartedAt,
                onTogglePlayback: { music.send(.togglePlayPause) }
            )
            .frame(width: PreviewPanel.layout(track: music.nowPlaying, event: nextEvent, metrics: metrics).panelWidth)
        case .expanded:
            ExpandedPanel(
                music: music,
                event: nextEvent,
                tasks: things.todayTitles,
                metrics: metrics,
                onOpenSettings: onOpenSettings,
                onJoin: onJoin,
                onOpenTasks: { ThingsService.openToday() },
                onCopyLink: onCopyLink,
                onOpenItem: onOpenItem,
                onOpenHub: onOpenHub,
                onAsk: settings.ollamaEnabled ? onAskAssistant : nil,
                weather: settings.weatherEnabled ? weather.current : nil
            )
            .frame(width: metrics.expanded(extraHeight: content.extraHeight).width, alignment: .leading)
        }
    }
}

/// Содержимое раскрытой панели: музыка и ближайшая встреча.
private struct ExpandedPanel: View {
    @ObservedObject var music: MusicClient
    let event: CalendarItem?
    let tasks: [String]
    let metrics: NotchMetrics
    let onOpenSettings: () -> Void
    let onJoin: (URL) -> Void
    let onOpenTasks: () -> Void
    let onCopyLink: (URL) -> Void
    let onOpenItem: (CalendarItem) -> Void
    let onOpenHub: () -> Void
    /// Спросить модель. nil — Ollama выключена в настройках, и кнопки нет:
    /// кнопка, которая ничего не делает, хуже её отсутствия.
    let onAsk: (() -> Void)?
    /// Погода живёт в полосе аппаратного выреза справа: там пусто, и панель
    /// от неё не растёт.
    let weather: WeatherService.Snapshot?

    var body: some View {
        NotchPanel(metrics: metrics, width: metrics.expanded(extraHeight: 0).width) {
            // Погода уехала из правого угла в левое крыло, освободив правое
            // под настройки: в строке музыки шестерёнка отнимала ширину
            // у названия трека.
            if let weather {
                WeatherCorner(snapshot: weather, notchHeight: metrics.notchHeight)
            }
        } trailing: {
            HStack(spacing: 2) {
                if let onAsk {
                    NotchPanelButton(symbol: "sparkles", action: onAsk)
                }
                NotchPanelButton(symbol: "gearshape", action: onOpenSettings)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                musicRow
                schedule
            }
            .foregroundStyle(.white)
        }
    }

    /// Встреча и задачи — двумя подложками, а не одной с линией внутри.
    ///
    /// Сначала их разделяли `Divider()`, потом волосяная линия внутри общей
    /// карточки — и то и другое читалось как полоса поперёк панели. Две
    /// отдельные подложки на чёрном разделяются сами: границу показывает
    /// зазор между ними, а не проведённая черта.
    @ViewBuilder
    private var schedule: some View {
        VStack(spacing: Self.cardGap) {
            if let event {
                card { eventRow(event) }
            }
            if !tasks.isEmpty {
                card { tasksList }
            }
        }
    }

    /// Зазор между подложками — он же единственный разделитель.
    static let cardGap: CGFloat = 6
    /// Отступ содержимого от края подложки. Он же задаёт вертикаль, по которой
    /// выравнивается обложка трека.
    static let cardInset: CGFloat = 12

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Self.cardInset)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Та же заливка, что у круглых кнопок панели: подложки и кнопки
            // лежат рядом, и разная плотность читалась как небрежность.
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(NotchButtonStyle.restingFill))
            )
    }

    private var musicRow: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(trackTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                // Пустая вторая строка не рисуется вовсе: без неё название
                // встаёт по центру обложки, а не липнет к её верху.
                if hasTrack, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            transport
            hubButton
        }
        // Тот же отступ, что у содержимого подложек ниже: без него обложка
        // стояла левее строки встречи, и левый край панели выглядел рваным.
        .padding(.horizontal, Self.cardInset)
    }

    /// Переход в меню всех функций — кнопкой, а не жестом.
    ///
    /// Горизонтальный свайп двумя пальцами в этом же состоянии уже занят
    /// переключением трека, а вертикальный — раскрытием панели; вешать на них
    /// третий смысл значило бы сделать все жесты ненадёжными: система
    /// не отличит намерение по одному движению.
    ///
    /// Раньше кнопка вела прямо в команды. Теперь функций больше, чем одна,
    /// и вести из панели в одну из них, минуя остальные, — произвол.
    private var hubButton: some View {
        button("square.grid.2x2.fill", action: onOpenHub)
            .padding(.leading, 6)
    }

    /// Играет ли что-нибудь на самом деле. MediaRemote в паузах между
    /// треками присылает запись с пустым названием — по одному только `nil`
    /// это не отличить.
    private var hasTrack: Bool {
        !(music.nowPlaying?.title ?? "").isEmpty
    }

    /// Название трека либо честное «ничего не играет».
    ///
    /// Проверяется не только `nil`: MediaRemote в паузах между треками
    /// присылает запись с пустым названием, и строка молча оставалась
    /// пустой — панель выглядела не «музыки нет», а «что-то не загрузилось».
    private var trackTitle: String {
        let title = music.nowPlaying?.title ?? ""
        return title.isEmpty ? t("Ничего не играет") : title
    }

    /// Исполнитель — и только он. Состояние связи с хелпером («подключён»)
    /// подписью под названием быть не должно: это слово для журнала, а не
    /// для человека, и под «ничего не играет» оно читается как ошибка.
    private var subtitle: String {
        music.nowPlaying?.artist ?? ""
    }

    /// Задачи получили собственные строки, а не подпись под треком: пока
    /// играла музыка, подпись была занята исполнителем, и включённая
    /// интеграция с Things не показывала ничего вовсе.
    private var tasksList: some View {
        Button(action: onOpenTasks) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visibleTasks.enumerated()), id: \.offset) { index, task in
                    taskRow(task, isLast: index == visibleTasks.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var visibleTasks: [String] {
        Array(tasks.prefix(NotchMetrics.maxVisibleTasks))
    }

    private func taskRow(_ task: String, isLast: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text(task)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer(minLength: 8)

            // Остаток списка показываем последней строкой, чтобы не отнимать
            // место у самих задач.
            if isLast, tasks.count > visibleTasks.count {
                Text("+\(tasks.count - visibleTasks.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize()
            }
        }
        .frame(height: NotchMetrics.taskRowHeight)
    }

    private func eventRow(_ event: CalendarItem) -> some View {
        HStack(spacing: 10) {
            // Нажатие на саму строку открывает запись в её приложении.
            // Кнопки ссылки справа живут отдельно: у них своё действие,
            // и попасть в них мимо строки должно быть можно.
            Button { onOpenItem(event) } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(event.color)
                        .frame(width: 7, height: 7)

                    // Название на своей строке, время под ним подписью.
                    // В одну строку они делили ширину с кнопкой встречи,
                    // и название обрезалось на третьем слове — притом что
                    // именно оно и отвечает на вопрос «что за встреча».
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(event.isAllDay ? event.timeLabel : "\(event.timeLabel) · \(event.countdown())")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                // Высота задана, а не выведена из содержимого: расчёт размера
                // панели опирается на неё, и «примерно столько» разъезжается
                // с нарисованным на пустую полосу внизу.
                .frame(height: NotchMetrics.eventRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(t("Открыть в Календаре"))

            if let link = event.link {
                Button { onCopyLink(link.url) } label: {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .buttonStyle(PressableStyle())
                .help(t("Скопировать ссылку"))

                Button { onJoin(link.url) } label: {
                    Label(link.provider.title, systemImage: link.provider.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
            }
        }
        .frame(height: NotchMetrics.eventRowHeight - 6)
    }

    private var artwork: some View {
        Group {
            if let data = music.nowPlaying?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.12))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.45))
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Только «играть»: перематывают свайпом двумя пальцами.
    ///
    /// Кнопки «назад» и «вперёд» убраны намеренно. Они занимали треть панели,
    /// повторяя жест, который и так работает, — а место нужнее названию трека:
    /// оно обрезалось на третьем слове.
    private var transport: some View {
        button(music.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill") {
            music.send(.togglePlayPause)
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        // Отклик на нажатие и вибрация живут в стиле, а не здесь.
        .buttonStyle(NotchButtonStyle())
    }
}
