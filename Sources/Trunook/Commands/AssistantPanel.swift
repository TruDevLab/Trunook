import SwiftUI
import AppKit

/// Панель модели и заметок — с переключателем режима под полем ввода.
///
/// Режимы, а не одно поле на две работы. Одно поле пробовали: набранное можно
/// было отправить модели или сохранить заметкой, и выбор делался кнопкой уже
/// после набора. Хуже — потому что от выбора зависит **само поле**. Вопросу
/// нужна одна строка и отправка по Enter, заметке — несколько строк, где Enter
/// переводит строку. В одном поле это не сходится: либо вопрос не отправить
/// клавишей, либо заметку не набрать в два абзаца.
///
/// Отсюда и остальное: в режиме ИИ есть область ответа и поиск по заметкам,
/// в режиме заметки — ни того ни другого, зато оформление и высокое поле.
///
/// Все мелкие кнопки — одни значки, без подписей: подпись показывает плашка
/// под чёлкой, там пусто в любом состоянии выреза. Главное действие каждого
/// режима — наоборот, широкая овальная кнопка с подписью: она одна, её ищут
/// глазами, и значок рядом с тремя такими же значками её не выделяет.
struct AssistantPanel: View {
    @ObservedObject var session: AssistantSession
    @ObservedObject var draft: NoteDraft
    @ObservedObject var flash: PanelFlash
    let metrics: NotchMetrics
    /// Модель включена. Без неё панель остаётся местом для заметок: набрать
    /// и сохранить можно и так, а кнопки, которым нечего делать, прячутся.
    let modelEnabled: Bool
    let notesEnabled: Bool

    let onSend: () -> Void
    let onSaveNote: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onSaveAnswer: () -> Void
    let onOpenNotes: () -> Void
    let onToggleNotesSearch: () -> Void
    let onSelectMode: (NotePanelMode) -> Void
    let onClose: () -> Void

    // MARK: - Размеры

    /// Наименьшая ширина. Ниже неё ответ модели читается в три слова
    /// на строку.
    private static var minimumWidth: CGFloat { NotchStyle.scaled(480) }

