import AppKit
import SwiftUI

/// Телесуфлер — прямо под чёлкой.
///
/// Место выбрано не за неимением другого: камера MacBook стоит **в самом
/// вырезе**, и текст, который читают вслух, обязан быть к ней как можно ближе.
/// Читая из окна посреди экрана, человек смотрит мимо объектива, и на записи
/// это видно сразу. Здесь взгляд остаётся на камере.
///
/// Отсюда и остальное устройство: панель не закрывается ни по уходу курсора,
/// ни по нажатию мимо — в чужом окне в это время работают, — а текст живёт
/// на диске и не пропадает сам.
struct TeleprompterPanel: View {
    @ObservedObject var store: TeleprompterStore
    let metrics: NotchMetrics
    let onClose: () -> Void

    /// Шире прочих панелей: строку речи читают целиком, а перенос на каждом
    /// третьем слове сбивает темп.
    static let width: CGFloat = 560
    /// Высота видимой части текста. Панель висит подолгу, поэтому не во весь
    /// экран: под ней продолжают работать.
    static let bodyHeight: CGFloat = 300
    /// Полоса управления прокруткой под текстом.
    private static let controlsHeight: CGFloat = 28

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: bodyHeight + NotchStyle.gridSpacing + controlsHeight
        )
    }

    var body: some View {
        NotchPanel(
            metrics: metrics,
            width: Self.width,
            // Текст и полоса управления тянутся во всю ширину, поэтому поле
            // отмеряется от чёрного тела, а не от рамки: вогнутое плечо формы
            // иначе съело бы три четверти бокового отступа.
            bodyPadding: NotchStyle.bottomPadding
        ) {
            NotchPanelTitle(
                symbol: "text.alignleft",
                title: t("Телесуфлер"),
                tint: Palette.teleprompter
            )
        } trailing: {
            HStack(spacing: 2) {
                NotchPanelButton(symbol: "textformat.size.larger", hint: t("Заголовок"),
                                 action: store.toggleHeading)
                NotchPanelButton(symbol: "bold", hint: t("Полужирный"), action: store.toggleBold)
                NotchPanelButton(symbol: "italic", hint: t("Курсив"), action: store.toggleItalic)
                NotchPanelButton(symbol: "underline", hint: t("Подчёркнутый"),
                                 action: store.toggleUnderline)
                NotchPanelButton(symbol: "link", hint: t("Ссылка"), action: store.askForLink)
                NotchPanelButton(symbol: "face.smiling", hint: t("Эмодзи"),
                                 action: store.showEmojiPalette)
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                TeleprompterTextView(store: store)
                    .frame(height: Self.bodyHeight)
                    .background(
                        RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
                            .fill(.white.opacity(NotchButtonStyle.restingFill))
                    )
                // Строка вопроса занимает место полосы управления, а не
                // добавляется к ней: высота панели задана числом, и выросшее
                // содержимое вылезло бы за её край.
                switch store.prompt {
                case .link: linkRow
                case .clear: clearRow
                case nil: controls
                }
            }
        }
    }

    // MARK: - Полоса управления

    private var controls: some View {
        HStack(spacing: 8) {
            action(
                store.isScrolling ? "pause.fill" : "play.fill",
                store.isScrolling ? t("Стоп") : t("Пуск"),
                tint: Palette.teleprompter,
                action: store.toggleScrolling
            )
            .disabled(store.isEmpty)

            action("arrow.up.to.line", t("В начало"), action: store.scrollToStart)
                .disabled(store.isEmpty)

            speedSlider

            Spacer(minLength: 6)

            action("trash", t("Очистить"), tint: Palette.negative, action: store.askToClear)
                .disabled(store.isEmpty)
        }
        .frame(height: Self.controlsHeight)
    }

    private var speedSlider: some View {
        HStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(store.speed) },
                    set: { store.speed = Int($0.rounded()) }
                ),
                in: Double(TeleprompterStore.minSpeed)...Double(TeleprompterStore.maxSpeed)
            )
            .controlSize(.mini)
            .tint(Palette.teleprompter)
            .frame(width: 96)
            // Ширина задана: без неё полоса дёргалась бы на каждой смене
            // числа с двузначного на трёхзначное.
            .help(t("Скорость прокрутки"))
            Text(tf("%d т/с", store.speed))
                .font(.system(size: NotchStyle.captionFontSize, design: .monospaced))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: 46, alignment: .leading)
        }
    }

    // MARK: - Строки вопросов
    //
    // Вместо всплывающих окон. Окно система ставит по центру экрана — то есть
    // ровно под чёлкой, — и панель телесуфлера его закрывала: диалог был,
    // а увидеть его было нельзя.

    private var linkRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.teleprompter)
            TextField("https://", text: $store.linkAddress)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                        .fill(.black.opacity(0.3))
                )
                .onSubmit(store.confirmLink)

            action("checkmark", t("Применить"), tint: Palette.teleprompter, action: store.confirmLink)
            action("xmark", t("Отмена"), action: store.cancelPrompt)
        }
        .frame(height: Self.controlsHeight)
    }

    private var clearRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.warning)
            Text(t("Удалить весь текст? Вернуть его будет нельзя."))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 6)
            action("trash", t("Очистить"), tint: Palette.negative, action: store.confirmClear)
            action("xmark", t("Отмена"), action: store.cancelPrompt)
        }
        .frame(height: Self.controlsHeight)
    }

    private func action(
        _ symbol: String,
        _ title: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: NotchStyle.hintFontSize + 1.5, weight: .medium))
                    .fixedSize()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .fill(.white.opacity(NotchStyle.tileFill))
            )
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
