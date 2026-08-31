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
    /// Команды, которые показывает список. Пустой — списка нет вовсе:
    /// команды выключены в настройках.
    let commands: [QuickCommand]
    /// Установленные модели и та, что выбрана в настройках, — для правой
    /// части строки команды.
    let models: [ModelRef]
    let defaultModel: ModelRef

    let onSend: () -> Void
    /// Запустить команду из списка.
    let onRunCommand: (QuickCommand) -> Void
    /// Убрать захваченный текст.
    let onClearCapture: () -> Void
    /// Раскрыть или свернуть плашку захваченного текста.
    let onToggleCapture: () -> Void
    /// Открыть выбор модели для команды и выбрать её.
    let onBeginChoosingModel: (QuickCommand) -> Void
    let onChooseModel: (String?) -> Void
    let onCancelChoosingModel: () -> Void
    /// Клавиатура в поле вопроса: стрелки ведут подсветку по списку команд,
    /// Tab меняет модель подсвеченной, Esc снимает подсветку. Каждое отвечает,
    /// забрало ли оно нажатие себе.
    let onMoveHighlight: (Int) -> Bool
    /// ← и → ведут подсветку по действиям с готовым ответом.
    let onMoveAnswerAction: (Int) -> Bool
    let onCycleModel: () -> Bool
    let onEscapeHighlight: () -> Bool
    let onSaveNote: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onSaveAnswer: () -> Void
    let onOpenNotes: () -> Void
    let onToggleNotesSearch: () -> Void
    let onSelectMode: (NotePanelMode) -> Void
    let onClose: () -> Void
    /// Оборвать голосовой заход. Кнопка нужна и здесь, а не только
    /// в мини-виде: панель важнее мини-вида по расчёту состояния и просто
    /// занимает его место — открыв разговор глазами, оборвать его стало бы
    /// нечем.
    let onStopVoice: () -> Void
    /// Чем занят голосовой заход прямо сейчас. `nil` — заход не идёт.
    let voicePhase: VoiceSession.Phase?

    // MARK: - Размеры

    /// Наименьшая ширина. Ниже неё ответ модели читается в три слова
    /// на строку.
    private static var minimumWidth: CGFloat { NotchStyle.scaled(480) }

    /// Сколько кнопок бывает в крыле разом.
    ///
    /// Три, а не две: к списку заметок и крестику добавилась остановка
    /// голоса. Считается по самому полному составу, а не по обычному —
    /// панель, рассчитанная на два значка, обрезала бы третий ровно тогда,
    /// когда он и нужен.
    static let wingButtons = 3

    /// Ширина панели.
    ///
    /// Не число, а расчёт: крыло зависит от ширины чёлки — у каждой модели
    /// MacBook она своя. Подобранное на одной машине число обрезало бы
    /// последнюю кнопку на другой; телесуфлер на этом уже ловили.
    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: wingButtons),
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

    /// Сколько остаётся тексту вопроса после полей самого поля.
    ///
    /// Наружу — потому что по этой ширине считается высота поля, а считает
    /// её `GrowingTextField`, которому о панели ничего не известно.
    static func questionTextWidth(notchWidth: CGFloat) -> CGFloat {
        width(notchWidth: notchWidth)
            - 2 * (bodyPadding + NotchStyle.shoulderInset)
            - 2 * GrowingTextField.inset.width
    }

    /// Высота поля вопроса под набранный текст.
    ///
    /// Поле было однострочным, и текст, переросший строку, дальше
    /// не набирался вовсе: он уезжал за правый край, а поле стояло на месте.
    /// Теперь оно растёт вместе с текстом — а раз растёт оно, растёт и панель,
    /// поэтому высота считается тем же расчётом, что спрашивает окно.
    static func questionHeight(text: String, notchWidth: CGFloat) -> CGFloat {
        GrowingTextField.height(
            for: text,
            textWidth: questionTextWidth(notchWidth: notchWidth)
        )
    }

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

    /// Насколько реплика человека у́же полосы: она в капсуле, прижатой
    /// к правому краю, и во всю ширину не растягивается — иначе перестала бы
    /// отличаться от ответа.
    static let userReplyInset: CGFloat = 44

    /// Зазор между репликами. Крупнее межстрочного: по нему лента и читается
    /// лентой, а не сплошным текстом.
    static let replySpacing: CGFloat = 8

    /// Высота ленты переписки.
    ///
    /// Пока идёт поток — во всю доступную: панель, подраставшая на каждой
    /// новой строке, дёргала бы вырез десяток раз за ответ. Когда поток
    /// закончился, панель садится по содержимому — одним движением.
    static func bodyHeight(
        transcript: [AssistantSession.Reply],
        isStreaming: Bool,
        notchWidth: CGFloat
    ) -> CGFloat {
        guard !isStreaming else { return maxBodyHeight }
        guard !transcript.isEmpty else { return lineHeight * 2 }

        let available = width(notchWidth: notchWidth) - 2 * (bodyPadding + NotchStyle.shoulderInset)
        var total: CGFloat = 0
        for reply in transcript {
            switch reply.role {
            // Реплика человека у́же: она в капсуле у правого края.
            case .user:
                total += userReplyHeight(reply.text, available: available - userReplyInset)
            case .assistant:
                total += answerReplyHeight(reply.text, available: available)
            }
        }
        total += CGFloat(max(0, transcript.count - 1)) * replySpacing
        return min(maxBodyHeight, max(lineHeight * 2, total))
    }

    /// Просвет на месте пустой строки разметки.
    ///
    /// Столько же, сколько рисует сама вёрстка: пустой абзац там не строка
    /// текста, а узкий зазор. Считать его полной строкой значило бы отмерить
    /// панели лишнего — и под лентой открылась бы пустая полоса тем шире,
    /// чем больше в ответе абзацев.
    static let blankLineHeight: CGFloat = 4 + lineSpacing

    /// Поле внутри капсулы своей реплики. Наружу — потому что по нему же
    /// считается её высота: выписанное в двух местах порознь, оно разошлось
    /// бы, и реплика обрезалась бы снизу.
    static let userReplyPadding = CGSize(width: 10, height: 5)

    /// Колонка маркера в пункте списка: сама колонка и зазор до текста.
    ///
    /// Тексту пункта достаётся меньше ширины, чем абзацу, — а значит он
    /// переносится раньше. Не учесть это значило бы недосчитать строку
    /// ровно у длинных пунктов, то есть у тех, где перенос и случается.
    static let markerColumn: CGFloat = 14 + 6

    /// Высота реплики человека.
    ///
    /// Она лежит в капсуле, и поля капсулы — это высота сверх текста.
    /// Считать её как голый текст значило бы недомерить десяток точек,
    /// а вся лента от этого съезжает вверх и обрезается снизу.
    static func userReplyHeight(_ text: String, available: CGFloat) -> CGFloat {
        guard available > 0 else { return lineHeight }
        let inner = available - 2 * userReplyPadding.width
        let measured = TextMeasure.width(text, font: answerFont)
        let rows = max(1, Int(ceil(measured / max(1, inner))))
        return CGFloat(rows) * lineHeight + 2 * userReplyPadding.height
    }

    /// Высота ответа модели.
    ///
    /// Считается по разобранной разметке, а не по голому тексту: у пункта
    /// списка своя ширина, у пустой строки — свой узкий просвет, и оба
    /// расходятся с «строка есть строка» в разные стороны.
    static func answerReplyHeight(_ text: String, available: CGFloat) -> CGFloat {
        guard available > 0 else { return lineHeight }
        var total: CGFloat = 0
        var rows = 0
        for line in MarkdownRender.lines(from: text) {
            switch line.kind {
            case .rule:
                total += blankLineHeight
                continue
            case .paragraph where line.plain.trimmingCharacters(in: .whitespaces).isEmpty:
                total += blankLineHeight
                continue
            default:
                break
            }
            var room = available
            if case .item = line.kind { room -= markerColumn }
            let measured = TextMeasure.width(line.plain, font: answerFont)
            let wrapped = max(1, Int(ceil(measured / max(1, room))))
            rows += wrapped
            total += CGFloat(wrapped) * lineHeight
        }
        // Хотя бы строка: пустая реплика всё равно занимает место под текст.
        return rows > 0 ? total : lineHeight
    }

    static func height(
        notchHeight: CGFloat,
        notchWidth: CGFloat,
        mode: NotePanelMode = .model,
        transcript: [AssistantSession.Reply] = [],
        isStreaming: Bool = true,
        question: String = "",
        hasCapture: Bool = false,
        captureExpanded: Bool = false,
        commandRows: Int = 0,
        modelEnabled: Bool = true,
        notesEnabled: Bool = true
    ) -> CGFloat {
        var content: CGFloat = 0
        switch mode {
        case .model:
            // Захваченное — над всем остальным: сперва человек узнаёт, с чем
            // работает, и только потом решает, что с этим делать.
            if hasCapture {
                content += CapturedTextPill.height(expanded: captureExpanded)
                    + NotchStyle.gridSpacing
            }
            // С выключенной моделью ленты и поля вопроса нет вовсе: спросить
            // некого, а пустая область ответа и мёртвое поле — это полпанели,
            // отданной под то, чего нет. Остаются захваченное и команды,
            // которым модель не нужна.
            if modelEnabled {
                content += bodyHeight(
                    transcript: transcript,
                    isStreaming: isStreaming,
                    notchWidth: notchWidth
                )
                // Строка действий над лентой появляется только вместе
                // с ответом: держать её пустой значило бы отнимать высоту
                // у самой ленты.
                if !transcript.isEmpty || isStreaming {
                    content += NotchStyle.gridSpacing + actionSize
                }
                content += NotchStyle.gridSpacing
                    + questionHeight(text: question, notchWidth: notchWidth)
            }
            // Список команд стоит под полем: сперва «что сказать», потом
            // «чем это сделать». Ноль строк — признак того, что списка нет
            // вовсе: команды выключены в настройках.
            if commandRows > 0 {
                content += NotchStyle.gridSpacing + CommandRows.height(rows: commandRows)
            }
        case .note:
            content = noteFieldHeight
        }
        if hasActionRow(modelEnabled: modelEnabled, notesEnabled: notesEnabled, isNote: mode == .note) {
            content += NotchStyle.gridSpacing + rowHeight
        }
        return NotchStyle.height(notchHeight: notchHeight, contentHeight: content)
    }

    /// Самая высокая, какой панель вообще может стать.
    ///
    /// Потолок окна считается по ней, и считать его надо здесь, а не в окне:
    /// у панели два режима и растущее поле вопроса, и какой из них выше
    /// на этой машине — заранее не сказать. Прежде здесь перебирались только
    /// режимы, поле было однострочным, и выросшая панель обрезалась бы краем
    /// окна: содержимое, переросшее окно, обрезается — и это ловится только
    /// снимком.
    ///
    /// Считается по **самому полному** составу: выросшее поле, плашка захвата
    /// и полный список команд разом. Так они и сходятся в жизни — ⌃⌥C
    /// открывает панель ровно с захватом и списком.
    static func tallest(notchHeight: CGFloat, notchWidth: CGFloat) -> CGFloat {
        // Строка из пробелов ровно на потолок поля: высоту вопроса считает
        // сам `GrowingTextField`, и просить у него потолок надо тем же
        // расчётом, каким считается обычная высота.
        let longQuestion = String(repeating: "\n", count: GrowingTextField.maxLines)
        return NotePanelMode.allCases
            .map {
                height(
                    notchHeight: notchHeight,
                    notchWidth: notchWidth,
                    mode: $0,
                    question: longQuestion,
                    hasCapture: true,
                    captureExpanded: true,
                    commandRows: QuickCommands.visibleRows
                )
            }
            .max() ?? 0
    }

    // MARK: - Тело

    private var isNote: Bool { draft.mode == .note }
    private var hasAnswer: Bool { !session.transcript.isEmpty || session.isStreaming }
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
                // Первой в крыле: пока голос идёт, оборвать его — самое
                // срочное из всего, что здесь можно сделать.
                if voicePhase != nil {
                    NotchPanelButton(
                        symbol: "stop.fill",
                        hint: t("Замолчать"),
                        action: onStopVoice
                    )
                }
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
                    if !session.captured.isEmpty {
                        CapturedTextPill(
                            text: session.captured,
                            isExpanded: session.isCaptureExpanded,
                            onToggle: onToggleCapture,
                            onClear: onClearCapture
                        )
                    }
                    if modelEnabled {
                        answerBody
                        if hasAnswer { answerActions }
                        questionField
                    }
                    if !commands.isEmpty { commandList }
                }
                switch draft.prompt {
                case .link: linkRow
                case nil:
                    if Self.hasActionRow(
                        modelEnabled: modelEnabled,
                        notesEnabled: notesEnabled,
                        isNote: isNote
                    ) {
                        actionRow
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            NotchPanelTitle(
                symbol: isNote ? draft.mode.symbol : (modelEnabled ? "sparkles" : "square.grid.2x2"),
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
        // Пока идёт голосовой заход, название говорит о нём: панель открыли
        // затем, чтобы понять, что происходит, — и «Модель» на это
        // не отвечает.
        switch voicePhase {
        case .listening: return t("Слушаю")
        case .thinking: return t("Модель думает…")
        case .speaking: return t("Отвечаю")
        case nil: break
        }
        // Без модели панель — это список того, что можно сделать
        // с захваченным. Обещать в шапке модель, которой нет, значит
        // отправить человека искать поле ввода, которого тоже нет.
        // Своё имя есть только у запущенной команды — оно и стоит в шапке,
        // пока она отвечает. Всё остальное время панель зовётся так же,
        // как плитка, которой её открыли.
        return session.title.isEmpty ? t("Команды") : session.title
    }

    // MARK: - Ответ

    private var emptyText: String {
        if session.isStreaming { return t("Модель думает…") }
        if !modelEnabled { return t("Модель выключена — переключитесь на заметку") }
        return session.hasNoConversation ? t("Ответ появится здесь") : ""
    }

    /// Лента переписки: свои реплики и ответы модели по порядку.
    ///
    /// Показывался только последний ответ, и это было терпимо, пока
    /// спрашивали с клавиатуры: свой вопрос человек только что набрал
    /// и помнит. Голосом — не помнит: сказанное вслух нигде не осталось,
    /// а разобрать, что расслышала модель, можно только увидев это словами.
    ///
    /// Лента одна на оба способа спрашивать. Переписка и так одна —
    /// два разных её вида разошлись бы при первой же правке.
    private var answerBody: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Self.replySpacing) {
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: NotchStyle.font(11.5)))
                            // Янтарный из палитры, а не системный `.orange`:
                            // «что-то не так» в этом приложении одного цвета
                            // везде, и плашка события красит его отсюда же.
                            .foregroundStyle(Palette.warning)
                    }
                    if transcript.isEmpty {
                        Text(emptyText)
                            .font(.system(size: NotchStyle.font(12)))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(transcript) { reply in
                            replyRow(reply)
                        }
                    }
                    // Якорь для прокрутки: следим за хвостом, а не за всем
                    // текстом — иначе рывок на каждом слове.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Self.bodyHeight(
                transcript: transcript,
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

    private var transcript: [AssistantSession.Reply] { session.transcript }

    /// Одна реплика ленты.
    ///
    /// Свою прижимаем вправо и кладём в капсулу, ответ оставляем слева
    /// обычным текстом. Различать их обязательно: без этого лента читается
    /// как один сплошной текст, в котором непонятно, где чей голос, — а при
    /// голосовом разговоре именно свой вопрос и приходят проверять.
    ///
    /// Разметку разбираем только у ответа: человек её не пишет, а модель
    /// пишет всегда.
    @ViewBuilder
    private func replyRow(_ reply: AssistantSession.Reply) -> some View {
        switch reply.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: Self.userReplyInset)
                Text(reply.text)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Self.userReplyPadding.width)
                    .padding(.vertical, Self.userReplyPadding.height)
                    .background(
                        RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                            .fill(Palette.assistant.opacity(NotchStyle.dense(0.28)))
                    )
            }
        case .assistant:
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                ForEach(MarkdownRender.lines(from: reply.text)) { line in
                    markdownLine(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Что сделать с готовым ответом.
    ///
    /// Как только ответ дописан, подсветка сама переезжает сюда со списка
    /// команд: команду человек уже выбрал, ответ получил — остаётся решить,
    /// куда его деть. ← и → водят подсветку, Enter выполняет.
    private var answerActions: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            icon(
                AssistantSession.AnswerAction.copy.symbol,
                AssistantSession.AnswerAction.copy.title,
                isHighlighted: session.highlightedAnswerAction == .copy,
                action: onCopy
            )
            icon(
                AssistantSession.AnswerAction.paste.symbol,
                AssistantSession.AnswerAction.paste.title,
                isHighlighted: session.highlightedAnswerAction == .paste,
                action: onPaste
            )
            if notesEnabled {
                icon(
                    AssistantSession.AnswerAction.note.symbol,
                    AssistantSession.AnswerAction.note.title,
                    tint: Palette.assistant,
                    isHighlighted: session.highlightedAnswerAction == .note,
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

    /// Вопрос: Enter отправляет, ⇧Enter переводит строку.
    ///
    /// Поле растёт вместе с текстом до пяти строк, дальше прокручивается.
    /// Однострочным оно быть перестало не ради удобства: набранное сверх
    /// строки уезжало за правый край и **дальше не набиралось вовсе** —
    /// человек не видел ни начала своего вопроса, ни конца.
    private var questionField: some View {
        GrowingTextField(
            text: Binding(get: { draft.question }, set: { draft.question = $0 }),
            textWidth: Self.questionTextWidth(notchWidth: metrics.notchWidth),
            onSubmit: onSend,
            onMoveHighlight: onMoveHighlight,
            onMoveAnswerAction: onMoveAnswerAction,
            onCycleModel: onCycleModel,
            onEscape: onEscapeHighlight
        )
        .frame(height: questionFieldHeight)
        // Скругление постоянное — то, что делает пустое поле капсулой.
        // Настоящая `Capsule` подросшее поле превратила бы в пилюлю
        // с полукруглыми боками; постоянный радиус оставляет его
        // скруглённым прямоугольником, не меняя вида однострочного.
        //
        // `.circular`, не `.continuous`: у сглаженной обводка торца рвётся —
        // дуга не доходит до края, и слева остаётся вертикальный огрызок.
        // Подложка через общий слой: на стекле поле, выкрашенное своей
        // заливкой, читалось плоским серым прямоугольником среди
        // преломляющих поверхностей.
        //
        // Роль `.card`, а не `.row`: поле не нажимают, в него ставят курсор,
        // и подсветка под курсором обещала бы кнопку.
        .surface(.card,
                 in: RoundedRectangle(cornerRadius: Self.questionRadius, style: .circular),
                 glass: Surface.inNotch)
        // Обводка осталась своей и ушла из подложки в наложение: она очерчивает
        // поле как место для ввода, а не как поверхность, и нужна на обеих
        // ветках — со стеклом и без.
        .overlay(
            RoundedRectangle(cornerRadius: Self.questionRadius, style: .circular)
                .strokeBorder(
                    .white.opacity(NotchStyle.dense(0.12)),
                    lineWidth: 1
                )
        )
        // Подсказка своим наложением, а не средствами поля: у `NSTextView`
        // её нет вовсе, в отличие от `NSTextField`. Отступы берутся из самого
        // поля — выписанные заново, они разъехались бы с текстом.
        .overlay(alignment: .topLeading) {
            if draft.question.isEmpty {
                Text(session.usesNotes ? t("Спросите по заметкам") : t("Спросите модель"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .padding(.horizontal, GrowingTextField.inset.width)
                    .padding(.vertical, GrowingTextField.inset.height)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) { flashPill }
    }

    /// Список команд под полем.
    private var commandList: some View {
        CommandRows(
            commands: commands,
            models: models,
            defaultModel: defaultModel,
            highlighted: session.highlightedCommandID,
            choosingModelFor: session.choosingModelFor,
            onRun: onRunCommand,
            onBeginChoosingModel: onBeginChoosingModel,
            onChooseModel: onChooseModel,
            onCancelChoosingModel: onCancelChoosingModel
        )
    }

    /// Высота поля вопроса прямо сейчас.
    private var questionFieldHeight: CGFloat {
        Self.questionHeight(text: draft.question, notchWidth: metrics.notchWidth)
    }

    /// Скругление поля вопроса — половина его наименьшей высоты, то есть
    /// ровно капсула, пока строка одна.
    static var questionRadius: CGFloat { GrowingTextField.minHeight / 2 }

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
        // Через общий слой, как и поле вопроса: они лежат на одном экране,
        // и разные подложки у двух полей ввода читались бы небрежностью.
        .surface(.card,
                 in: RoundedRectangle(cornerRadius: NotchStyle.cardRadius, style: .continuous),
                 glass: Surface.inNotch)
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
    /// Обычные плашки событий сюда не годятся вовсе: накладка важнее плашки
    /// по расчёту состояния, и из-под открытой панели её не видно. Сама
    /// плашка — общая с панелью буфера, см. `PanelFlashPill`.
    private var flashPill: some View {
        PanelFlashPill(flash: flash)
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

    /// Есть ли в полосе действий хоть что-нибудь.
    ///
    /// С выключенной моделью в режиме разговора её содержимое пусто: главного
    /// действия нет — отправлять некому, — а переключатель режима есть только
    /// вместе с заметками. Пустая полоса при этом всё равно занимала высоту,
    /// и под списком команд оставалась чёрная плешь в тридцать точек.
    static func hasActionRow(modelEnabled: Bool, notesEnabled: Bool, isNote: Bool) -> Bool {
        if isNote { return notesEnabled }
        return notesEnabled || modelEnabled
    }

    private var actionRow: some View {
        // Группа стеклянных поверхностей: переключатель режима, кнопки
        // оформления и главное действие сливаются в один блок управления,
        // а не лежат россыпью кружков вдоль края панели.
        //
        // Состав ряда ограничен по построению, высота задана `rowHeight` —
        // содержимое размер панели здесь не задаёт, и контейнер безопасен.
        GlassGroup(spacing: Self.actionSpacing) {
            HStack(spacing: Self.actionSpacing) {
                // Переключатель режима есть и без модели: разговаривать
                // не с кем, а записать захваченное заметкой — по-прежнему да,
                // и другого пути в этот режим из панели нет.
                if notesEnabled {
                    ModeSwitch(mode: draft.mode, onSelect: onSelectMode)
                }
                if isNote {
                    // Оформление правит абзац под курсором. В пустом поле
                    // абзаца нет, и кнопки не делают ровно ничего — а нажатие
                    // без ответа человек читает как поломку, а не как
                    // «пока рано».
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
            // Капсула ссылки стоит в том же ряду, что и круглые кнопки
            // действий, и подложку берёт оттуда же.
            .surface(.control, in: Capsule(), glass: Surface.inNotch)

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
        isHighlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.actionSize, height: Self.actionSize)
                // Через общий слой: кнопки действий стоят в одном ряду
                // с круглыми кнопками панели, и своя заливка рядом со стеклом
                // читалась бы плоским пятном.
                .surface(.control, in: Circle(), glass: Surface.inNotch)
                // Подсветка с клавиатуры — обводкой, как у строки команды:
                // одинаковый признак «сюда сейчас уйдёт Enter» в обоих местах,
                // иначе их пришлось бы различать по памяти.
                .overlay(
                    Circle().strokeBorder(
                        isHighlighted ? Palette.assistant.opacity(0.9) : .clear,
                        lineWidth: 1.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
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
