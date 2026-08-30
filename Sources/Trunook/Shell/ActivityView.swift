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
/// Что делает кнопка-капсула справа в плашке.
enum ActivityButton: Equatable {
    case join(URL)
    case installUpdate
}

struct ActivityView: View {
    let activity: Activity
    let track: NowPlaying?
    let metrics: NotchMetrics
    let onJoin: (URL) -> Void
    /// Поставить скачанное обновление и перезапуститься.
    let onInstallUpdate: () -> Void
    /// Убрать плашку крестиком. Есть только у тех, что не уходят сами.
    let onDismiss: () -> Void
    /// Нажатие по самой плашке. У неинтерактивных не вызывается.
    let onOpen: () -> Void
    /// Отложить скопированное в заметки, не открывая ничего.
    let onSaveToNotes: (ClipboardEntry) -> Void
    /// Заметки включены. От этого зависит не только кнопка, но и ширина
    /// плашки — поэтому признак приходит и сюда, и в расчёт размера.
    let notesEnabled: Bool

    static func layout(
        for kind: Activity.Kind,
        track: NowPlaying?,
        metrics: NotchMetrics,
        notesEnabled: Bool
    ) -> ActivityLayout {
        ActivityLayout(
            text: text(for: kind, track: track),
            trailing: trailing(for: kind),
            minimumWidth: metrics.closed.width,
            trailingIsButton: button(for: kind) != nil,
            trailingExtra: sideButtonCount(kind, notesEnabled: notesEnabled) * sideButtonWidth
        )
    }

    /// Сколько кнопок стоит справа от значения — за пределами нажимаемой
    /// части плашки.
    ///
    /// Считается здесь, а не выписывается по месту: по этому же числу
    /// отмеряется ширина плашки, и разойдясь с рисунком, оно обрезало бы
    /// последнюю кнопку.
    static func sideButtonCount(_ kind: Activity.Kind, notesEnabled: Bool) -> CGFloat {
        var count: CGFloat = 0
        if isDismissable(kind) { count += 1 }
        if notesEntry(for: kind, notesEnabled: notesEnabled) != nil { count += 1 }
        return count
    }

    /// Запись, которую с этой плашки можно отложить в заметки.
    ///
    /// Только у скопированного текста: изображение в заметку не положить,
    /// а список путей к файлам заметкой не является — файлы откладывают
    /// на полку.
    static func notesEntry(for kind: Activity.Kind, notesEnabled: Bool) -> ClipboardEntry? {
        guard notesEnabled, case let .clipboard(entry) = kind else { return nil }
        return entry.notesText == nil ? nil : entry
    }

    /// Место под одну боковую кнопку вместе с отступом от значения.
    ///
    /// Считается от самой кнопки: выписанное числом, оно разошлось бы с ней
    /// при первой же правке размера — а разойдясь, обрезало бы кнопку.
    static let sideButtonWidth: CGFloat = NotchPanelButton.size + 2

    /// У каких плашек есть крестик. Он нужен там, где плашка не уходит сама.
    static func isDismissable(_ kind: Activity.Kind) -> Bool {
        if case .shelf = kind { return true }
        return false
    }

    /// Что делает кнопка-капсула, если она в плашке есть.
    ///
    /// Одной функцией на оба применения нарочно: по её ответу и отмеряется
    /// место под кнопку (`trailingIsButton`), и рисуется сама кнопка. Пока
    /// это были две отдельные проверки — на ссылку встречи в расчёте ширины
    /// и на неё же в вёрстке, — им полагалось молча совпадать, а это ровно
    /// тот сорт уговора, который однажды нарушают.
    static func button(for kind: Activity.Kind) -> ActivityButton? {
        switch kind {
        case let .meeting(item, _):
            return (item.link?.url).map(ActivityButton.join)
        case .update:
            return .installUpdate
        default:
            return nil
        }
    }

    private var layout: ActivityLayout {
        Self.layout(
            for: activity.kind,
            track: track,
            metrics: metrics,
            notesEnabled: notesEnabled
        )
    }

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

