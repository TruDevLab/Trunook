import SwiftUI
import TrunookXPC

/// Что может стоять в мини-виде при наведении.
///
/// Активных событий бывает несколько разом — играет музыка, горит чашка,
/// скоро встреча. Мини-вид показывает одно, остальные — миниатюрами
/// в крыльях у чёлки (первое справа, второе слева); нажатие по миниатюре
/// переключает. Каждое новое наведение начинает с первого.
enum PreviewItem: Equatable {
    case music
    case caffeine
    case meeting

    /// Сколько вперёд встреча или напоминание считается «скорым» и встаёт
    /// в мини-виде раньше молчащей музыки.
    static let soonWindow: TimeInterval = 60 * 60

    /// Встреча, напоминание или задача начнётся в ближайший час или идёт
    /// сейчас. Событие на весь день скорым не бывает: оно «сейчас» весь день.
    static func isSoon(_ item: CalendarItem?, now: Date = Date()) -> Bool {
        guard let item, !item.isAllDay else { return false }
        return item.start.timeIntervalSince(now) <= soonWindow && (item.end ?? item.start) >= now
    }

    /// Какую встречу показать: первую скорую, иначе просто ближайшую.
    /// Не `events.first`: событие на весь день заслоняло бы созвон через
    /// двадцать минут, и мини-вид решил бы, что скорых нет.
    static func featured(_ events: [CalendarItem], now: Date = Date()) -> CalendarItem? {
        events.first { isSoon($0, now: now) } ?? events.first
    }

    /// Активные события по порядку важности: играющая музыка, чашка (она
    /// идёт прямо сейчас), скорая встреча, молчащая музыка, встреча позже.
    ///
    /// Молчащая музыка (`musicIdle` — функция включена, но ничего
    /// не играет) — строка «Ничего не играет», нажатие по ней запускает
    /// плеер. Она встаёт первой, когда в ближайший час ничего нет: встреча
    /// вечером в мини-виде по наведению бесполезна, а включить музыку —
    /// то, ради чего наводят чаще (просьба пользователя).
    static func items(track: NowPlaying?, event: CalendarItem?, caffeine: CaffeineChip?,
                      musicIdle: Bool = false, now: Date = Date()) -> [PreviewItem] {
        var items: [PreviewItem] = []
        let playing = PreviewPanel.hasTrack(track)
        let soon = isSoon(event, now: now)
        if playing { items.append(.music) }
        if caffeine != nil { items.append(.caffeine) }
        if event != nil, soon { items.append(.meeting) }
        if !playing, musicIdle { items.append(.music) }
        if event != nil, !soon { items.append(.meeting) }
        return items
    }

    /// Что на виду: выбранное, если оно ещё активно, иначе первое.
    static func shown(in items: [PreviewItem], selection: PreviewItem?) -> PreviewItem? {
        if let selection, items.contains(selection) { return selection }
        return items.first
    }

    /// Миниатюры в крыльях — все, кроме показанного, не больше двух.
    static func alternates(in items: [PreviewItem], shown: PreviewItem?) -> [PreviewItem] {
        Array(items.filter { $0 != shown }.prefix(2))
    }
}

