import SwiftUI

/// История буфера обмена строками, прямо в вырезе.
///
/// Строками, а не плитками: у записи важен текст, а он длинный. В плитке
/// от него осталось бы два слова, и отличить одну запись от другой стало бы
/// невозможно.
struct ClipboardPanel: View {
    let entries: [ClipboardEntry]
    let metrics: NotchMetrics
    /// Сочетание для номерных строк — показываем рядом с номером,
    /// иначе о клавишах никто не узнает.
    let slotHint: String?
    let onUse: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    static let width: CGFloat = 440
    static let rowHeight: CGFloat = 34
    /// Промежуток между строками входит в расчёт высоты: без него список
    /// обрезал последнюю строку ровно на величину всех зазоров.
    static let rowSpacing = NotchStyle.rowSpacing
    /// Сколько строк видно без прокрутки. Больше — вырез закрывал бы
    /// половину экрана, меньше — список не читается как список.
    static let visibleRows = 6
    static func height(notchHeight: CGFloat, rows: Int) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: listHeight(rows: rows))
    }

    /// Высота видимой части списка.
    static func listHeight(rows: Int) -> CGFloat {
        let shown = max(1, min(rows, visibleRows))
        return CGFloat(shown) * rowHeight + CGFloat(shown - 1) * rowSpacing
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: NotchStyle.bottomPadding) {
            NotchPanelTitle(
                symbol: "doc.on.clipboard",
                title: t("Буфер"),
                tint: Palette.clipboard
            )
        } trailing: {
            HStack(spacing: 2) {
                // Подсказка про цифры — в крыле: она нужна один раз,
                // чтобы о клавишах узнали, и не стоит строки в списке.
                if let slotHint {
                    Text(slotHint)
                        .font(.system(size: NotchStyle.hintFontSize, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .fixedSize()
                }
                if !entries.isEmpty {
                    NotchPanelButton(symbol: "trash", action: onClear)
                }
                NotchPanelButton(symbol: "gearshape", action: onOpenSettings)
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", action: onClose)
            }
        } content: {
            if entries.isEmpty { empty } else { list }
        }
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Text(t("Пока пусто"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(t("Скопируйте что-нибудь — запись появится здесь"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.rowHeight)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, index: index)
                }
            }
        }
        .frame(height: Self.listHeight(rows: entries.count))
    }

    private func row(_ entry: ClipboardEntry, index: Int) -> some View {
        Button { onUse(entry) } label: {
            HStack(spacing: 9) {
                number(index)
                preview(entry)
                    .frame(width: 18, height: 18)

                Text(entry.oneLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(subtitle(entry))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous).fill(.white.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button(t("Удалить запись"), role: .destructive) { onDelete(entry) }
        }
    }

    /// Номер есть только у тех строк, до которых дотягивается клавиша.
    @ViewBuilder
    private func number(_ index: Int) -> some View {
        if index < ClipboardService.hotSlotCount {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 14)
        } else {
            Color.clear.frame(width: 14)
        }
    }

    @ViewBuilder
    private func preview(_ entry: ClipboardEntry) -> some View {
        if let image = entry.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
        } else {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func subtitle(_ entry: ClipboardEntry) -> String {
        guard let source = entry.source else { return entry.age() }
        return "\(source) · \(entry.age())"
    }
}
