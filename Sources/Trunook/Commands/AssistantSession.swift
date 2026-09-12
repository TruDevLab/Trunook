import TrunookXPC
import AppKit

/// Разговор с моделью, идущий прямо в вырезе.
///
/// Ответ пишется по мере поступления, а не появляется целиком: локальная
/// модель думает секунды, и пустая панель всё это время выглядит как отказ.
final class AssistantSession: ObservableObject {
    /// Название команды, с которой всё началось.
    @Published private(set) var title = ""
    @Published private(set) var answer = ""
    @Published private(set) var isStreaming = false
    @Published private(set) var error: String?
    /// Искать ответ в заметках, а не в общих знаниях модели.
    ///
    /// Переключатель, а не отдельная кнопка отправки: включил — и все
    /// вопросы идут по заметкам, пока не выключил. Кнопка заставляла бы
    /// выбирать заново на каждом вопросе, хотя разговор обычно весь про одно.
    ///
    /// Живёт в сессии, а не в панели: `@State` в этом тулчейне недоступен,
    /// а признак обязан пережить перерисовку.
    @Published var usesNotes = false

    /// Текст, захваченный при вызове: то, что было выделено в чужом окне.
    ///
    /// Живёт отдельно от поля ввода нарочно. В поле его клали — и это было
    /// плохо сразу с двух сторон: страницу текста в однострочном поле
    /// не прочитать, а дописать к ней свой вопрос значит редактировать
    /// чужой текст вокруг своего. Здесь он лежит целым и виден плашкой,
    /// а поле остаётся под то, что человек хочет с ним сделать.
    @Published private(set) var captured = ""

    /// Плашка захваченного текста раскрыта.
    ///
    /// Живёт в сессии, а не в панели: `@State` в этом тулчейне недоступен,
    /// а от признака зависит высота панели — её считает `NotchSizing`,
    /// которому вёрстка ничего сообщить не может.
    @Published var isCaptureExpanded = false

    /// Что делать с готовым ответом. Порядок тот же, что и в панели.
    ///
    /// Отдельный тип, а не индекс: по индексу нельзя понять, что именно
    /// подсвечено, а состав строки меняется — «в заметки» есть только при
    /// включённых заметках, и третьим действием там оказывалось бы то одно,
    /// то другое.
    enum AnswerAction: String, CaseIterable {
        case copy, paste, note

        /// Подпись действия — одна на кнопку в панели и на плашку под чёлкой.
        /// Выписанная в двух местах, она разошлась бы при первой правке.
        var title: String {
            switch self {
            case .copy: return t("Скопировать ответ")
            case .paste: return t("Вставить ответ")
            case .note: return t("Ответ в заметки")
            }
        }

        var symbol: String {
            switch self {
            case .copy: return "doc.on.doc"
            case .paste: return "text.insert"
            case .note: return "tray.and.arrow.down"
            }
        }
    }

    /// Какое действие с ответом подсвечено. `nil` — никакое.
    ///
    /// Появляется само, как только ответ дописан: к этому моменту список
    /// команд человеку уже не нужен — он выбрал команду, получил ответ,
    /// и остаётся решить, куда его деть. Оставлять подсветку на команде
    /// значило бы предлагать спросить то же самое ещё раз.
    @Published var highlightedAnswerAction: AnswerAction?

    /// Какая строка списка команд подсвечена с клавиатуры. `nil` — никакая,
    /// и тогда Enter отправляет набранное в поле.
    ///
    /// Живёт в сессии, а не в панели: `@State` в этом тулчейне недоступен,
    /// а подсветка обязана пережить перерисовку.
    @Published var highlightedCommandID: Int?

    /// У какой команды сейчас выбирают модель. `nil` — список показывает
    /// сами команды.
    ///
    /// Список моделей занимает место списка команд, а не всплывает поверх:
    /// панель прибита к верхней кромке экрана, и всплывающему просто некуда
    /// раскрыться — вниз содержимое обрезается окном.
    @Published var choosingModelFor: Int?

    /// Куда вставлять ответ.
    ///
    /// Запоминается в момент запуска команды, до того как панель заберёт
    /// фокус ради ввода: иначе «вставить в активное окно» вставляло бы
    /// в саму панель.
    private(set) var target: NSRunningApplication?