/// Мини-представление: то, что видно при наведении, до нажатия.
///
/// Намеренно повторяет раскладку плашки события — значок и одна строка.
/// Наведение и всплывающее уведомление показывают одно и то же по сути,
/// и разная вёрстка для них выглядела бы как сбой, а не как замысел.
struct PreviewPanel: View {
    let track: NowPlaying?
    /// Ближайшая встреча.
    let event: CalendarItem?
    /// Чашка горит — с ней удержание экрана.
    var caffeine: CaffeineChip? = nil
    /// До какого времени держится экран — подпись чашки.
    var caffeineEndsAt: Date? = nil
    /// Что выбрали миниатюрой в крыле. `nil` — первое по важности.
    var selection: PreviewItem? = nil
    let metrics: NotchMetrics
    /// Точка отсчёта бегущей строки — момент наведения.
    let startDate: Date
    let onTogglePlayback: () -> Void
    /// Перемотать трек на столько секунд — назад со знаком минус.
    let onSkip: (Double) -> Void
    /// Подключиться к встрече по её ссылке.
    let onJoin: (URL) -> Void
    /// Нажали миниатюру в крыле — показать это событие.
    var onSelect: (PreviewItem) -> Void = { _ in }
    /// Нажали строку чашки — панель бодрости.
    var onOpenCaffeine: () -> Void = {}
    /// Музыка включена в настройках: при тишине в мини-виде строка
    /// «Ничего не играет», которая запускает плеер.
    var musicIdle = false
    /// Мини-вид показан — миниатюры выпрыгивают из-под чёлки следом за строкой.
    var wingsShown = true
    /// Имя плеера из настроек — для подсказки строки «Ничего не играет».
    var playerName: String? = nil
    /// Нажали строку «Ничего не играет» — запустить плеер и включить музыку.
    var onStartPlayer: () -> Void = {}

    /// Сторона миниатюры в крыле.
    static var alternateSize: CGFloat { ActivityLayout.iconSize - 2 }

    /// Есть ли что показывать про музыку.
    ///
    /// Нужны и исполнитель, и название: MediaRemote отдаёт сведения порциями
    /// и в паузах между треками присылает огрызки — одно название без
    /// исполнителя или пустоту. Показывать ради них «ничего не играет»
    /// в единственной строке мини-вида расточительно: там полезнее встреча.
    static func hasTrack(_ track: NowPlaying?) -> Bool {
        guard let track, !track.isEmpty else { return false }
        let title = track.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty && !artist.isEmpty
    }

    static func text(track: NowPlaying?, event: CalendarItem? = nil) -> String {
        if hasTrack(track), let track {
            return "\(track.artist ?? "") — \(track.title ?? "")"
        }
        if let event {
            return "\(event.timeLabel) · \(event.title)"
        }
        return t("Ближайших встреч нет")
    }

    /// Строка чашки: «Экран не гаснет · до 14:35» или «без срока».
    static func caffeineText(endsAt: Date?) -> String {
        guard let endsAt else { return t("Экран не гаснет · без срока") }
        let formatter = DateFormatter()
        formatter.locale = Settings.shared.language.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return tf("Экран не гаснет · до %@", formatter.string(from: endsAt))
    }

    /// Текст строки для показанного события.
    static func text(
        for item: PreviewItem?, track: NowPlaying?, event: CalendarItem?, caffeineEndsAt: Date?
    ) -> String {
        switch item {
        case .music: return hasTrack(track) ? text(track: track) : t("Ничего не играет")
        case .caffeine: return caffeineText(endsAt: caffeineEndsAt)
        case .meeting: return text(track: nil, event: event)
        case nil: return text(track: nil, event: nil)
        }
    }

    /// Ссылка на видеозвонок, если строка сейчас про встречу и ссылка у неё есть.
    ///
    /// Та же кнопка, что у плашки в момент начала встречи: навёл на чёлку,
    /// увидел, что созвон через минуту, — и подключаешься оттуда же, а не
    /// ждёшь, пока всплывёт плашка, и не ищешь ссылку в календаре. Одной
    /// функцией на расчёт ширины и на вёрстку — по тому же правилу, что
    /// `ActivityView.button(for:)`: две проверки однажды разошлись бы.
    static func joinLink(track: NowPlaying?, event: CalendarItem?) -> URL? {
        guard !hasTrack(track) else { return nil }
        return event?.link?.url
    }

    /// Раскладка одной строки — для показанного события.
    private static func rowLayout(
        _ item: PreviewItem?, track: NowPlaying?, event: CalendarItem?, caffeineEndsAt: Date?,
        minimumWidth: CGFloat
    ) -> ActivityLayout {
        let join = item == .meeting && event?.link != nil
        return ActivityLayout(
            text: text(for: item, track: track, event: event, caffeineEndsAt: caffeineEndsAt),
            trailing: nil,
            minimumWidth: minimumWidth,
            trailingExtra: (item == .music && hasTrack(track) ? skipRoom : 0)
                + (join ? ActivityLayout.spacing + ActivityView.answerDiameter : 0)
        )
    }

