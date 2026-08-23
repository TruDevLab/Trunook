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
    /// Открыто ли поле для встречного вопроса.
    @Published var isComposing = false
    @Published var draft = ""
    /// Поле ввода в фокусе. Живёт здесь, а не в теле панели: `@State`
    /// в этом тулчейне недоступен — по той же причине так устроены
    /// `HoverTracker` и `NotchHintTracker`.
    @Published var isDraftFocused = false

    /// Куда вставлять ответ.
    ///
    /// Запоминается в момент запуска команды, до того как панель заберёт
    /// фокус ради ввода: иначе «вставить в активное окно» вставляло бы
    /// в саму панель.
    private(set) var target: NSRunningApplication?

    private let client: OllamaClient
    private var messages: [OllamaClient.ChatMessage] = []
    private var task: Task<Void, Never>?

    init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    var isEmpty: Bool { answer.isEmpty && !isStreaming && error == nil }

    // MARK: - Ход разговора

    func start(title: String, prompt: String, target: NSRunningApplication?) {
        cancel()
        self.title = title
        self.target = target
        answer = ""
        error = nil
        draft = ""
        isComposing = false
        messages = [.user(prompt)]
        run()
    }

    /// Свободный вопрос: панель открывается сразу с полем ввода, без команды
    /// и без выделенного текста.
    ///
    /// Отдельно от `start`: там разговор начинается с готового промта и сразу
    /// уходит к модели, а здесь ждём, пока человек напишет.
    func ask(target: NSRunningApplication?) {
        cancel()
        title = t("Вопрос")
        self.target = target
        answer = ""
        error = nil
        draft = ""
        isComposing = true
        messages = []
    }

    /// Разговора ещё не было: ни ответа, ни заданных вопросов. Не то же
    /// самое, что `isEmpty` — тот про пустой ответ внутри уже начатого
    /// разговора.
    var hasNoConversation: Bool { messages.isEmpty && answer.isEmpty }

    /// Встречный вопрос. Прежний ответ уходит в переписку — модель должна
    /// помнить, что она уже сказала.
    func follow(up question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        if !answer.isEmpty {
            messages.append(.assistant(answer))
        }
        messages.append(.user(text))
        answer = ""
        error = nil
        draft = ""
        isComposing = false
        run()
    }

    private func run() {
        isStreaming = true
        DebugLog.write("модель: запрос, реплик в переписке — \(messages.count)")
        task = client.stream(
            messages: messages,
            onToken: { [weak self] piece in
                self?.answer += piece
            },
            onFinish: { [weak self] result in
                guard let self else { return }
                self.isStreaming = false
                switch result {
                case let .success(text):
                    DebugLog.write("модель: ответ \(text.count) симв.")
                case let .failure(failure):
                    self.error = failure.localizedDescription
                    DebugLog.write("модель: ошибка — \(failure.localizedDescription)")
                }
            }
        )
    }

    func cancel() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    func reset() {
        cancel()
        title = ""
        answer = ""
        error = nil
        draft = ""
        isComposing = false
        messages = []
        target = nil
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
    /// Приложение сначала возвращают на передний план: панель могла забрать
    /// фокус ради встречного вопроса, и без этого ⌘V ушло бы в пустоту.
    func pasteAnswer(completion: @escaping () -> Void) {
        guard !answer.isEmpty else { return }
        copyAnswer()

        guard let target, !target.isActive else {
            ClipboardPaster.paste()
            completion()
            return
        }
        target.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            ClipboardPaster.paste()
            completion()
        }
    }
}
