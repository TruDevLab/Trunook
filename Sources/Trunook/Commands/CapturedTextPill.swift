import SwiftUI

/// Захваченный текст над полем вопроса.
///
/// Не в поле ввода, а над ним — и это не оформительский выбор. В поле его
/// и клали: команда получала выделенное, подставляя его в свой промт, а при
/// свободном вопросе текст уезжал в однострочное поле, где его нельзя было
/// ни прочитать, ни обойти курсором. Хуже того, дописать к нему свой вопрос
/// значило редактировать чужой текст вокруг своего.
///
/// Здесь он лежит отдельно: виден целиком настолько, чтобы узнать его
/// («да, это тот абзац»), не мешает набирать и снимается крестиком. Поле
/// ввода остаётся под то единственное, что человек хочет сказать сам.
struct CapturedTextPill: View {
    let text: String
    /// Плашка раскрыта: видно весь текст, а не две строки.
    let isExpanded: Bool
    let onToggle: () -> Void
    let onClear: () -> Void

    /// Сколько строк текста показывать в свёрнутом виде.
    ///
    /// Две. Одной хватает, чтобы узнать короткую фразу, но не абзац: у него
    /// первая строка бывает общей у десятка соседних. Больше двух — и плашка
    /// начинает соперничать с лентой ответа за высоту панели, которая висит
    /// под чёлкой и растёт только вниз, в чужую работу.
    static let lines = 2

    /// Сколько строк видно в раскрытом виде, дальше — прокрутка.
    ///
    /// Двух строк хватает, чтобы узнать кусок, но не чтобы его прочитать,
    /// а читать иногда надо: захват срабатывает на всё выделенное, и понять,
    /// то ли взялось, по обрезанной фразе нельзя. Потолок нужен по той же
    /// причине, по какой плашка вообще свёрнута, — панель растёт вниз,
    /// в чужую работу.
    static let expandedLines = 8

    /// Поля внутри плашки.
    static let inset = CGSize(width: 9, height: 6)

    /// Кегль текста. Мельче ответа модели нарочно: это не то, что читают,
    /// а то, по чему узнаю́т.
    static let fontSize: CGFloat = 11

    /// Высота плашки — по числу строк, а не по содержимому.
    ///
    /// Высоту панели считает `NotchSizing` ещё до того, как вёрстка
    /// построена, и считать её по длине чужого абзаца значило бы
    /// пересчитывать окно на каждую смену захвата. Короткий текст оставит
    /// вторую строку пустой — это дешевле, чем прыгающая панель.
    ///
    /// Раскрытая — тоже постоянной высоты, по своему потолку: текст в неё
    /// прокручивается. Иначе панель прыгала бы на каждое раскрытие по-разному,
    /// в зависимости от того, что попало в захват.
    static func height(expanded: Bool) -> CGFloat {
        let line = ceil(NSFont.systemFont(ofSize: NotchStyle.font(fontSize)).boundingRectForFont.height)
        return CGFloat(expanded ? expandedLines : lines) * line + 2 * inset.height
    }

    /// Сторона крестика. Меньше кнопок полосы действий: он не действие,
    /// а поправка к тому, что приложение сделало само.
    private static var clearSize: CGFloat { max(18, NotchStyle.scaled(18)) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(Palette.assistant)
                // Значок объясняет плашку, а не сообщает что-то своё: имя
                // для диктора несёт сам текст ниже.
                .accessibilityHidden(true)
                .padding(.top, 1)

            capturedText

            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: NotchStyle.font(9), weight: .bold))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .frame(width: Self.clearSize, height: Self.clearSize)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            // Имя постоянное, состояние — отдельным значением: меняющееся имя
            // диктор прочтёт как другую кнопку, а не как ту же в другом
            // состоянии.
            .notchHint(
                t("Показать захваченное целиком"),
                bubble: isExpanded ? t("Свернуть захваченное") : t("Показать захваченное целиком")
            )
            .accessibilityValue(isExpanded ? t("раскрыто") : t("свёрнуто"))

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: NotchStyle.font(9), weight: .bold))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .frame(width: Self.clearSize, height: Self.clearSize)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Убрать захваченный текст"))
        }
        .padding(.horizontal, Self.inset.width)
        .padding(.vertical, Self.inset.height)
        .frame(height: Self.height(expanded: isExpanded), alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .fill(Palette.assistant.opacity(NotchStyle.dense(0.16)))
        )
    }

    /// Сам текст: свёрнутый обрезается, раскрытый прокручивается.
    ///
    /// Прокрутка только в раскрытом. В свёрнутом она была бы ловушкой: две
    /// строки под курсором мыши перехватывали бы прокрутку страницы, ради
    /// которой человек к вырезу и не обращался.
    @ViewBuilder
    private var capturedText: some View {
        let label = Text(text)
            .font(.system(size: NotchStyle.font(Self.fontSize)))
            .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(tf("Захвачено: %@", text))

        if isExpanded {
            ScrollView(.vertical, showsIndicators: false) {
                label.fixedSize(horizontal: false, vertical: true)
            }
        } else {
            label
                .lineLimit(Self.lines)
                .truncationMode(.tail)
        }
    }
}
