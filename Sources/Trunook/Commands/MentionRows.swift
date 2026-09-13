import SwiftUI

/// Список того, на что можно показать через «@»: встречи и заметки.
///
/// Занимает тот же слот под полем, что список команд и действия с ответом,
/// и живёт по тем же меркам — `CommandRows.rowHeight` и `spacing`. Своя
/// высота строки развела бы два списка, стоящих в одном месте по очереди:
/// панель прыгала бы на каждое «@».
///
/// Строки только выбирают. Ни модели, ни сочетания у записи нет — правая
/// часть строки отдана времени встречи и дате заметки, то есть тому,
/// чем две одинаково названные записи и различаются.
struct MentionRows: View {
    let mentions: [Mention]
    /// Какая строка подсвечена с клавиатуры. Ведёт её `NotchController`
    /// теми же стрелками, что и список команд.
    let highlighted: Int?
    let onPick: (Mention) -> Void

    /// Сколько строк видно разом. Столько же, сколько у команд: список
    /// стоит на их месте, и разная длина читалась бы как разная важность.
    static var visibleRows: Int { QuickCommands.visibleRows }

    static func height(rows count: Int) -> CGFloat {
        CommandRows.height(rows: count)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GlassGroup(spacing: CommandRows.spacing) {
                    VStack(spacing: CommandRows.spacing) {
                        if mentions.isEmpty {
                            emptyRow
                        } else {
                            ForEach(Array(mentions.enumerated()), id: \.element.id) { index, mention in
                                row(mention, at: index)
                            }
                        }
                    }
                }
            }
            .frame(height: Self.height(rows: mentions.count))
            // Подсветка уходит вниз по списку, а видно четыре строки:
            // без прокрутки вслед за ней Enter выбирал бы то, чего на экране
            // нет. Та же беда и то же лечение, что у списка команд.
            .onChange(of: highlighted) { _, index in
                guard let index, mentions.indices.contains(index) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(mentions[index].id, anchor: nil)
                }
            }
        }
    }

    /// Ничего не нашлось. Пустая строка вместо исчезнувшего списка:
    /// исчезнувший читается как «@ не работает», а строка отвечает на то,
    /// что человек сейчас набирает.
    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .frame(width: 16)
            Text(t("Ничего похожего"))
                .font(.system(size: NotchStyle.font(11.5)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .frame(height: CommandRows.rowHeight)
    }

    private func row(_ mention: Mention, at index: Int) -> some View {
        let isHighlighted = index == highlighted
        return NotchTile(
            id: "mention-\(mention.id)",
            radius: NotchStyle.rowRadius,
            isHighlighted: isHighlighted
        ) {
            Button { onPick(mention) } label: {
                HStack(spacing: 8) {
                    Image(systemName: mention.symbol)
                        .font(.system(size: NotchStyle.font(11), weight: .medium))
                        .foregroundStyle(mention.tint)
                        .frame(width: 16)

                    Text(mention.title)
                        .font(.system(size: NotchStyle.font(11.5)))
                        .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    // Время встречи и дата заметки — приглушённее названия:
                    // выбирают по названию, а время отвечает на «которая
                    // из двух».
                    Text(mention.detail)
                        .font(.system(size: NotchStyle.font(10.5)))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: CommandRows.modelWidth, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .frame(height: CommandRows.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(mention.title, bubble: mention.title + " · " + mention.detail)
        }
        // Та же обводка, что у команд: заливку строка получает и от мыши,
        // а обводка говорит, что сюда привела клавиатура и Enter сработает
        // именно здесь.
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .fill(Palette.assistant.opacity(isHighlighted ? NotchStyle.dense(0.32) : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Palette.assistant.opacity(0.9) : .clear,
                    lineWidth: 1.5
                )
        )
        .id(mention.id)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }
}
