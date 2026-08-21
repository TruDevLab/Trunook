import SwiftUI
import AppKit
import TrunookXPC

/// Размеры плашки события.
///
/// Ширина считается по фактической ширине текста ещё до вёрстки: короткое
/// событие получает компактную плашку, длинное упирается в потолок и включает
/// бегущую строку. Раскладка по бокам от чёлки, которая была здесь раньше,
/// этого не позволяла — содержимое переменной ширины из неё вылезало.
struct ActivityLayout {
    /// Слева отступ больше: обложка вплотную к скруглению выглядит зажатой.
    static let leadingPadding: CGFloat = 20
    static let trailingPadding: CGFloat = 14
    static let spacing: CGFloat = 8
    static let iconSize: CGFloat = 24
    static let maxWidth: CGFloat = 360
    /// Насколько плашка должна выступать за края свёрнутой формы, чтобы
    /// читаться как раскрытие, а не как случайный обрубок.
    static let overhangBeyondNotch: CGFloat = 32

    static let textFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let trailingFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    /// Ширина всей плашки.
    let panelWidth: CGFloat
    /// Сколько остаётся тексту после значка и числа справа.
    let textWidth: CGFloat

    /// - Parameters:
    ///   - minimumWidth: ширина свёрнутой формы. Плашка не имеет права стать
    ///     уже неё — иначе остров получается меньше самого выреза.
    ///   - trailingIsButton: у кнопки есть собственные поля, и без запаса
    ///     её подпись обрезалась бы.
    ///   - trailingExtra: место под значок справа от значения — например,
    ///     под крестик, которым убирают плашку полки.
    init(
        text: String,
        trailing: String?,
        minimumWidth: CGFloat,
        trailingIsButton: Bool = false,
        trailingExtra: CGFloat = 0
    ) {
        let trailingWidth = trailing.map {
            TextMeasure.width($0, font: Self.trailingFont)
                + Self.spacing
                + (trailingIsButton ? 22 : 0)
        } ?? 0

        let fixed = Self.leadingPadding + Self.trailingPadding
            + Self.iconSize + Self.spacing
            + trailingWidth + trailingExtra
        let natural = fixed + TextMeasure.width(text, font: Self.textFont)
        let floorWidth = minimumWidth + Self.overhangBeyondNotch

        panelWidth = min(Self.maxWidth, max(floorWidth, natural))
        textWidth = panelWidth - fixed
    }
}

/// Плашка события — компактная панель, выпадающая из-под выреза.
struct ActivityView: View {
    let activity: Activity
    let track: NowPlaying?
    let metrics: NotchMetrics
    let onJoin: (URL) -> Void
    /// Убрать плашку крестиком. Есть только у тех, что не уходят сами.
    let onDismiss: () -> Void
    /// Нажатие по самой плашке. У неинтерактивных не вызывается.
    let onOpen: () -> Void

    static func layout(
        for kind: Activity.Kind,
        track: NowPlaying?,
        metrics: NotchMetrics
    ) -> ActivityLayout {
        ActivityLayout(
            text: text(for: kind, track: track),
            trailing: trailing(for: kind),
            minimumWidth: metrics.closed.width,
            trailingIsButton: joinLink(for: kind) != nil,
            trailingExtra: isDismissable(kind) ? dismissButtonWidth : 0
        )
    }

    /// Ширина крестика вместе с отступом от значения.
    static let dismissButtonWidth: CGFloat = 26

    /// У каких плашек есть крестик. Он нужен там, где плашка не уходит сама.
    static func isDismissable(_ kind: Activity.Kind) -> Bool {
        if case .shelf = kind { return true }
        return false
    }

    /// Ссылка, ради которой в плашке появляется кнопка.
    static func joinLink(for kind: Activity.Kind) -> URL? {
        guard case let .meeting(item, _) = kind else { return nil }
        return item.link?.url
    }

    private var layout: ActivityLayout { Self.layout(for: activity.kind, track: track, metrics: metrics) }