    /// Ширина мини-вида.
    ///
    /// Когда событий несколько, ширина — **одна на все**: самая широкая
    /// из строк. Иначе переключение меняло бы ширину, миниатюра в крыле
    /// уезжала бы из-под курсора, и курсор, оказавшийся за краем, сворачивал
    /// мини-вид — нажатие «ничего не переключало и закрывало» (поймал
    /// пользователь). И не уже, чем нужно крыльям под миниатюры.
    static func layout(
        track: NowPlaying?,
        event: CalendarItem?,
        caffeine: CaffeineChip? = nil,
        caffeineEndsAt: Date? = nil,
        selection: PreviewItem? = nil,
        musicIdle: Bool = false,
        metrics: NotchMetrics
    ) -> ActivityLayout {
        let items = PreviewItem.items(track: track, event: event, caffeine: caffeine, musicIdle: musicIdle)
        let shown = PreviewItem.shown(in: items, selection: selection)
        guard items.count > 1 else {
            return rowLayout(shown, track: track, event: event, caffeineEndsAt: caffeineEndsAt,
                             minimumWidth: metrics.closed.width)
        }
        let wings = metrics.notchWidth
            + 2 * (alternateSize + wingInset + NotchStyle.shoulderInset + 4)
            - ActivityLayout.overhangBeyondNotch
        let floor = max(metrics.closed.width, wings)
        let widest = items.map {
            rowLayout($0, track: track, event: event, caffeineEndsAt: caffeineEndsAt, minimumWidth: floor).panelWidth
        }.max() ?? 0
        return rowLayout(shown, track: track, event: event, caffeineEndsAt: caffeineEndsAt,
                         minimumWidth: max(floor, widest - ActivityLayout.overhangBeyondNotch))
    }

    /// Отступ миниатюры от края панели.
    static let wingInset: CGFloat = 10

    /// Шаг перемотки.
    static let skipStep: Double = 10

    /// Место под две кнопки перемотки — тем же расчётом, что у кнопок
    /// ответа в плашках: одной мерой и для ширины, и для вёрстки.
    static var skipRoom: CGFloat {
        ActivityLayout.spacing + 2 * ActivityView.answerDiameter + ActivityView.answerSpacing
    }

    private var items: [PreviewItem] {
        PreviewItem.items(track: track, event: event, caffeine: caffeine, musicIdle: musicIdle)
    }
    private var shown: PreviewItem? { PreviewItem.shown(in: items, selection: selection) }
    private var alternates: [PreviewItem] { PreviewItem.alternates(in: items, shown: shown) }

    private var layout: ActivityLayout {
        Self.layout(track: track, event: event, caffeine: caffeine, caffeineEndsAt: caffeineEndsAt,
                    selection: selection, musicIdle: musicIdle, metrics: metrics)
    }

    var body: some View {
        row
            .padding(.leading, ActivityLayout.leadingPadding)
            .padding(.trailing, ActivityLayout.trailingPadding)
            .padding(.top, metrics.notchHeight + 6)
            .padding(.bottom, 12)
            .foregroundStyle(.white)
            // Остальные события — выше строки, в крыльях у самой чёлки:
            // там пусто в любом случае, и строка остаётся строкой одного
            // события, а не перечнем.
            .overlay(alignment: .topTrailing) {
                if let first = alternates.first {
                    wingThumb(first).notchCascade(4, shown: wingsShown, scale: 0.4, lift: -8, pop: true)
                }
            }
            .overlay(alignment: .topLeading) {
                if alternates.count > 1 {
                    wingThumb(alternates[1]).notchCascade(6, shown: wingsShown, scale: 0.4, lift: -8, pop: true)
                }
            }
    }

