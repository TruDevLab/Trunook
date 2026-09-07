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
    /// Проигрыватель записей. Ссылкой, а не признаком: строка обязана
    /// перерисоваться, когда запись доиграет сама.
    @ObservedObject var player: RecordingPlayer
    /// Пустить или остановить запись заметки.
    let onPlayRecording: (Note) -> Void
    let onExportAll: () -> Void
    /// Перейти к созданию заметки. Из списка это первое, чего хочется:
    /// пришёл посмотреть записанное — и вспомнил, что записать ещё.
    ///
    /// Строкой передаётся затравка — то, что уже набрано в поиске. Пустая
    /// строка означает чистый лист.
    let onNewNote: (String) -> Void
    let onClose: () -> Void

    // MARK: - Размеры

    private static var minimumWidth: CGFloat { NotchStyle.scaled(440) }

    /// Ширина считается от чёлки, а не берётся числом: в крыле две кнопки,
    /// а ширина крыла у каждой модели MacBook своя.
    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: 2),
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

    /// Высота кнопки «Новая заметка».
    static var newNoteHeight: CGFloat { NotchStyle.scaled(32) }
    /// Полоса, которую кнопка занимает внизу списка вместе с зазором.
    static var newNoteBand: CGFloat { newNoteHeight + rowSpacing }

    /// Высота списка вместе с полосой кнопки.
    ///
    /// Кнопка лежит **поверх** списка, а не под ним, и от этого зависит,
    /// прибавлять ли её полосу к высоте.
    ///
    /// Пока строк меньше, чем помещается, прибавлять надо: иначе стекло легло
    /// бы на единственную строку и закрыло её целиком — при том, что места
    /// на экране сколько угодно. Как только список перерос окно, прибавлять
    /// нечего: последние строки уходят под стекло, видны сквозь него
    /// и достаются прокруткой. Высота панели на полном списке от кнопки
    /// не меняется вовсе — а полный список и есть обычный случай.
    static func listHeight(rows: Int) -> CGFloat {
        let shown = max(1, min(rows, visibleRows))
        let stack = CGFloat(shown) * rowHeight + CGFloat(shown - 1) * rowSpacing
        return rows < visibleRows ? stack + newNoteBand : stack
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
                // Новой заметки здесь больше нет: она стоит большой кнопкой
                // внизу списка. Два способа одного действия на одном экране
                // человек читает как два разных.
                NotchPanelButton(
                    symbol: "square.and.arrow.up",
                    hint: t("Выгрузить все заметки в папку"),
                    action: onExportAll
                )
                // Выгружать нечего, пока заметок нет. Крестик от этого
                // не гаснет: закрыть панель нужно в любом случае.
                .disabled(notes.total == 0)
                .opacity(notes.total == 0 ? 0.5 : 1)

                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                search
                listArea
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
                onSubmit: submitSearch
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

    /// Enter в поиске, когда искомого нет.
    ///
    /// Искать заметку и не найти её — самый частый повод её завести: человек
    /// уже сформулировал, о чём она, и набрал это в строке. Заставлять его
    /// после этого нажимать кнопку и набирать то же самое второй раз незачем.
    ///
    /// Когда что-то нашлось, Enter не делает ничего: заводить рядом вторую
    /// заметку с тем же именем — не то, чего от него ждут.
    private func submitSearch() {
        let query = notes.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, notes.notes.isEmpty else { return }
        onNewNote(query)
    }

    // MARK: - Пустые состояния

    /// Их два, и это разные слова. «Заметок нет» объясняет, что делать;
    /// «ничего не нашлось» объясняет, что искали не то. Одна строка на оба
    /// случая врала бы в одном из них.
    private var empty: some View {
        VStack(spacing: 0) {
            message
            // Полоса кнопки — не место для объяснения: стекло легло ровно
            // на середину строки, и половина слов пропала. Видно это было
            // только на снимке: в вёрстке оба вида законны, они просто
            // лежат в одном прямоугольнике.
            Color.clear.frame(height: Self.newNoteBand)
        }
    }

    private var message: some View {
        VStack(spacing: 4) {
            Image(systemName: notes.isSearching ? "magnifyingglass" : "square.and.pencil")
                .font(.system(size: NotchStyle.font(18)))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .accessibilityHidden(true)
            Text(notes.isSearching
                ? t("Ничего не нашлось — Enter заведёт заметку с этим текстом")
                : t("Заметок пока нет — начните новую кнопкой снизу"))
                .font(.system(size: NotchStyle.font(11.5)))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Список

    /// Список и лежащая на нём кнопка.
    ///
    /// Высоту задаёт эта обёртка, а не содержимое: панель, размер которой
    /// определяет содержимое, растит `ZStack` и вылезает вверх поверх
    /// соседей — на этом в проекте ловились уже дважды.
    private var listArea: some View {
        ZStack(alignment: .bottom) {
            if notes.notes.isEmpty {
                empty
            } else {
                list
            }
            newNoteButton
        }
        .frame(height: Self.listHeight(rows: notes.notes.count))
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.rowSpacing) {
                ForEach(notes.notes) { note in
                    row(note)
                }
                // Место под кнопкой в самой прокрутке: без него последняя
                // строка остаётся под стеклом навсегда, и добраться до её
                // крестика нечем.
                Color.clear.frame(height: Self.newNoteBand)
            }
        }
        // Строки растворяются, уходя под кнопку, а не обрываются под ней
        // ровным краем: обрубленный список читается обрезанной вёрсткой.
        .mask(listFade)
    }

    private var listFade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: 1 - Self.newNoteBand / Self.listHeight(rows: notes.notes.count)),
                // Не до нуля: кнопка теперь круг в середине, и строка
                // под ней закрыта не вся. Растворять её целиком значило бы
                // прятать то, что прекрасно видно рядом с кнопкой.
                .init(color: .black.opacity(0.4), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Новая заметка

    /// Главное действие списка — большой кнопкой внизу, поверх строк.
    ///
    /// Раньше оно стояло значком в крыле, вторым из трёх, и там его надо было
    /// сперва найти: крыло — это место закрытия и настроек, а не начала
    /// работы. Внизу списка кнопка попадается на глаза ровно тогда, когда
    /// человек дочитал список и не нашёл того, что искал.
    ///
    /// **Один плюс, без подписи.** Подпись жила в самой кнопке и делала
    /// её широкой полосой поперёк списка: круг того же роста закрывает вчетверо
    /// меньше строк под собой, а сказать «Новая заметка» есть чем — всплывающая
    /// подпись под чёлкой, ровно как у всех кнопок без слов в этом приложении.
    ///
    /// **Стекло обычной кнопки, а не цветное.** Цветное стекло здесь пробовали:
    /// оно не пускает сквозь себя строки, и кнопка выходила наклейкой поверх
    /// списка вместо стекла над ним. Цвет остался у оттенка стекла.
    ///
    /// **Кнопку держит кольцо, а не плотность.** Первый заход был прозрачным
    /// целиком — и кнопка перестала быть кнопкой: зелёный плюс сел прямо
    /// на текст строки и прочитался значком строки, а не действием. Обводка
    /// в одну точку очерчивает круг, ничего не закрывая; плюс от неё стал
    /// белым — зелёный на зелёном значке заметки не различался.
    private var newNoteButton: some View {
        NotchTile(
            id: "notes-new",
            radius: Self.newNoteHeight / 2,
            role: .tile,
            tint: Palette.notes
        ) {
            Button(action: { onNewNote("") }) {
                Image(systemName: "plus")
                    .font(.system(size: NotchStyle.font(16), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Self.newNoteHeight, height: Self.newNoteHeight)
                    .background(Circle().fill(.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Новая заметка"))
        }
        .fixedSize()
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

            // Запись — первой из кнопок строки: её слушают вместо того,
            // чтобы читать заметку, и это самое частое, зачем к такой
            // заметке возвращаются.
            if note.hasAudio {
                Button(action: { onPlayRecording(note) }) {
                    Image(systemName: player.isPlaying(note.id) ? "stop.fill" : "play.fill")
                        .font(.system(size: NotchStyle.font(9), weight: .semibold))
                        .foregroundStyle(
                            player.isPlaying(note.id)
                                ? Palette.notes
                                : .white.opacity(NotchStyle.secondaryOpacity)
                        )
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(player.isPlaying(note.id) ? t("Остановить") : t("Прослушать запись"))
            }

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
