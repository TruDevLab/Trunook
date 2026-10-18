import AppKit
import SwiftUI

/// История буфера обмена: слева список строками, справа превью записи.
///
/// Строками, а не плитками: у записи важен текст, а он длинный. В плитке
/// от него осталось бы два слова, и отличить одну запись от другой стало бы
/// невозможно. А чтобы прочесть запись целиком, не вставляя её, — превью
/// справа (7 октября, просьба пользователя): текст или изображение, откуда
/// и когда скопировано, сколько знаков, и кнопки действий. Показывает
/// подсвеченную клавишами строку, иначе ту, что под курсором, иначе
/// самую свежую (`ClipboardService.previewEntry`). Нажатие по строке
/// по-прежнему вставляет — превью только смотрят.
struct ClipboardPanel: View {
    @ObservedObject var clipboard: ClipboardService
    private var entries: [ClipboardEntry] { clipboard.entries }
    /// Подтверждение сохранения — своё, а не плашкой в вырезе: накладка
    /// важнее плашки по расчёту состояния, и из-под открытой панели плашки
    /// не видно вовсе.
    @ObservedObject var flash: PanelFlash
    let metrics: NotchMetrics
    /// Сочетание для номерных строк — показываем рядом с номером,
    /// иначе о клавишах никто не узнает.
    let slotHint: String?
    let notesEnabled: Bool
    /// Какая строка подсвечена с клавиатуры. `nil` — ни одна.
    private var highlighted: Int64? { clipboard.highlighted }
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
    private static var minimumWidth: CGFloat { NotchStyle.scaled(680) }

