import SwiftUI

/// Блокировка клавиатуры для чистки: выбор срока и отсчёт.
///
/// Устроена как панель бодрости, с одним отличием: после выбора срока
/// она **не закрывается**. Клавиатура в этот момент мертва, и единственное,
/// что человеку нужно видеть, — сколько осталось и где кнопка, которая
/// вернёт её раньше. Закрывается по сроку сама.
struct KeyboardLockPanel: View {
    @ObservedObject var lock: KeyboardLock
    let metrics: NotchMetrics
    let onChoose: (Int) -> Void
    let onUnlock: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var statusHeight: CGFloat { NotchStyle.scaled(22) }
    private static var rowHeight: CGFloat { NotchStyle.rowHeight }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: statusHeight + NotchStyle.gridSpacing + rowHeight
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(symbol: "keyboard", title: t("Чистка"), tint: Palette.keyboardLock)
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                status
                choices
            }
        }
    }

    private var status: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.statusText(lock: lock, now: context.date))
                .font(.system(size: NotchStyle.rowFontSize))
                .foregroundStyle(lock.failed ? Palette.warning : .white.opacity(
                    lock.isOn ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                ))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.statusHeight)
        }
    }

    static func statusText(lock: KeyboardLock, now: Date) -> String {
        if let endsAt = lock.endsAt {
            return tf("Клавиатура заблокирована — осталось %@", KeyboardLock.clock(until: endsAt, now: now))
        }
        if lock.failed { return t("Не удалось — нужен Универсальный доступ") }
        return t("Заблокировать клавиатуру, чтобы протереть её")
    }

    static func title(seconds: Int) -> String {
        tf("%d с", seconds)
    }

    private var choices: some View {
        HStack(spacing: 6) {
            // «Разблокировать» первым и только пока есть что снимать — как
            // «Выключить» у чашки: ради него к панели и возвращаются.
            if lock.isOn {
                choice(title: t("Разблокировать"), tint: Palette.negative, isChosen: false, action: onUnlock)
            }
            ForEach(KeyboardLock.durations, id: \.self) { seconds in
                choice(
                    title: Self.title(seconds: seconds),
                    tint: Palette.keyboardLock,
                    isChosen: lock.isOn && lock.activeSeconds == seconds,
                    action: { onChoose(seconds) }
                )
            }
        }
        .frame(height: Self.rowHeight)
    }

    private func choice(
        title: String,
        tint: Color,
        isChosen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
        return Button(action: action) {
            Text(title)
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(isChosen ? tint : .white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
                .background(shape.fill(.white.opacity(isChosen ? NotchStyle.tileFill : 0.02)))
                .overlay(shape.strokeBorder(isChosen ? tint : .clear, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }
}

/// Значок блокировки в левом крыле главного экрана, рядом с чашкой.
///
/// Той же выделкой, что и чашка: пока клавиатура заглушена — подложка
/// с обводкой. Панель к этому времени могли закрыть щелчком мимо,
/// и значок остаётся единственным признаком, что клавиатура не работает.
struct KeyboardLockButton: View {
    let isOn: Bool
    let action: () -> Void

    private static let side: CGFloat = NotchPanelButton.size

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
        Button(action: action) {
            Image(systemName: "keyboard")
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(isOn ? Palette.keyboardLock : .white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.side, height: Self.side)
                .background(shape.fill(isOn ? Palette.keyboardLock.opacity(0.2) : .clear))
                .overlay(shape.strokeBorder(isOn ? Palette.keyboardLock : .clear, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .notchHint(
            t("Чистка"),
            bubble: isOn ? t("Клавиатура заблокирована — нажмите, чтобы снять")
                         : t("Заблокировать клавиатуру для чистки")
        )
        .accessibilityValue(isOn ? t("заблокирована") : t("работает"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
