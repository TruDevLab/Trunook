import SwiftUI

/// Список заметок.
///
/// Строка — это имя и под ним начало текста. Имя придумывает модель,
/// и оно отвечает на «что это»; начало текста отвечает на «точно ли это то»,
/// когда имён похоже несколько.
///
/// Нажатие по строке открывает заметку на правку **в панели модели** — там же,
/// где её и набирали. Отдельного окна правки нет: поле ввода уже есть,
/// и заводить рядом второе такое же значило бы держать две разные привычки
/// для одного действия.
struct NotesPanel: View {
    @ObservedObject var notes: NotesService
    let metrics: NotchMetrics
    let onOpen: (Note) -> Void
    let onDelete: (Note) -> Void
    /// Есть ли у заметки файл в хранилище Obsidian. Не свойство заметки:
    /// это знает служба синхронизации, а список о ней ничего не знает
    /// и знать не должен.
    let isInVault: (Note) -> Bool
    let onOpenInObsidian: (Note) -> Void
    let onExportAll: () -> Void
    /// Перейти к созданию заметки. Из списка это первое, чего хочется:
    /// пришёл посмотреть записанное — и вспомнил, что записать ещё.
    let onNewNote: () -> Void
    let onClose: () -> Void

    // MARK: - Размеры

    private static var minimumWidth: CGFloat { NotchStyle.scaled(440) }

    /// Ширина считается от чёлки, а не берётся числом: в крыле три кнопки,
    /// а ширина крыла у каждой модели MacBook своя.
    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: 3),
                notchWidth: notchWidth,
                bodyPadding: NotchStyle.bottomPadding
            )
        )
    }

    /// Строка выше, чем у буфера: в ней два яруса — имя и под ним начало
    /// текста.
    /// Двойная ступень: у заметки заголовок и подпись под ним.
    static var rowHeight: CGFloat { NotchStyle.rowHeightDouble }
    static var searchHeight: CGFloat { NotchStyle.scaled(26) }
    static let rowSpacing = NotchStyle.rowSpacing

    /// Сколько строк видно сразу. Дальше — прокрутка: список, который может
    /// пополниться, обязан прокручиваться с самого начала, иначе однажды
    /// он вырастет и обрежется.
    static let visibleRows = 5

    static func listHeight(rows: Int) -> CGFloat {
        let shown = max(1, min(rows, visibleRows))
        return CGFloat(shown) * rowHeight + CGFloat(shown - 1) * rowSpacing
    }

    static func height(notchHeight: CGFloat, rows: Int) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: searchHeight + NotchStyle.gridSpacing + listHeight(rows: rows)
        )
    }

    // MARK: - Тело

    var body: some View {
        NotchPanel(
            metrics: metrics,
            width: Self.width(notchWidth: metrics.notchWidth),
            // Список тянется во всю ширину, поэтому поле отмеряется
            // от чёрного тела, а не от рамки: вогнутое плечо формы иначе
            // съедает три четверти бокового отступа.
            bodyPadding: NotchStyle.bottomPadding
        ) {
            HStack(spacing: 6) {
                NotchPanelTitle(
                    symbol: "list.bullet.rectangle",
                    title: t("Заметки"),
                    tint: Palette.notes
                )
                if notes.total > 0 {
                    NotchPanelCount(value: notes.total)
                }
            }
        } trailing: {
            HStack(spacing: 2) {
                // Новая заметка — первой: из списка чаще всего идут именно
                // сюда, а не в выгрузку.
                NotchPanelButton(
                    symbol: "square.and.pencil",
                    hint: t("Новая заметка"),
                    action: onNewNote
                )
                NotchPanelButton(
                    symbol: "square.and.arrow.up",
                    hint: t("Выгрузить все заметки в папку"),
                    action: onExportAll
                )
                // Выгружать нечего, пока заметок нет. Крестик и новая заметка
                // от этого не гаснут: закрыть панель и начать писать нужно
                // в любом случае.
                .disabled(notes.total == 0)
                .opacity(notes.total == 0 ? 0.5 : 1)

                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                search
                if notes.notes.isEmpty {
                    empty
                } else {
                    list
                }
            }
        }
    }

    // MARK: - Поиск

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                // Значок — метка поля, а не отдельная мысль: он повторяет
                // то, что уже сказано подсказкой рядом.
                .accessibilityHidden(true)
            FocusedTextField(
                text: Binding(get: { notes.query }, set: { notes.query = $0 }),
                placeholder: t("Поиск по заметкам"),
                onSubmit: {}
            )
            .accessibilityLabel(t("Поиск по заметкам"))
            if notes.isSearching {
                Button(action: { notes.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: NotchStyle.font(11)))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(t("Очистить поиск"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.searchHeight)
        .background(Capsule().fill(.white.opacity(NotchStyle.tileFill)))
    }

    // MARK: - Пустые состояния

    /// Их два, и это разные слова. «Заметок нет» объясняет, что делать;
    /// «ничего не нашлось» объясняет, что искали не то. Одна строка на оба
    /// случая врала бы в одном из них.
    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: notes.isSearching ? "magnifyingglass" : "square.and.pencil")
                .font(.system(size: NotchStyle.font(18)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .accessibilityHidden(true)
            Text(notes.isSearching
                ? t("По этому запросу ничего нет")
                : t("Заметок пока нет — начните новую кнопкой сверху"))
                .font(.system(size: NotchStyle.font(11.5)))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.listHeight(rows: 0))
    }

    // MARK: - Список

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(notes.notes) { note in
                    row(note)
                }
            }
        }
        .frame(height: Self.listHeight(rows: notes.notes.count))
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 10) {
            Image(systemName: note.origin.symbol)
                .font(.system(size: NotchStyle.font(11)))
                .foregroundStyle(Palette.notes.opacity(0.9))
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: NotchStyle.rowFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    .lineLimit(1)
                Text(note.oneLine)
                    .font(.system(size: NotchStyle.captionFontSize))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Уход в Obsidian стоит у всякой заметки, у которой там есть
            // файл, — и у своих тоже: своя заметка лежит в хранилище ровно
            // так же, и открыть её там бывает нужно не реже.
            if isInVault(note) {
                Button(action: { onOpenInObsidian(note) }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: NotchStyle.font(9), weight: .semibold))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(t("Открыть в Obsidian"))
            }

            // У заметки хранилища крестика нет: удалять чужой файл из выреза
            // человек не просил, а править её всё равно можно только
            // в Obsidian.
            if !note.isReadOnly {
                Button(action: { onDelete(note) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: NotchStyle.font(9), weight: .semibold))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(t("Удалить заметку"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .fill(.white.opacity(NotchStyle.tileFill))
        )
        // Форма попаданий задана явно: без неё нажимается только по буквам,
        // а не по всей строке. Снимок этого не показывает — зоны попадания
        // на нём не видно.
        .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        .onTapGesture { onOpen(note) }
        // Своё имя у строки уже есть — её текст. Подменять его действием
        // было бы порчей: диктор произносил бы «Открыть заметку» одинаково
        // для всех строк подряд.
        .notchActionHint(note.isReadOnly ? t("Открыть в Obsidian") : t("Открыть на правку"))
    }
}