            // Скопированное — сразу в заметки, не открывая ни истории,
            // ни панели. Плашка и так висит перед глазами четыре секунды
            // ровно затем, чтобы по ней успели попасть курсором, — а решение
            // «это стоит сохранить» приходит именно в тот миг, когда текст
            // скопирован, а не когда за ним вернутся в историю.
            //
            // Отдельной кнопкой рядом, а не внутри: сама плашка — тоже
            // кнопка, а кнопка, вложенная в кнопку, нажатий не получает.
            if let entry = Self.notesEntry(for: activity.kind, notesEnabled: notesEnabled) {
                sideButton(
                    symbol: "tray.and.arrow.down",
                    hint: t("В заметки"),
                    tint: Palette.assistant
                ) { onSaveToNotes(entry) }
            }

            if Self.isDismissable(activity.kind) {
                sideButton(
                    symbol: "xmark",
                    hint: t("Закрыть"),
                    tint: .white.opacity(NotchStyle.secondaryOpacity),
                    action: onDismiss
                )
            }
        }
        .padding(.leading, ActivityLayout.leadingPadding)
        .padding(.trailing, ActivityLayout.trailingPadding)
        // Содержимое начинается ровно под аппаратным вырезом.
        .padding(.top, metrics.notchHeight + 6)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
    }

    /// Кнопка сбоку от плашки — за пределами её нажимаемой части.
    ///
    /// Размер тот же, что у кнопок в шапках панелей: это одни и те же кнопки,
    /// и попадать в них должно быть одинаково легко. По этому же размеру
    /// отмеряется место в раскладке — см. `sideButtonWidth`.
    private func sideButton(
        symbol: String,
        hint: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(10), weight: .bold))
                .foregroundStyle(tint)
                .frame(width: NotchPanelButton.size, height: NotchPanelButton.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint)
        .fixedSize()
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

            if let action = Self.button(for: activity.kind) {
                Button { perform(action) } label: {
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
        case let .clipboard(entry):
            iconTile(entry.kind.symbol)
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
        case .update:
            iconTile("arrow.down.circle.fill")
        }
    }

    /// Формат строки трека: исполнитель, затем название.
    static func text(for kind: Activity.Kind, track: NowPlaying?) -> String {
        switch kind {
        case let .command(text, _):
            return text
        case let .clipboard(entry):
            return entry.oneLine
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
        case let .update(version):
            return tf("Вышла новая версия %@", version)
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
        case .update:
            return t("Обновить")
        }
    }

    /// Цвет значка в плашке.
    ///
    /// Весь до единого — из `Palette`. Раньше половина шла оттуда, а половина
    /// системными `.green`, `.cyan`, `.orange`, и это ломалось дважды.
    ///
    /// По смыслу: `Palette.shelf` — янтарный, а плашка полки брала `.cyan`.
    /// Одно и то же событие было оранжевым в панели и голубым в плашке
    /// под чёлкой, то есть цвет переставал что-либо значить ровно там, где
    /// он единственное, чем событие и опознаётся.
    ///
    /// По оттенку: системные цвета рассчитаны на оба режима и на чёрном теле
    /// заметно тусклее собственных. Рядом в этом же `switch` стояли обе пары,
    /// и разницу было видно, не выходя из файла.
    private var tint: Color {
        switch activity.kind {
        case let .command(_, state):
            switch state {
            case .running: return Palette.panel
            case .done: return Palette.positive
            case .failed: return Palette.warning
            }
        case .clipboard: return Palette.clipboard
        case .shelf: return Palette.shelf
        case .weather: return Palette.weather
        case .caffeine: return Palette.caffeine
        case .timer: return Palette.timer
        case let .meeting(item, _): return item.color
        case .powerConnected: return Palette.positive
        case .lowBattery: return Palette.warning
        // Мятный, а не янтарный: янтарь в этом наборе означает «что-то
        // не так», а готовое обновление — хорошая новость.
        case .update: return Palette.positive
        case .powerDisconnected, .trackChanged: return Palette.panel
        }
    }

    private func perform(_ action: ActivityButton) {
        switch action {
        case let .join(link): onJoin(link)
        case .installUpdate: onInstallUpdate()
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
            .fill(.white.opacity(0.12))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: NotchStyle.font(12), weight: .medium))
                    .foregroundStyle(tint)
            )
    }
}
