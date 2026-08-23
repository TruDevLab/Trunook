import SwiftUI
import TrunookXPC

/// Мини-представление: то, что видно при наведении, до нажатия.
///
/// Намеренно повторяет раскладку плашки события — обложка и одна строка.
/// Наведение и всплывающее уведомление показывают одно и то же по сути,
/// и разная вёрстка для них выглядела бы как сбой, а не как замысел.
struct PreviewPanel: View {
    let track: NowPlaying?
    /// Ближайшая встреча — ею мини-вид занят, когда музыки нет.
    let event: CalendarItem?
    let metrics: NotchMetrics
    /// Точка отсчёта бегущей строки — момент наведения.
    let startDate: Date
    let onTogglePlayback: () -> Void

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

    static func layout(track: NowPlaying?, event: CalendarItem?, metrics: NotchMetrics) -> ActivityLayout {
        ActivityLayout(
            text: text(track: track, event: event),
            trailing: nil,
            minimumWidth: metrics.closed.width
        )
    }

    private var layout: ActivityLayout { Self.layout(track: track, event: event, metrics: metrics) }
    private var showsTrack: Bool { Self.hasTrack(track) }

    var body: some View {
        HStack(spacing: ActivityLayout.spacing) {
            leading
                .frame(width: ActivityLayout.iconSize, height: ActivityLayout.iconSize)

            MarqueeText(
                text: Self.text(track: track, event: event),
                font: ActivityLayout.textFont,
                availableWidth: layout.textWidth,
                startDate: startDate
            )
        }
        .padding(.leading, ActivityLayout.leadingPadding)
        .padding(.trailing, ActivityLayout.trailingPadding)
        .padding(.top, metrics.notchHeight + 6)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    /// Слева либо обложка-кнопка, либо значок встречи: нажимать в строке
    /// со встречей нечего, а кнопка воспроизведения там сбивала бы с толку.
    @ViewBuilder
    private var leading: some View {
        if showsTrack {
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

    @ViewBuilder
    private var artwork: some View {
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

    var body: some View {
        Image(systemName: direction == .next ? "forward.fill" : "backward.fill")
            .font(.system(size: NotchStyle.font(14), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: NotchSizing.swipeExtension)
            // Плашки под чёлкой здесь быть не может: указатель живёт
            // во время жеста двумя пальцами, а не по наведению — показывать
            // подпись некому и некогда. Имя всё равно нужно: значок
            // сообщает, куда переключится трек, если довести палец.
            .accessibilityLabel(direction == .next ? t("Следующий трек") : t("Предыдущий трек"))
    }
}