    /// Ширина панели.
    ///
    /// Не число, а расчёт: в крыле две кнопки, а само крыло зависит
    /// от ширины чёлки — у каждой модели MacBook она своя. Подобранное
    /// на одной машине число обрезало бы последнюю кнопку на другой;
    /// телесуфлер на этом уже ловили.
    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: 2),
                notchWidth: notchWidth,
                bodyPadding: bodyPadding
            )
        )
    }

    /// Сторона кнопки-значка. Норма для указательного ввода — 24 точки.
    static var actionSize: CGFloat { max(24, NotchStyle.scaled(24)) }
    /// Высота полосы с главным действием. Выше значка: главную кнопку
    /// увеличили нарочно, а полоса равняется по самому высокому в ней.
    static var rowHeight: CGFloat { NotchStyle.scaled(30) }
    /// Однострочное поле вопроса.
    static var questionHeight: CGFloat { NotchStyle.scaled(28) }

    /// Поле вокруг текста в поле заметки. Наружу — по нему выравнивается
    /// подсказка пустого поля.
    static let fieldInset = CGSize(width: 10, height: 6)

    /// Высота поля заметки.
    ///
    /// Восемь строк: области ответа в этом режиме нет вовсе, и место, которое
    /// она занимала, уходит туда, ради чего режим и заведён. Не больше:
    /// панель висит под чёлкой, и под ней продолжают работать.
    static var noteFieldHeight: CGFloat {
        NotchStyle.scaled(8 * 17) + 2 * fieldInset.height
    }

    /// Потолок области ответа: дальше она прокручивается.
    static let maxBodyHeight: CGFloat = 168

    /// Зазор между строками ответа. Он же стоит в самой вёрстке — иначе
    /// расчёт и рисунок разойдутся.
    static let lineSpacing: CGFloat = 3

    /// Высота одной строки ответа.
    ///
    /// Считается из шрифта, а не выписана числом. Числом она и была — 15
    /// точек при кегле 12, — и это на две с половиной точки меньше
    /// настоящей: панель выходила короче своего содержимого, и последняя
    /// строка ответа обрезалась пополам.
    static var lineHeight: CGFloat {
        ceil(answerFont.ascender - answerFont.descender + answerFont.leading) + lineSpacing
    }

    /// Поле от чёрного тела панели — одинаковое слева, справа и снизу.
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    static let answerFont = NSFont.systemFont(ofSize: 12)

    /// Высота области ответа.
    ///
    /// Пока идёт поток — во всю доступную: панель, подраставшая на каждой
    /// новой строке, дёргала бы вырез десяток раз за ответ. Когда поток
    /// закончился, панель садится по содержимому — одним движением.
    static func bodyHeight(answer: String, isStreaming: Bool, notchWidth: CGFloat) -> CGFloat {
        guard !isStreaming else { return maxBodyHeight }
        guard !answer.isEmpty else { return lineHeight * 2 }

        // Замеряем текст без разметки: звёздочки и решётки на экран
        // не попадают, а ширину строки заметно меняют.
        let available = width(notchWidth: notchWidth) - 2 * (bodyPadding + NotchStyle.shoulderInset)
        let rows = MarkdownRender.plain(answer)
            .components(separatedBy: "\n")
            .reduce(0) { total, line in
                let measured = TextMeasure.width(line, font: answerFont)
                return total + max(1, Int(ceil(measured / available)))
            }
        return min(maxBodyHeight, max(lineHeight * 2, CGFloat(rows) * lineHeight))
    }

    static func height(
        notchHeight: CGFloat,
        notchWidth: CGFloat,
        mode: NotePanelMode = .model,
        answer: String = "",
        isStreaming: Bool = true
    ) -> CGFloat {
        var content: CGFloat
        switch mode {
        case .model:
            content = bodyHeight(answer: answer, isStreaming: isStreaming, notchWidth: notchWidth)
            // Строка действий над ответом появляется только вместе с ответом:
            // держать её пустой значило бы отнимать высоту у самого ответа.
            if !answer.isEmpty || isStreaming {
                content += NotchStyle.gridSpacing + actionSize
            }
            content += NotchStyle.gridSpacing + questionHeight
        case .note:
            content = noteFieldHeight
        }
        content += NotchStyle.gridSpacing + rowHeight
        return NotchStyle.height(notchHeight: notchHeight, contentHeight: content)
    }

    // MARK: - Тело

    private var isNote: Bool { draft.mode == .note }
    private var hasAnswer: Bool { !session.answer.isEmpty || session.isStreaming }
    private var isEditingNote: Bool { draft.editingID != nil }

    var body: some View {
        NotchPanel(
            metrics: metrics,
            width: Self.width(notchWidth: metrics.notchWidth),
            bodyPadding: Self.bodyPadding
        ) {
            header
        } trailing: {
            HStack(spacing: 2) {
                if notesEnabled {
                    NotchPanelButton(
                        symbol: "list.bullet.rectangle",
                        hint: t("Список заметок"),
                        action: onOpenNotes
                    )
                }
                // Крестик — общий для всех накладок и всегда последний
                // в крыле: где бы человек ни находился, закрывается панель
                // одинаково и в одном и том же месте.
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(alignment: .leading, spacing: NotchStyle.gridSpacing) {
                if isNote {
                    noteField
                } else {
                    answerBody
                    if hasAnswer { answerActions }
                    questionField
                }
                switch draft.prompt {
                case .link: linkRow
                case nil: actionRow
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            NotchPanelTitle(
                symbol: isNote ? draft.mode.symbol : "sparkles",
                title: headerTitle,
                tint: Palette.assistant
            )
            // Пока идёт поток — вертушка рядом с названием: она
            // и объясняет, почему панель пуста.
            if session.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
            }
        }
    }

    /// Название говорит, что случится с набранным.
    ///
    /// Правка заметки важнее всего остального: это единственное состояние,
    /// в котором сохранение не заводит новую запись, а переписывает
    /// существующую, — и не сказать об этом значило бы дать человеку
    /// потерять её содержимое, думая, что он пишет новую.
    private var headerTitle: String {
        if isNote { return isEditingNote ? t("Правка заметки") : t("Новая заметка") }
        return session.title.isEmpty ? t("Модель") : session.title
    }

    // MARK: - Ответ

    private var emptyText: String {
        if session.isStreaming { return t("Модель думает…") }
        if !modelEnabled { return t("Модель выключена — переключитесь на заметку") }
        return session.hasNoConversation ? t("Ответ появится здесь") : ""
    }

    private var answerBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Self.lineSpacing) {
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: NotchStyle.font(11.5)))
                            .foregroundStyle(.orange)
                    }
                    if session.answer.isEmpty {
                        Text(emptyText)
                            .font(.system(size: NotchStyle.font(12)))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(MarkdownRender.lines(from: session.answer)) { line in
                            markdownLine(line)
                        }
                    }
                    // Якорь для прокрутки: следим за хвостом, а не за всем
                    // текстом — иначе рывок на каждом слове.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
            }
            .frame(height: Self.bodyHeight(
                answer: session.answer,
                isStreaming: session.isStreaming,
                notchWidth: metrics.notchWidth
            ))
            .onChange(of: session.answer) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private static let bottomAnchor = "assistant-bottom"

    @ViewBuilder
    private func markdownLine(_ line: MarkdownRender.Line) -> some View {
        switch line.kind {
        case .rule:
            Divider().overlay(.white.opacity(0.15))

        case let .heading(level):
            Text(line.text)
                .font(.system(size: level == 1 ? 13.5 : 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .item(marker):
            // Маркер в колонке постоянной ширины, текст — своей: иначе
            // перенос длинного пункта уезжает под сам маркер и список
            // перестаёт читаться списком.
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .frame(width: 14, alignment: .trailing)
                Text(line.text)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 2)
                Text(line.text)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code:
            Text(line.text)
                .font(.system(size: NotchStyle.font(11), design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                        .fill(.white.opacity(0.07))
                )

        case .paragraph where line.plain.isEmpty:
            // Пустая строка разделяет абзацы. Пустой `Text` занял бы целую
            // строку — здесь хватает узкого просвета.
            Color.clear.frame(height: 4)

        case .paragraph:
            Text(line.text)
                .font(.system(size: NotchStyle.font(12)))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var answerActions: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            icon("doc.on.doc", t("Скопировать ответ"), action: onCopy)
            icon("text.insert", t("Вставить ответ"), action: onPaste)
            if notesEnabled {
                icon(
                    "tray.and.arrow.down",
                    t("Ответ в заметки"),
                    tint: Palette.assistant,
                    action: onSaveAnswer
                )
            }
        }
        .frame(height: Self.actionSize)
        // Пока ответа нет, действовать не с чем.
        .disabled(session.answer.isEmpty)
        .opacity(session.answer.isEmpty ? 0.4 : 1)
    }

    // MARK: - Поля ввода

    /// Вопрос — одной строкой, и отправляется он Enter'ом.
    private var questionField: some View {
        FocusedTextField(
            text: Binding(get: { draft.question }, set: { draft.question = $0 }),
            placeholder: session.usesNotes ? t("Спросите по заметкам") : t("Спросите модель"),
            onSubmit: onSend
        )
        .padding(.horizontal, 12)
        .frame(height: Self.questionHeight)
        // Капсула обычная, не `.continuous`: у сглаженной обводка торца
        // рвётся — дуга не доходит до края, и слева остаётся отдельный
        // вертикальный огрызок.
        .background(
            Capsule()
                .fill(.white.opacity(NotchStyle.tileFill))
                .overlay(
                    Capsule().strokeBorder(
                        .white.opacity(NotchStyle.dense(0.12)),
                        lineWidth: 1
                    )
                )
        )
        .overlay(alignment: .trailing) { flashPill }
    }

    /// Заметка — многострочно, с оформлением.
    private var noteField: some View {
        RichTextView(
            editor: draft.editor,
            inset: Self.fieldInset,
            onChange: draft.textDidChange,
            onPaste: draft.didPaste,
            onAttach: draft.attach
        )
        .frame(height: Self.noteFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous)
                .fill(.white.opacity(NotchButtonStyle.restingFill))
        )
        // Пустое поле — это пустой прямоугольник с курсором, и по нему
        // не видно ни что сюда кладут, ни что будет дальше. Отступы и кегль
        // берутся из самого поля, а не выписаны заново: порознь они
        // разъезжались — подсказка вставала левее текста и была мельче.
        .overlay(alignment: .topLeading) {
            if draft.isNoteEmpty {
                Text(isEditingNote ? t("Правьте заметку") : t("Наберите заметку"))
                    .font(.system(size: Note.bodyFontSize))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, Self.fieldInset.width)
                    .padding(.vertical, Self.fieldInset.height)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) { flashPill }
    }

    /// Подтверждение поверх поля, а не вместо полосы действий.
    ///
    /// Вместо полосы — значит на полторы секунды убрать переключатель режима
    /// и главную кнопку; поверх поля — ничего не двигается, а не заметить всё
    /// равно нельзя. Обычные плашки событий сюда не годятся вовсе: накладка
    /// важнее плашки по расчёту состояния, и из-под открытой панели её
    /// не видно.
    @ViewBuilder
    private var flashPill: some View {
        if let text = flash.text {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: NotchStyle.font(10), weight: .semibold))
                Text(text)
                    .font(.system(size: NotchStyle.font(11), weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.positive)
            .padding(.horizontal, 9)
            .frame(height: NotchStyle.scaled(22))
            .background(Capsule().fill(.black.opacity(0.82)))
            .overlay(Capsule().strokeBorder(Palette.positive.opacity(0.35), lineWidth: 0.5))
            .padding(6)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Полоса действий

    /// Зазор внутри полосы действий. Наружу — по нему считается остаток
    /// под главную кнопку, и это же число проверяется тестом.
    static let actionSpacing: CGFloat = 6

    /// Сколько останется главной кнопке при самой тесной раскладке —
    /// в режиме заметки, где рядом ещё четыре кнопки оформления.
    static func primaryWidth(notchWidth: CGFloat) -> CGFloat {
        let available = width(notchWidth: notchWidth) - 2 * (bodyPadding + NotchStyle.shoulderInset)
        let formatting = 4 * actionSize + 3 * actionSpacing
        return available - ModeSwitch.width - formatting - 2 * actionSpacing
    }

    /// Ширина кнопки отправки в разговоре.
    ///
    /// Половина того, что осталось от строки: растянутая по всему остатку,
    /// она выходила вдвое шире кнопки заметки при вдвое меньшем поводе —
    /// в разговоре рядом с ней нет ни одной другой кнопки, и заполнять
    /// собой всю строку ей незачем.
    static func sendWidth(notchWidth: CGFloat) -> CGFloat {
        let available = width(notchWidth: notchWidth) - 2 * (bodyPadding + NotchStyle.shoulderInset)
        return (available - ModeSwitch.width - actionSpacing) / 2
    }

    /// Что остаётся под зазор в полосе разговора.
    ///
    /// В ней три вещи постоянной ширины: переключатель режима, значок поиска
    /// по заметкам и кнопка отправки. Остаток уходит в распорку между
    /// режимом и парой справа — и он обязан быть положительным.
    static func conversationSlack(notchWidth: CGFloat) -> CGFloat {
        let available = width(notchWidth: notchWidth) - 2 * (bodyPadding + NotchStyle.shoulderInset)
        return available - ModeSwitch.width - actionSize - sendWidth(notchWidth: notchWidth)
            - 2 * actionSpacing
    }

    private var actionRow: some View {
        HStack(spacing: Self.actionSpacing) {
            if modelEnabled, notesEnabled {
                ModeSwitch(mode: draft.mode, onSelect: onSelectMode)
            }
            if isNote {
                // Оформление правит абзац под курсором. В пустом поле абзаца
                // нет, и кнопки не делают ровно ничего — а нажатие без ответа
                // человек читает как поломку, а не как «пока рано».
                Group {
                    icon("textformat.size.larger", t("Заголовок"), action: draft.toggleHeading)
                    icon("bold", t("Полужирный"), action: draft.toggleBold)
                    icon("italic", t("Курсив"), action: draft.toggleItalic)
                    icon("link", t("Ссылка"), action: draft.askForLink)
                }
                .disabled(draft.isNoteEmpty)
                .opacity(draft.isNoteEmpty ? 0.4 : 1)
            }
            primaryAction
        }
        .frame(height: Self.rowHeight)
    }

    /// Главное действие режима: одна широкая овальная кнопка с подписью.
    ///
    /// Не значок в ряду значков: она одна на весь режим, её ищут глазами,
    /// и среди четырёх одинаковых кружков она терялась. Растянута по остатку
    /// строки — так в неё невозможно не попасть.
    @ViewBuilder
    private var primaryAction: some View {
        if isNote {
            if notesEnabled {
                wideAction(
                    symbol: isEditingNote ? "checkmark.circle.fill" : "square.and.pencil",
                    title: isEditingNote ? t("Сохранить") : t("В заметки"),
                    isEnabled: !draft.isNoteEmpty,
                    action: onSaveNote
                )
            }
        } else if modelEnabled {
            // Распорка: пара справа прижата к краю, переключатель режима —
            // к левому. Растянутая на весь остаток кнопка читалась полосой.
            Spacer(minLength: 0)
            if notesEnabled {
                NotesSearchToggle(isOn: session.usesNotes, action: onToggleNotesSearch)
            }
            // Подпись всегда одна и та же. Была разная — «Спросить
            // по заметкам» при включённом поиске, — и она не помещалась,
            // обрываясь на «Спросить по зам…». Режим и так виден соседней
            // кнопкой, повторять его на отправке незачем.
            wideAction(
                symbol: "arrow.up.circle.fill",
                title: t("Отправить"),
                isEnabled: !draft.isEmpty && !session.isStreaming,
                action: onSend
            )
            .frame(width: Self.sendWidth(notchWidth: metrics.notchWidth))
        }
    }

    private func wideAction(
        symbol: String,
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: NotchStyle.font(12), weight: .semibold))
                Text(title)
                    .font(.system(size: NotchStyle.font(12), weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Self.rowHeight)
            .background(
                Capsule().fill(
                    Palette.assistant.opacity(isEnabled ? NotchStyle.dense(0.85) : 0.25)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .notchHint(title)
    }

    /// Строка адреса ссылки — вместо всплывающего окна.
    ///
    /// Окно система ставит по центру экрана, то есть ровно под чёлкой,
    /// и панель его закрывает: диалог есть, а увидеть его нельзя.
    private var linkRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                .foregroundStyle(Palette.assistant)
                .accessibilityHidden(true)
            FocusedTextField(
                text: Binding(get: { draft.linkAddress }, set: { draft.linkAddress = $0 }),
                placeholder: "https://",
                onSubmit: draft.confirmLink
            )
            .accessibilityLabel(t("Адрес ссылки"))
            .padding(.horizontal, 8)
            .frame(height: Self.actionSize)
            .background(Capsule().fill(.white.opacity(NotchStyle.tileFill)))

            icon("checkmark", t("Применить"), tint: Palette.assistant, action: draft.confirmLink)
            icon("xmark", t("Отмена"), action: draft.cancelPrompt)
        }
        .frame(height: Self.rowHeight)
    }

    // MARK: - Кнопка-значок

    /// Кнопка без подписи: подпись показывает плашка под чёлкой, имя
    /// для диктора берётся из той же строки.
    ///
    /// Подпись обязательна — она параметр, а не необязательный довесок.
    /// Пустая строка в `notchHint` не просто ничего не добавляет: она
    /// перекрывает имя, которое SwiftUI вывел бы из названия символа,
    /// и диктор говорит «кнопка» и умолкает.
    private func icon(
        _ symbol: String,
        _ hint: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.actionSize, height: Self.actionSize)
                .background(Circle().fill(.white.opacity(NotchStyle.tileFill)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint)
    }
}