    @ViewBuilder
    private var row: some View {
        switch shown {
        case .caffeine:
            // Вся строка — кнопка: чашку открывают ради срока, как и полоску
            // с отсчётом в свёрнутой чёлке.
            Button(action: onOpenCaffeine) {
                HStack(spacing: ActivityLayout.spacing) {
                    caffeineIcon(size: ActivityLayout.iconSize)
                    MarqueeText(
                        text: Self.caffeineText(endsAt: caffeineEndsAt),
                        font: ActivityLayout.textFont,
                        availableWidth: layout.textWidth,
                        startDate: startDate
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Бодрость"))
        case .music where !Self.hasTrack(track):
            // Тишина: вся строка — кнопка, как у чашки. Перематывать нечего,
            // а нажимают сюда ради одного — включить музыку.
            Button(action: onStartPlayer) {
                HStack(spacing: ActivityLayout.spacing) {
                    // Своя подложка, а не заглушка обложки: у той в середине
                    // нота, и «играть» поверх неё сливалось в кашу.
                    RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .overlay(Image(systemName: "play.fill")
                            .font(.system(size: NotchStyle.font(11), weight: .bold))
                            .foregroundStyle(.white))
                        .frame(width: ActivityLayout.iconSize, height: ActivityLayout.iconSize)
                    MarqueeText(
                        text: t("Ничего не играет"),
                        font: ActivityLayout.textFont,
                        availableWidth: layout.textWidth,
                        startDate: startDate
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(tf("Включить музыку в %@", playerName ?? t("Музыка")))
        default:
            let line = Self.text(for: shown, track: track, event: event, caffeineEndsAt: caffeineEndsAt)
            HStack(spacing: ActivityLayout.spacing) {
                // Новый трек или другая встреча — обложка и строка перетекают,
                // а не подменяются (`NotchMotion.Swap`).
                leading
                    .frame(width: ActivityLayout.iconSize, height: ActivityLayout.iconSize)
                    // Трек — переворот карточкой, встреча — перетекание.
                    .notchFlip(shown == .music ? (track?.title ?? "") : "")
                    .notchSwap(shown == .music ? "" : line, alignment: .center)

                MarqueeText(
                    text: line,
                    font: ActivityLayout.textFont,
                    availableWidth: layout.textWidth,
                    startDate: startDate
                )
                .notchSwap(line)

                if shown == .meeting, let link = event?.link?.url {
                    MeetingJoinButton(url: link, provider: event?.link?.provider.title, action: onJoin)
                }

                if shown == .music, Self.hasTrack(track) {
                    HStack(spacing: ActivityView.answerSpacing) {
                        skipButton(symbol: "gobackward.10", hint: t("Назад на 10 секунд"), delta: -Self.skipStep)
                        skipButton(symbol: "goforward.10", hint: t("Вперёд на 10 секунд"), delta: Self.skipStep)
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// Миниатюра события в крыле: обложка, чашка или значок встречи.
    private func wingThumb(_ item: PreviewItem) -> some View {
        let side = Self.alternateSize
        let shape = RoundedRectangle(cornerRadius: NotchStyle.artRadius - 1, style: .continuous)
        return Button { onSelect(item) } label: {
            Group {
                switch item {
                case .music: artwork
                case .caffeine: caffeineIcon(size: side)
                case .meeting:
                    shape.fill((event?.color ?? .white).opacity(0.22))
                        .overlay(
                            Image(systemName: event?.symbol ?? "calendar")
                                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                                .foregroundStyle(event?.color ?? .white)
                        )
                }
            }
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint(for: item))
        .padding(.top, max(2, (metrics.notchHeight - side) / 2))
        .padding(.horizontal, NotchStyle.shoulderInset + Self.wingInset)
    }

    private func hint(for item: PreviewItem) -> String {
        switch item {
        case .music: return t("Показать музыку")
        case .caffeine: return t("Показать бодрость")
        case .meeting: return event.map { tf("Показать: %@", $0.title) } ?? t("Показать встречу")
        }
    }

    private func caffeineIcon(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
            .fill(Palette.caffeine.opacity(0.22))
            .overlay(
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: NotchStyle.font(size > 22 ? 11 : 9.5), weight: .semibold))
                    .foregroundStyle(Palette.caffeine)
            )
            .frame(width: size, height: size)
    }

    /// Слева либо обложка-кнопка, либо значок встречи: нажимать в строке
    /// со встречей нечего, а кнопка воспроизведения там сбивала бы с толку.
    @ViewBuilder
    private var leading: some View {
        if shown == .music {
            artworkButton
        } else {
            RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay(
                    Image(systemName: event?.symbol ?? "calendar")
                        .font(.system(size: NotchStyle.font(12), weight: .medium))
                        .foregroundStyle(event?.color ?? .white.opacity(0.5))
                )
        }
    }

    /// Круглая кнопка перемотки — как кнопки ответа в плашках.
    private func skipButton(symbol: String, hint: String, delta: Double) -> some View {
        Button { onSkip(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .bold))
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .frame(width: ActivityView.answerDiameter, height: ActivityView.answerDiameter)
                .background(Circle().fill(.white.opacity(0.14)))
        }
        .buttonStyle(NotchButtonStyle(diameter: ActivityView.answerDiameter))
        .notchHint(hint)
    }

    /// Обложка работает кнопкой воспроизведения.
    ///
    /// Значок показан всегда, а не по наведению на саму обложку: мини-вид
    /// и так существует только пока курсор над островом, так что «всегда»
    /// здесь и означает «при наведении». Заодно не нужно хранить состояние
    /// наведения, недоступное без `@State`.
    private var artworkButton: some View {
        Button(action: onTogglePlayback) {
            artwork
                .overlay {
                    ZStack {
                        Color.black.opacity(0.4)
                        Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                            .font(.system(size: NotchStyle.font(10), weight: .bold))
                            .symbolSwap(track?.isPlaying == true)
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        // Обложка — картинка, своего текста у неё нет: без имени диктор
        // объявлял бы её просто «кнопкой». Подпись меняется вместе
        // со значком, как и у кнопки воспроизведения в раскрытой панели.
        .notchHint(track?.isPlaying == true ? t("Пауза") : t("Играть"))
    }


    private var artwork: some View {
        // Обложка приходит позже названия — проявляется, а не подменяет.
        artworkImage
            .animation(NotchMotion.timed(.easeOut(duration: 0.28)), value: track?.artwork?.count)
    }

    @ViewBuilder
    private var artworkImage: some View {
        if let data = track?.artwork, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                .fill(.white.opacity(0.12))
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: NotchStyle.font(12), weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}

/// Значок направления, всплывающий при свайпе двумя пальцами.
///
/// Без подложки: он показывается в расширении острова, где под ним пусто,
/// и кружок вокруг выглядел бы лишней деталью.
struct SwipeIndicator: View {
    let direction: SwipeDirection
    /// Трек уже переключён — значок «щёлкает»: рывок в сторону перелистывания
    /// с отскоком и встряска стрелок. Видно, что жест засчитан.
    var committed = false

    var body: some View {
        let sign: Double = direction == .next ? 1 : -1
        Image(systemName: direction == .next ? "forward.fill" : "backward.fill")
            .font(.system(size: NotchStyle.font(14), weight: .semibold))
            .foregroundStyle(.white)
            .symbolSwap(direction == .next)
            .symbolEffect(.bounce.byLayer, options: .speed(1 / NotchMotion.slowdown),
                          value: NotchMotion.reduced ? false : committed)
            .keyframeAnimator(initialValue: 0.0, trigger: NotchMotion.reduced ? false : committed) { view, x in
                view.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(committed ? 9 * sign : 0, duration: 0.09 * NotchMotion.slowdown, spring: .snappy)
                    SpringKeyframe(0, duration: 0.4 * NotchMotion.slowdown, spring: .bouncy)
                }
            }
            .frame(width: NotchSizing.swipeExtension)
            // Плашки под чёлкой здесь быть не может: указатель живёт
            // во время жеста двумя пальцами, а не по наведению — показывать
            // подпись некому и некогда. Имя всё равно нужно: значок
            // сообщает, куда переключится трек, если довести палец.
            .accessibilityLabel(direction == .next ? t("Следующий трек") : t("Предыдущий трек"))
    }
}