    var body: some View {
        HStack(spacing: ActivityLayout.spacing) {
            // Нажатие живёт здесь, а не снаружи всей плашки: крестик обязан
            // быть отдельной кнопкой, а кнопка, вложенная в кнопку, нажатий
            // не получает — крестик открывал полку вместо того, чтобы её
            // убрать.
            if activity.isInteractive {
                Button(action: onOpen) { content }
                    .buttonStyle(PressableStyle())
            } else {
                content
            }

            if Self.isDismissable(activity.kind) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
            }
        }
        .padding(.leading, ActivityLayout.leadingPadding)
        .padding(.trailing, ActivityLayout.trailingPadding)
        // Содержимое начинается ровно под аппаратным вырезом.
        .padding(.top, metrics.notchHeight + 6)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    private var content: some View {
        HStack(spacing: ActivityLayout.spacing) {
            icon
                .frame(width: ActivityLayout.iconSize, height: ActivityLayout.iconSize)

            MarqueeText(
                text: Self.text(for: activity.kind, track: track),
                font: ActivityLayout.textFont,
                availableWidth: layout.textWidth,
                startDate: activity.createdAt
            )

            if let link = Self.joinLink(for: activity.kind) {
                Button { onJoin(link) } label: {
                    Text(Self.trailing(for: activity.kind) ?? t("Подключиться"))
                        .font(Font(ActivityLayout.trailingFont))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
                .buttonStyle(PressableStyle())
                .fixedSize()
            } else if let trailing = Self.trailing(for: activity.kind) {
                Text(trailing)
                    .font(Font(ActivityLayout.trailingFont))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Содержимое по типу события

    @ViewBuilder
    private var icon: some View {
        switch activity.kind {
        case let .command(_, state):
            switch state {
            case .running:
                RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .overlay(ProgressView().controlSize(.small).scaleEffect(0.7))
            case .done:
                iconTile("checkmark.circle.fill")
            case .failed:
                iconTile("exclamationmark.triangle.fill")
            }
        case let .clipboard(_, kind):
            iconTile(kind.symbol)
        case .shelf:
            iconTile("tray.full")
        case .timer:
            iconTile("timer")
        case let .weather(_, symbol):
            iconTile(symbol)
        case .caffeine:
            iconTile("cup.and.saucer.fill")
        case let .meeting(item, _):
            iconTile(item.symbol)
        case .trackChanged:
            if let artwork = track?.artwork, let image = NSImage(data: artwork) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
            } else {
                iconTile("music.note")
            }
        case .powerConnected:
            iconTile("bolt.fill")
        case .powerDisconnected:
            iconTile("bolt.slash.fill")
        case .lowBattery:
            iconTile("battery.25")
        }
    }

    /// Формат строки трека: исполнитель, затем название.
    static func text(for kind: Activity.Kind, track: NowPlaying?) -> String {
        switch kind {
        case let .command(text, _):
            return text
        case let .clipboard(text, _):
            return text
        case let .shelf(count):
            return tf("На полке файлов: %d", count)
        case let .weather(text, _):
            return text
        case let .caffeine(change):
            switch change {
            case let .on(minutes):
                return minutes > 0
                    ? tf("Экран не гаснет %d мин", minutes)
                    : t("Экран не будет гаснуть")
            case .off:
                return t("Экран снова гаснет как обычно")
            case .expired:
                return t("Время вышло — экран снова гаснет")
            }
        case let .timer(text):
            return text
        case let .meeting(item, minutes):
            return minutes <= 0 ? tf("Сейчас: %@", item.title) : tf("Через %d мин: %@", minutes, item.title)
        case .trackChanged:
            return PreviewPanel.text(track: track)
        case .powerConnected:
            return t("Питание подключено")
        case .powerDisconnected:
            return t("Работа от батареи")
        case .lowBattery:
            return t("Низкий заряд")
        }
    }

    static func trailing(for kind: Activity.Kind) -> String? {
        switch kind {
        case .command:
            return nil
        case .clipboard:
            return t("В буфере")
        // У полки значения справа нет: нажимается вся плашка целиком,
        // и подсказывать «Открыть» отдельным словом незачем.
        case .shelf:
            return nil
        case .weather:
            return nil
        case .caffeine:
            return nil
        case .timer:
            return nil
        case let .meeting(item, _):
            return item.link == nil ? nil : t("Подключиться")
        case .trackChanged:
            return nil
        case let .powerConnected(percentage),
             let .powerDisconnected(percentage),
             let .lowBattery(percentage):
            return "\(percentage)%"
        }
    }

    private var tint: Color {
        switch activity.kind {
        case let .command(_, state):
            switch state {
            case .running: return .white
            case .done: return .green
            case .failed: return .orange
            }
        case .clipboard: return .cyan
        case .shelf: return .cyan
        case .weather: return .cyan
        case .caffeine: return Palette.caffeine
        case .timer: return Palette.timer
        case let .meeting(item, _): return item.color
        case .powerConnected: return .green
        case .lowBattery: return .orange
        case .powerDisconnected, .trackChanged: return .white
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tint)
            )
    }
}
