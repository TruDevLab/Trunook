import AppKit
import SwiftUI

/// История буфера обмена строками, прямо в вырезе.
///
/// Строками, а не плитками: у записи важен текст, а он длинный. В плитке
/// от него осталось бы два слова, и отличить одну запись от другой стало бы
/// невозможно.
struct ClipboardPanel: View {
    let entries: [ClipboardEntry]
    /// Подтверждение сохранения — своё, а не плашкой в вырезе: накладка
    /// важнее плашки по расчёту состояния, и из-под открытой панели плашки
    /// не видно вовсе.
    @ObservedObject var flash: PanelFlash
    let metrics: NotchMetrics
    /// Сочетание для номерных строк — показываем рядом с номером,
    /// иначе о клавишах никто не узнает.
    let slotHint: String?
    let notesEnabled: Bool
    let onUse: (ClipboardEntry) -> Void
    let onSaveToNotes: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void
    let onClear: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    /// Место под подсказку клавиш в крыле.
    ///
    /// Считается по самому длинному из вариантов, а не подбирается числом:
    /// набор сочетаний настраивается, и «⇧⌘1…9» шире «⌃⌥1…9».
    private static var slotHintWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: NotchStyle.hintFontSize, weight: .medium)
        return ClipboardSlotModifiers.allCases
            .compactMap(\.hint)
            .map { TextMeasure.width($0, font: font) }
            .max() ?? 0
    }

    /// Ширина панели.
    ///
    /// В крыле, кроме трёх кнопок, стоит подсказка про номерные клавиши.
    /// При области нажатия в 24 точки ряд перестал помещаться в прежние 440:
    /// подсказка вылезала под чёлку, где её не прочесть, — а она там ровно
    /// затем, чтобы о клавишах узнали.
    /// Прежняя ширина — теперь нижняя граница: у́же панель не станет,
    /// даже если крылу столько и не нужно.
    private static var minimumWidth: CGFloat { NotchStyle.scaled(440) }

    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: 3, reserved: slotHintWidth),
                notchWidth: notchWidth,
                bodyPadding: NotchStyle.bottomPadding
            )
        )
    }
    static var rowHeight: CGFloat { NotchStyle.scaled(34) }
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
        NotchPanel(
            metrics: metrics,
            width: Self.width(notchWidth: metrics.notchWidth),
            bodyPadding: NotchStyle.bottomPadding
        ) {
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
                    NotchPanelButton(symbol: "trash", hint: t("Очистить историю"), action: onClear)
                }
                NotchPanelButton(symbol: "gearshape", hint: t("Настройки"), action: onOpenSettings)
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            Group {
                if entries.isEmpty { empty } else { list }
            }
            .overlay(alignment: .bottomTrailing) { PanelFlashPill(flash: flash) }
        }
    }

    private var empty: some View {
        VStack(spacing: 3) {
            Text(t("Пока пусто"))
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
            Text(t("Скопируйте что-нибудь — запись появится здесь"))
                .font(.system(size: NotchStyle.font(10)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
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

    /// Сторона кнопки «в заметки» в строке.
    ///
    /// Меньше нормы в 24 точки намеренно: строка сама высотой 34, и кнопка
    /// в 24 съела бы её почти целиком. Промах при этом не страшен — мимо
    /// кнопки попадаешь в саму строку, а это её обычное действие.
    static var noteButtonSize: CGFloat { NotchStyle.scaled(22) }

    private func row(_ entry: ClipboardEntry, index: Int) -> some View {
        // `NotchTile`, а не своя подложка. Своя была двумя ошибками сразу:
        // плотность 0.06 против 0.08 у соседних панелей — то есть строка была
        // тусклее всего, что лежит рядом, — и мимо `dense()`, поэтому при
        // «уменьшить прозрачность» она одна не уплотнялась.
        //
        // Главное же — отклика на курсор не было вовсе. Плитка написана ровно
        // против этого, и панель, где строк больше всего и промах дороже
        // всего, обходилась без неё дольше остальных.
        NotchTile(id: "clipboard-\(entry.id)", radius: NotchStyle.rowRadius) {
            HStack(spacing: 0) {
                // Нажатие живёт внутри плитки, а не вокруг неё: кнопка
                // «в заметки» обязана быть отдельной кнопкой, а кнопка,
                // вложенная в кнопку, нажатий не получает — она вставляла бы
                // запись вместо того, чтобы её сохранить.
                Button { onUse(entry) } label: {
                    HStack(spacing: 9) {
                        number(index)
                        preview(entry)
                            .frame(width: 18, height: 18)

                        Text(entry.oneLine)
                            .font(.system(size: NotchStyle.font(11.5)))
                            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(subtitle(entry))
                            .font(.system(size: NotchStyle.font(9.5)))
                            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.leading, 8)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())

                noteButton(entry)
                    .padding(.horizontal, 4)
            }
            .padding(.trailing, 4)
        }
        .contextMenu {
            Button(t("Удалить запись"), role: .destructive) { onDelete(entry) }
        }
    }

    /// Отложить запись в заметки, не вставляя её никуда.
    ///
    /// Есть только у текста: изображение в заметку не положить, а список
    /// путей к файлам заметкой не является — файлы откладывают на полку.
    /// У остальных строк на её месте пустое поле той же ширины: строки,
    /// у которых текст обрывается в разных точках, читаются как рваный
    /// список, а не как ровный.
    @ViewBuilder
    private func noteButton(_ entry: ClipboardEntry) -> some View {
        if notesEnabled, entry.notesText != nil {
            Button { onSaveToNotes(entry) } label: {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: NotchStyle.font(10), weight: .semibold))
                    .foregroundStyle(Palette.assistant)
                    .frame(width: Self.noteButtonSize, height: Self.noteButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("В заметки"))
        } else if notesEnabled {
            Color.clear.frame(width: Self.noteButtonSize, height: Self.noteButtonSize)
        }
    }

    /// Номер есть только у тех строк, до которых дотягивается клавиша.
    @ViewBuilder
    private func number(_ index: Int) -> some View {
        if index < ClipboardService.hotSlotCount {
            Text("\(index + 1)")
                .font(.system(size: NotchStyle.font(9), weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
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
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                // Вид записи виден по самому тексту строки рядом: диктору
                // значок добавил бы шум, а не сведения.
                .accessibilityHidden(true)
        }
    }

    private func subtitle(_ entry: ClipboardEntry) -> String {
        guard let source = entry.source else { return entry.age() }
        return "\(source) · \(entry.age())"
    }
}