    private let client: ModelClient
    private var messages: [ModelClient.ChatMessage] = []
    private var task: Task<Void, Never>?

    /// Какое окно контекста просить у модели.
    ///
    /// `nil` — не просить ничего, пусть решает Ollama: обычному разговору
    /// её умолчания хватает с запасом. Заметки в контекст в него не влезают,
    /// и там окно приходится называть явно — иначе промт молча обрежется.
    private var contextWindow: Int?

    /// Какой моделью идёт этот разговор. `nil` — той, что в настройках.
    ///
    /// Держится на весь разговор, а не на одну реплику: команда выбрала
    /// модель, модель ответила, человек возразил — отвечать на возражение
    /// обязана та же. Смена модели посреди разговора означала бы, что
    /// продолжение пишет кто-то другой, не помнящий сказанного своим голосом.
    private var model: String?

    /// Какой моделью спрашивать свободный вопрос. `nil` — как в настройках.
    ///
    /// Держится у разговора, а не в настройках: «а что скажет вот эта»
    /// спрашивают на один заход, и уносить этот выбор в настройки значило бы
    /// заставить человека возвращать его руками. Сбрасывается вместе
    /// с разговором.
    @Published private(set) var questionModel: String?

    func setQuestionModel(_ stored: String?) {
        questionModel = stored
        // Разговор уже идёт — менять его модель на полуслове нельзя:
        // продолжение писал бы кто-то другой, не помнящий сказанного
        // своим голосом. Новая модель возьмётся со следующей переписки.
        guard messages.isEmpty else { return }
        model = stored
    }

    /// Реплики, которых в ленте быть не должно.
    ///
    /// Номерами в `messages`, а не признаком у самой реплики: `ChatMessage`
    /// уходит в Ollama как есть, и лишнее поле пришлось бы вычищать перед
    /// каждой отправкой. Номера при этом устойчивы — переписка только
    /// дописывается с конца.
    private var hiddenMessages: Set<Int> = []

    // MARK: - Помощник

    /// Подписи шагов — номерами в `messages`, тем же приёмом, что
    /// и `hiddenMessages`, и по той же причине: `ChatMessage` уходит
    /// на провод как есть, и лишнее поле пришлось бы вычищать перед каждой
    /// отправкой.
    private var stepLabels: [Int: (label: String, symbol: String)] = [:]

    /// Какой инструмент работает прямо сейчас. `nil` — никакой.
    @Published private(set) var runningTool: AgentTool?

    /// Что помощник предлагает сделать. `nil` — ничего не предлагает.
    ///
    /// Значением, а не веткой: по нему считается высота панели.
    @Published private(set) var pending: PendingAction?

    /// Описания инструментов, доступных этому разговору. Пустой список —
    /// помощника нет, и запрос уходит ровно таким, каким уходил всегда.
    var availableTools: () -> [[String: Any]] = { [] }

    /// Выполнить то, о чём просит модель. Вешает контроллер: сессия
    /// о службах не знает и знать не должна.
    var runTool: ((ToolCall, @escaping (AgentToolResult) -> Void) -> Void)?

    private lazy var loop = AgentLoop(client: client)

    /// Каким способом спросили в этот раз.
    ///
    /// Инструменты голос получает наравне с набранным вопросом: заметки,
    /// календарь и погода нужны ему ровно так же. А вот карточку
    /// подтверждения спрошенному голосом показать негде — панель при нём
    /// не раскрывается, — поэтому её открывает контроллер, и знать об этом
    /// он может только отсюда.
    private(set) var style: AnswerStyle = .written

    /// Спросили голосом: ответ прочитают вслух, панели на экране нет.
    var isSpoken: Bool { style == .spoken }

    init(client: ModelClient = ModelClient()) {
        self.client = client
    }

    var isEmpty: Bool { answer.isEmpty && !isStreaming && error == nil }

    /// Вопрос ещё не задавали.
    ///
    /// Не `messages.isEmpty`: в переписке к этому моменту может уже лежать
    /// системное указание, как отвечать, — оно репликой человека не является.
    private var isFirstQuestion: Bool {
        !messages.contains { $0.role == "user" }
    }