/// Переключатель режима панели.
///
/// Своей вёрсткой, а не системным сегментированным `Picker`: тот приносит
/// в вырез системный материал и системную синеву — единственное место, где
/// они вообще появились бы.
struct ModeSwitch: View {
    let mode: NotePanelMode
    let onSelect: (NotePanelMode) -> Void

    /// Сегмент постоянной ширины, а не по содержимому.
    ///
    /// По содержимому переключатель менял бы ширину вместе с языком —
    /// и на китайском оставлял бы главной кнопке на семьдесят точек больше,
    /// чем на русском. Ширину полосы действий надо знать заранее, иначе
    /// её нечем проверить.
    static var segmentWidth: CGFloat { NotchStyle.scaled(92) }
    static var segmentHeight: CGFloat { NotchStyle.scaled(22) }
    private static let padding: CGFloat = 2
    private static let spacing: CGFloat = 2

    /// Ширина переключателя целиком — её знает и полоса действий, и проверка.
    static var width: CGFloat {
        CGFloat(NotePanelMode.allCases.count) * segmentWidth
            + CGFloat(NotePanelMode.allCases.count - 1) * spacing
            + 2 * padding
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(NotePanelMode.allCases) { item in
                segment(item)
            }
        }
        .padding(Self.padding)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(NotchStyle.dense(0.10)), lineWidth: 1))
        .fixedSize()
        .animation(.easeOut(duration: 0.12), value: mode)
    }

    private func segment(_ item: NotePanelMode) -> some View {
        let isOn = item == mode
        return Button(action: { onSelect(item) }) {
            HStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: NotchStyle.font(9.5), weight: .semibold))
                Text(item.title)
                    .font(.system(size: NotchStyle.font(11), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isOn ? .white : .white.opacity(NotchStyle.secondaryOpacity))
            .frame(width: Self.segmentWidth, height: Self.segmentHeight)
            .background(
                Capsule().fill(Palette.assistant.opacity(isOn ? NotchStyle.dense(0.75) : 0))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        // Имя постоянное, состояние — отдельным значением: меняющееся имя
        // диктор прочтёт как другую кнопку, а не как ту же в другом состоянии.
        .accessibilityLabel(item.title)
        .accessibilityValue(isOn ? t("выбрано") : "")
    }
}