    /// Доля списка в ширине содержимого — левая половина.
    static let listShare: CGFloat = 0.5

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
    /// Общая ступень. Было 34 — строка несёт кнопку «в заметки»
    /// в двадцать четыре точки, и запас вокруг неё подбирали на глаз.
    /// На двадцати восьми она стоит с полем в две точки с каждой стороны:
    /// норму цель нажатия держит сама, а панель стала ниже на шесть точек
    /// на каждой строке.
    static var rowHeight: CGFloat { NotchStyle.rowHeight }
    /// Промежуток между строками входит в расчёт высоты: без него список
    /// обрезал последнюю строку ровно на величину всех зазоров.
    static let rowSpacing = NotchStyle.rowSpacing
    /// Сколько строк видно без прокрутки. Больше — вырез закрывал бы
    /// половину экрана, меньше — список не читается как список.
    static let visibleRows = 6
    /// Превью не короче шести строк списка: при одной записи в истории
    /// панель иначе сжалась бы до строки, и превью было бы негде встать.
    static func height(notchHeight: CGFloat, rows: Int) -> CGFloat {
        let content = rows == 0 ? listHeight(rows: 1) : listHeight(rows: visibleRows)
        return NotchStyle.height(notchHeight: notchHeight, contentHeight: content)
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
                if entries.isEmpty {
                    empty
                } else {
                    HStack(alignment: .top, spacing: NotchStyle.gridSpacing) {
                        list
                            .frame(width: listWidth)
                        if let entry = clipboard.previewEntry {
                            ClipboardPreview(
                                entry: entry,
                                imageData: clipboard.imageData(for:),
                                notesEnabled: notesEnabled,
                                onUse: onUse,
                                onSaveToNotes: onSaveToNotes,
                                onReveal: clipboard.reveal,
                                onDelete: onDelete
                            )
                            .frame(height: Self.listHeight(rows: Self.visibleRows))
                        }
                    }
                }
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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        row(entry, index: index).id(entry.id)
                    }
                }
            }
            .frame(height: Self.listHeight(rows: Self.visibleRows), alignment: .top)
            // Список едет за подсветкой наименьшим движением: строк в истории
            // до полусотни, а видно шесть, — без этого подсветка уходила бы
            // за край, и Enter вставлял бы то, чего не видно.
            .onChange(of: highlighted) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
        }
    }

    /// Сторона кнопки «в заметки» в строке.
    ///
    /// Меньше нормы в 24 точки намеренно: строка сама высотой 34, и кнопка
    /// в 24 съела бы её почти целиком. Промах при этом не страшен — мимо
    /// кнопки попадаешь в саму строку, а это её обычное действие.
    static var noteButtonSize: CGFloat { NotchStyle.scaled(22) }

    private func row(_ entry: ClipboardEntry, index: Int) -> some View {
        let isHighlighted = entry.id == highlighted
        let isPreviewed = entry.id == clipboard.previewEntry?.id && !isHighlighted
        return rowBody(entry, index: index)
            .onHover { inside in
                if inside { clipboard.hovered = entry.id }
            }
            // Что сейчас в превью — тонкой обводкой; подсветка клавишами —
            // своей, толще и цветом буфера.
            .overlay(
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .strokeBorder(isPreviewed ? .white.opacity(0.22) : .clear, lineWidth: 1)
            )
            // Обводкой, а не заливкой: заливка у плитки уже занята
            // наведением, и строка бывает подсвечена клавишей и мышью разом —
            // одной заливкой они слились бы в одно.
            .overlay(
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? Palette.clipboard.opacity(0.9) : .clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }

    private func rowBody(_ entry: ClipboardEntry, index: Int) -> some View {
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

                        Text(entry.age())
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
        if let file = entry.imageFiles.first, let thumb = ClipboardThumbnails.image(at: file, maxSide: 48) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
        } else if let image = entry.image {
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

    /// Ширина списка — половина содержимого.
    private var listWidth: CGFloat {
        let content = Self.width(notchWidth: metrics.notchWidth)
            - 2 * (NotchStyle.bottomPadding + NotchStyle.shoulderInset)
        return (content - NotchStyle.gridSpacing) * Self.listShare
    }
}

/// Правая половина панели буфера: запись целиком, сведения и действия.
struct ClipboardPreview: View {
    let entry: ClipboardEntry
    let imageData: (ClipboardEntry) -> Data?
    let notesEnabled: Bool
    let onUse: (ClipboardEntry) -> Void
    let onSaveToNotes: (ClipboardEntry) -> Void
    let onReveal: (ClipboardEntry) -> Void
    let onDelete: (ClipboardEntry) -> Void

    private static var buttonHeight: CGFloat { NotchStyle.scaled(26) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                        .fill(.white.opacity(NotchStyle.tileFill))
                )
                .clipShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
            Text(Self.info(entry, imageData: imageData))
                .font(.system(size: NotchStyle.captionFontSize))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .lineLimit(1)
                .truncationMode(.middle)
            actions
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .text:
            ScrollView(.vertical, showsIndicators: false) {
                Text(entry.text)
                    .font(.system(size: NotchStyle.captionFontSize + 1))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
        case .image:
            // Вдвое больше места превью — на ретине без мыла, а не снимок
            // экрана целиком на каждом пересчёте панели.
            if let image = ClipboardThumbnails.preview(id: entry.id, maxSide: 800, data: { imageData(entry) }) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: NotchStyle.font(22)))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            }
        case .files where !entry.imageFiles.isEmpty:
            // Файл-картинка — сама картинка; несколько — первая, а имена
            // остальных в строке сведений.
            if let image = ClipboardThumbnails.image(at: entry.imageFiles[0], maxSide: 900) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            }
        case .files:
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(entry.fileURLs, id: \.self) { url in
                        HStack(spacing: 7) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(url.lastPathComponent)
                                .font(.system(size: NotchStyle.captionFontSize + 1))
                                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
            }
        }
    }

    /// Строка сведений: откуда, когда и сколько.
    static func info(_ entry: ClipboardEntry, imageData: (ClipboardEntry) -> Data?, now: Date = Date()) -> String {
        var parts: [String] = []
        if let source = entry.source, !source.isEmpty { parts.append(source) }
        parts.append(entry.age(from: now))
        switch entry.kind {
        case .text:
            let words = entry.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            parts.append(tf("%d знаков", entry.text.count))
            parts.append(tf("%d слов", words))
        case .image:
            parts.append(entry.text)
            if let count = ClipboardThumbnails.byteCount(id: entry.id, data: { imageData(entry) }) {
                parts.append(ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file))
            }
        case .files:
            let images = entry.imageFiles
            if images.count == 1, entry.fileURLs.count == 1 {
                parts.append(images[0].lastPathComponent)
                if let size = ClipboardThumbnails.pixelSize(at: images[0]) {
                    parts.append("\(Int(size.width))×\(Int(size.height))")
                }
                if let bytes = (try? images[0].resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                }
            } else {
                parts.append(tf("файлов: %d", entry.fileURLs.count))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 6) {
            button(t("Вставить"), symbol: "doc.on.clipboard", primary: true) { onUse(entry) }
            if notesEnabled, entry.notesText != nil {
                button(t("В заметки"), symbol: "tray.and.arrow.down") { onSaveToNotes(entry) }
            }
            if entry.kind == .files {
                button(t("В Finder"), symbol: "folder") { onReveal(entry) }
            }
            Spacer(minLength: 0)
            Button { onDelete(entry) } label: {
                Image(systemName: "trash")
                    .font(.system(size: NotchStyle.font(10), weight: .semibold))
                    .foregroundStyle(Palette.negative)
                    .frame(width: Self.buttonHeight, height: Self.buttonHeight)
                    .background(Circle().fill(Palette.negative.opacity(0.14)))
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Удалить запись"))
        }
        .frame(height: Self.buttonHeight)
    }

    private func button(_ title: String, symbol: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: NotchStyle.font(10.5), weight: .semibold))
                .foregroundStyle(primary ? Palette.clipboard : .white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: Self.buttonHeight)
                .background(Capsule().fill(primary ? Palette.clipboard.opacity(0.2) : .white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}