    /// Переписка для показа: без системных указаний и с ответом, который
    /// идёт прямо сейчас.
    ///
    /// Отдельно от `messages`, а не вместо них, потому что это разные списки.
    /// В `messages` лежит то, что уходит модели: там есть системная реплика,
    /// а заметки приклеены к первому вопросу целым простынём. Показывать это
    /// нельзя — человек увидел бы свой архив вместо своего вопроса.
    var transcript: [Reply] {
        var result: [Reply] = []
        for (index, message) in messages.enumerated() {
            switch message.role {
            case "user":
                // Промт команды в ленте не показывается вовсе: человек
                // не писал его — он нажал строку с названием. Показать
                // означало бы выдать ему за его слова чужой промт вместе
                // с захваченным абзацем целиком.
                guard !hiddenMessages.contains(index) else { continue }
                result.append(Reply(
                    id: result.count,
                    role: .user,
                    text: Self.question(from: message.content)
                ))
            case "assistant":
                // Заход за инструментом текста не несёт, и пустой пузырь
                // в ленте выглядел бы сбоем. Сам вызов покажет строка шага.
                guard !(message.content.isEmpty && !message.toolCalls.isEmpty) else { continue }
                result.append(Reply(id: result.count, role: .assistant, text: message.content))
            case "tool":
                // В реплике лежит то, что ушло модели: расписание дня целым
                // куском, погода числами. Человеку это показывать нельзя —
                // он увидел бы служебный текст вместо строчки «Посмотрел
                // календарь». Подпись для него лежит отдельно, номером.
                guard let step = stepLabels[index] else { continue }
                result.append(Reply(
                    id: result.count,
                    role: .step,
                    text: step.label,
                    symbol: step.symbol
                ))
            default:
                // Системное указание — не реплика разговора.
                continue
            }
        }
        // Идущий ответ ещё не в переписке: он попадёт туда со следующим
        // вопросом. Без него лента обрывалась бы ровно на том, что человек
        // сейчас читает.
        // Инструмент работает прямо сейчас — человеку видно, чем занят
        // помощник. Без этой строки панель молчит ровно столько, сколько
        // идёт служба, и выглядит это как зависание.
        if let runningTool {
            result.append(Reply(
                id: result.count,
                role: .step,
                text: runningTool.title + "…",
                symbol: runningTool.symbol
            ))
        }
        if !answer.isEmpty {
            result.append(Reply(id: result.count, role: .assistant, text: answer))
        }
        return result
    }

    /// Одна реплика разговора — то, что видно в панели.
    ///
    /// Опознаётся порядковым номером, а не `UUID`. Случайный
    /// на каждом обращении делал бы **любые** две ленты неравными, а по их
    /// равенству вырез решает, менялось ли что-нибудь: панель пересчитывала
    /// бы себя десять раз в секунду впустую.
    struct Reply: Identifiable, Equatable {
        /// Шаг — не реплика разговора, а отметка о сделанном: «Посмотрел
        /// календарь», «Таймер на 10 минут». Рисуется мелко и приглушённо,
        /// между вопросом и ответом.
        enum Role { case user, assistant, step }

        let id: Int
        let role: Role
        let text: String
        /// Значок шага. У реплик разговора его нет.
        var symbol: String?
    }

    /// Достаёт из первой реплики сам вопрос.
    ///
    /// Заметки уходят модели, приклеенными к вопросу одним куском, и в ленте
    /// от этого была бы стена чужого текста вместо строчки «что там у меня
    /// про X». Отрезаем по той же метке, которой они и склеивались.
    private static func question(from content: String) -> String {
        let marker = t("Вопрос:") + " "
        guard let range = content.range(of: marker, options: .backwards) else { return content }
        return String(content[range.upperBound...])
    }

    /// Каким должен быть ответ.
    ///
    /// Не настройка, а свойство **способа спросить**: набранный вопрос
    /// читают глазами и терпят подробность, а голосовой слушают ушами —
    /// и абзац, прочитанный вслух, слушать невозможно.
    enum AnswerStyle {
        /// Обычный ответ в панель.
        case written
        /// Ответ, который прочитают вслух.
        case spoken