/// Переключатель «искать в заметках».
///
/// Стоит в нижней полосе, вплотную к кнопке отправки: от него зависит,
/// откуда придёт ответ — из заметок или из общих знаний модели, — и решают
/// это ровно в тот момент, когда собираются отправлять.
///
/// Одним значком, без подписи: подпись показывает плашка под чёлкой, где
/// помещается целая фраза, а в полосе рядом с переключателем режима
/// и кнопкой отправки два слова отняли бы место у обоих.
///
/// Включённое состояние — цветом и заливкой. Имя для диктора при этом
/// постоянное, состояние идёт отдельным значением: меняющееся имя он
/// прочтёт как другую кнопку, а не как ту же в другом состоянии.
struct NotesSearchToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(isOn ? .white : .white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: AssistantPanel.actionSize, height: AssistantPanel.actionSize)
                .background(
                    Circle().fill(
                        isOn
                            ? Palette.assistant.opacity(NotchStyle.dense(0.85))
                            : .white.opacity(NotchStyle.tileFill)
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(
            t("Найти в заметках"),
            bubble: isOn
                ? t("Ответ ищется в заметках — нажмите, чтобы спрашивать как обычно")
                : t("Найти в заметках")
        )
        .accessibilityValue(isOn ? t("включено") : t("выключено"))
        .animation(.easeOut(duration: 0.12), value: isOn)
    }
}