        var instruction: String? {
            switch self {
            case .written:
                return nil
            case .spoken:
                // Промтом, а не обрезкой по `num_predict`: обрезка рвёт фразу
                // на полуслове, и вслух это звучит как оборванная связь.
                return t("Твой ответ прочитают вслух. Отвечай одним-тремя короткими предложениями, живой разговорной речью. Без списков, заголовков, звёздочек и любой разметки — её невозможно произнести. Если ответ длинный, скажи самое главное.")
            }
        }
    }

    // MARK: - Ход разговора

    /// Запуск команды: готовый промт уходит модели, разговор начинается
    /// заново.
    ///
    /// Реплика с промтом прячется из ленты. Человек её не писал — он нажал
    /// строку с названием команды, — а внутри неё лежит и сам промт, и весь
    /// захваченный абзац. Показать это значило бы выдать чужой текст за его
    /// собственный вопрос. Название команды и так стоит в шапке панели.
    func start(title: String, prompt: String, model: String?, target: NSRunningApplication?) {
        cancel()
        style = .written
        self.title = title
        self.target = target
        self.model = model
        answer = ""
        error = nil
        messages = [.user(prompt)]
        hiddenMessages = [0]
        highlightedAnswerAction = nil
        run()
    }

    /// Свободный вопрос: панель открывается с пустым разговором, а поле
    /// ввода в ней есть всегда.
    ///
    /// Отдельно от `start`: там разговор начинается с готового промта и сразу
    /// уходит к модели, а здесь ждём, пока человек напишет.
    /// `captured` — выделенный текст, если он был. Он не уходит модели сам
    /// по себе: пока человек не выбрал команду и не написал вопрос, спрашивать
    /// нечего. Уйдёт вместе с первым же вопросом.
    func ask(captured: String = "", target: NSRunningApplication?) {
        cancel()
        title = t("Команды")
        self.target = target
        self.captured = captured
        isCaptureExpanded = false
        highlightedAnswerAction = nil
        model = nil
        highlightedCommandID = nil
        choosingModelFor = nil
        answer = ""
        error = nil
        messages = []
        hiddenMessages = []
    }

    /// Убрать захваченное — крестиком на плашке.
    ///
    /// Нужно затем же, зачем плашка вообще видна: захват срабатывает
    /// на всё выделенное, и человек, спросивший о постороннем, должен
    /// иметь возможность не тащить чужой абзац в свой вопрос.
    func clearCapture() {
        guard !captured.isEmpty else { return }
        captured = ""
        isCaptureExpanded = false
        DebugLog.write("модель: захваченный текст убран")
    }

    /// Разговора ещё не было: ни ответа, ни заданных вопросов. Не то же
    /// самое, что `isEmpty` — тот про пустой ответ внутри уже начатого
    /// разговора.
    var hasNoConversation: Bool { messages.isEmpty && answer.isEmpty }

    /// Вопрос модели. Прежний ответ уходит в переписку — модель должна
    /// помнить, что она уже сказала.
    ///
    /// Заметки и захваченный текст кладутся **только в первую реплику**:
    /// дальше они уже в переписке, и слать их заново значило бы удваивать
    /// контекст на каждом встречном вопросе.
    func send(_ question: String, notesContext: String? = nil, style: AnswerStyle = .written) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        self.style = style

        if !answer.isEmpty {
            messages.append(.assistant(answer))
        }
        // Указание, как отвечать, кладётся один раз и первым — до всего
        // остального. Повторять его на каждой реплике нельзя: модель
        // начинает отвечать на само указание.
        if messages.isEmpty, let instruction = style.instruction {
            messages.append(.system(instruction))
        }
        // Приставка к первому вопросу: сперва заметки, если по ним ищут,
        // потом захваченный текст. Порядок такой потому, что заметки —
        // это архив, а захваченное — то, о чём спрашивают прямо сейчас:
        // ближе к вопросу должно лежать то, что к нему относится теснее.
        var preamble: [String] = []
        if isFirstQuestion {
            if let notesContext {
                title = t("По заметкам")
                preamble.append(notesContext)
            }
            if !captured.isEmpty { preamble.append(captured) }
        }

        if preamble.isEmpty {
            messages.append(.user(text))
        } else {
            // Метка «Вопрос:» — не украшение промта, а разделитель для ленты:
            // по ней из реплики достаётся сам вопрос, иначе человек увидел бы
            // в переписке свой архив и чужой абзац вместо строчки, которую
            // набрал.
            messages.append(.user(
                preamble.joined(separator: "\n\n") + "\n\n" + t("Вопрос:") + " " + text
            ))
            contextWindow = ModelClient.contextWindow(
                forCharacters: messages.reduce(0) { $0 + $1.content.count }
            )
        }
        // Модель разговора назначается первым вопросом и дальше не меняется.
        if messages.count <= 1, model == nil { model = questionModel }
        answer = ""
        error = nil
        highlightedAnswerAction = nil
        run()
    }

    private func run() {
        isStreaming = true
        let tools = availableTools()
        // Инструменты занимают место в контексте, и место немалое. Ollama
        // режет переросшее **молча** — и выглядит это как выдумка модели,
        // а не как потеря половины промта. Просим окно с их учётом.
        if !tools.isEmpty {
            let schemas = (try? JSONSerialization.data(withJSONObject: tools))?.count ?? 0
            contextWindow = ModelClient.contextWindow(
                forCharacters: messages.reduce(0) { $0 + $1.content.count } + schemas
            )
        }
        // Имя модели пишем всегда, в том числе «по умолчанию»: у команд
        // модель своя, и увидеть, к какой именно ушёл запрос, иначе негде —
        // ответ приходит без обратного адреса.
        DebugLog.write(
            "модель: запрос \(model ?? "по умолчанию"), реплик в переписке — \(messages.count)"
                + (contextWindow.map { ", окно контекста \($0)" } ?? "")
                + (tools.isEmpty ? "" : ", инструментов \(tools.count)")
        )

        if !tools.isEmpty {
            runAgent(tools: tools)
            return
        }

        task = client.stream(
            messages: messages,
            contextWindow: contextWindow,
            model: model,
            onToken: { [weak self] piece in
                self?.answer += piece
            },
            onFinish: { [weak self] result in self?.finish(result) }
        )
    }

    /// Заход с инструментами: круг ведёт `AgentLoop`.
    ///
    /// Отдельной веткой, а не вторым путём на всю сессию: с пустым списком
    /// инструментов разговор обязан идти ровно так же, как шёл всегда, —
    /// иначе помощник сломал бы то, чего не касается.
    private func runAgent(tools: [[String: Any]]) {
        loop.perform = { [weak self] call, done in
            guard let self, let runTool = self.runTool else {
                done(AgentToolResult(
                    text: t("Действие выполнить нечем."),
                    label: t("Действие недоступно")
                ))
                return
            }
            runTool(call, done)
        }

        loop.run(
            messages: messages,
            tools: tools,
            contextWindow: contextWindow,
            model: model,
            onToken: { [weak self] piece in self?.answer += piece },
            onCall: { [weak self] call in
                guard let self else { return }
                // Проговорённое моделью уже легло в переписку репликой
                // с вызовом — в `answer` ему делать нечего, иначе тот же
                // текст встал бы в ленте дважды.
                self.answer = ""
                self.runningTool = AgentTool.named(call.name)
            },
            onStep: { [weak self] step, updated in
                guard let self else { return }
                self.messages = updated
                self.stepLabels[updated.count - 1] = (
                    step.result.label,
                    AgentTool.named(step.call.name)?.symbol ?? "wand.and.stars"
                )
                self.runningTool = nil
            },
            onFinish: { [weak self] result in self?.finish(result) }
        )
    }

    /// Что делать с готовым ответом. Один на оба пути — обычный и с кругом.
    private func finish(_ result: Result<String, Error>) {
        isStreaming = false
        runningTool = nil
        switch result {
        case let .success(text):
            DebugLog.write("модель: ответ \(text.count) симв.")
            // Ответ дописан — фокус переезжает на то, что с ним делать.
            // Список команд свою работу закончил.
            if !text.isEmpty {
                highlightedCommandID = nil
                highlightedAnswerAction = .copy
                // Подпись сразу: подсветка появилась сама, человек её
                // не наводил и не знает, на чём она стоит.
                NotchHintTracker.shared.focus(AnswerAction.copy.title)
            }
        case let .failure(failure):
            error = failure.localizedDescription
            DebugLog.write("модель: ошибка — \(failure.localizedDescription)")
        }
    }

    // MARK: - Предложение помощника

    /// Помощник предлагает — панель показывает карточку.
    func propose(_ action: PendingAction) {
        pending = action
        runningTool = nil
        DebugLog.write("помощник: предлагает \(action.tool.name) — \(action.detail)")
    }

    /// Карточки больше нет: человек нажал, или разговор оборвали.
    func clearPending() { pending = nil }

    func cancel() {
        task?.cancel()
        task = nil
        loop.cancel()
        isStreaming = false
        runningTool = nil
        // Закрыть — не значит согласиться: висящее предложение снимается
        // невыполненным.
        pending = nil
    }

    func reset() {
        cancel()
        title = ""
        answer = ""
        error = nil
        messages = []
        target = nil
        contextWindow = nil
        captured = ""
        isCaptureExpanded = false
        highlightedCommandID = nil
        highlightedAnswerAction = nil
        choosingModelFor = nil
        model = nil
        hiddenMessages = []
        stepLabels = [:]
        runningTool = nil
        pending = nil
        questionModel = nil
    }

    // MARK: - Отладка

    /// Готовая лента со строками шагов — под снимок.
    ///
    /// Настоящие шаги приходят от модели, а вёрстка у них одна и та же:
    /// снимок не должен зависеть от того, что сегодня ответит модель.
    func debugSteps(_ steps: [(String, String)], answer text: String) {
        reset()
        style = .written
        messages = [.user("поставь таймер на 10 минут и скажи, что у меня завтра")]
        for (label, symbol) in steps {
            messages.append(.calls([ToolCall(id: "debug", name: "debug", arguments: "{}")]))
            messages.append(.tool(label, id: "debug", name: "debug"))
            stepLabels[messages.count - 1] = (label, symbol)
        }
        answer = text
        // Ровно как после настоящего ответа: подсветка переезжает
        // на «Скопировать» сама. Без неё отладка не воспроизвела бы беду —
        // она вся была в этой подсветке.
        highlightedAnswerAction = .copy
    }

    // MARK: - Что делать с ответом

    /// В буфер уходит текст без разметки — тот же, что виден в панели.
    /// Копировать сырой Markdown было бы неожиданно: звёздочек на экране
    /// человек не видел, а получил бы их в документе.
    func copyAnswer() {
        let text = MarkdownRender.plain(answer)
        guard !text.isEmpty else { return }
        PasteboardActivity.beQuiet(for: 1.0)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DebugLog.write("модель: ответ скопирован, \(text.count) симв.")
    }

    /// Кладёт ответ в буфер и вставляет его туда, откуда команду позвали.
    ///
    /// Порядок здесь важнее самого нажатия, и на нём это и ломалось. Панель
    /// забирает клавиатуру (`NSApp.activate` плюс ключевое окно выреза),
    /// а ⌘V уходит **активному** приложению. Пока панель на экране и наше
    /// приложение активно, нажатие достаётся вырезу — вставки не происходит,
    /// и выглядит это как несработавшая кнопка.
    ///
    /// Поэтому сперва панель закрывается и фокус возвращается цели, и только
    /// потом идёт нажатие. Закрытие делает не сессия — она о панели ничего
    /// не знает, — а `completion`, и цель приходится запомнить до него:
    /// закрытие сбрасывает сессию, вместе с ней и адрес.
    func pasteAnswer(completion: @escaping () -> Void) {
        guard !answer.isEmpty else { return }
        copyAnswer()

        let destination = target
        completion()

        // Порядок — деактивация, переключение, пауза, нажатие — живёт
        // в `ClipboardPaster`: он же вставляет строки истории, и разъехаться
        // этим двум путям нельзя. Разъезжались: у истории паузы не было вовсе.
        DebugLog.write("модель: вставка ответа в \(destination?.localizedName ?? "?")")
        ClipboardPaster.paste(into: destination)
    }
}
