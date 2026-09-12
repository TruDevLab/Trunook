import TrunookXPC
import Foundation

/// Круг: модель — инструмент — модель.
///
/// `ModelClient.stream` — строго один заход, и это правильно: он про провод,
/// а не про разговор. Круг живёт здесь.
///
/// Служб этот объект не знает вовсе — вызов уходит наружу замыканием
/// `perform`. Так же устроен и `OverlayRouter`: узел распознаёт, а делает
/// тот, кому принадлежат службы. Заодно это даёт карточке подтверждения
/// работать даром: исполнитель просто не отвечает, пока человек не нажмёт,
/// и круг ждёт его столько, сколько нужно.
final class AgentLoop {
    /// Один вызов и то, что с ним вышло.
    struct Step: Equatable {
        let call: ToolCall
        let result: AgentToolResult
    }

    /// Сколько заходов к модели на один вопрос.
    ///
    /// Четыре. Каждый заход — это вся переписка плюс описания инструментов
    /// заново: на местной модели в дюжину миллиардов это секунды, и пятый
    /// заход человек читает уже как зависание. Больше трёх инструментов
    /// подряд на один вопрос не требовалось ни разу.
    static let maxRounds = 4

    /// Инструменты этого захода.
    ///
    /// На последнем их нет вовсе — и это не экономия, а единственный способ
    /// закончить разговор словами. С инструментами в руках модель закажет
    /// ещё один круг, которого не будет, и человек останется без ответа.
    static func tools(_ all: [[String: Any]], round: Int) -> [[String: Any]] {
        round >= maxRounds - 1 ? [] : all
    }

    /// Выполнить вызов. Отвечает не сразу: пишущее ждёт человека.
    var perform: ((ToolCall, @escaping (AgentToolResult) -> Void) -> Void)?

    private let client: ModelClient
    private var task: Task<Void, Never>?
    private var stopped = false

    init(client: ModelClient) {
        self.client = client
    }

    /// Куда сообщать о ходе дела. Одной связкой, а не пятью параметрами
    /// через каждый виток рекурсии.
    private struct Sink {
        let onToken: (String) -> Void
        /// Модель заказала вызов — его видно в ленте, пока он идёт.
        let onCall: (ToolCall) -> Void
        /// Вызов закончился; переписка дописана.
        let onStep: (Step, [ModelClient.ChatMessage]) -> Void
        let onFinish: (Result<String, Error>) -> Void
    }

    func run(
        messages: [ModelClient.ChatMessage],
        tools: [[String: Any]],
        contextWindow: Int?,
        model: String?,
        onToken: @escaping (String) -> Void,
        onCall: @escaping (ToolCall) -> Void,
        onStep: @escaping (Step, [ModelClient.ChatMessage]) -> Void,
        onFinish: @escaping (Result<String, Error>) -> Void
    ) {
        stopped = false
        ask(
            messages: messages,
            all: tools,
            round: 0,
            contextWindow: contextWindow,
            model: model,
            sink: Sink(onToken: onToken, onCall: onCall, onStep: onStep, onFinish: onFinish)
        )
    }

    func cancel() {
        stopped = true
        task?.cancel()
        task = nil
    }

    // MARK: - Один заход

    private func ask(
        messages: [ModelClient.ChatMessage],
        all: [[String: Any]],
        round: Int,
        contextWindow: Int?,
        model: String?,
        sink: Sink
    ) {
        let offered = Self.tools(all, round: round)
        task = client.stream(
            messages: messages,
            tools: offered,
            contextWindow: contextWindow,
            model: model,
            onToken: sink.onToken,
            onFinish: { [weak self] result in
                guard let self, !self.stopped else { return }
                switch result {
                case let .failure(error):
                    sink.onFinish(.failure(error))
                case let .success(completion):
                    guard !completion.calls.isEmpty else {
                        sink.onFinish(.success(completion.text))
                        return
                    }
                    // С аргументами, а не одними именами: беда помощника
                    // почти всегда в них — не в том, какой инструмент позван,
                    // а с чем. По одному имени «спросил расписание» не отличить
                    // «спросил про сегодня» от «спросил про десятое октября».
                    DebugLog.write(
                        "помощник: круг \(round + 1), просит "
                            + completion.calls
                                .map { $0.arguments.isEmpty ? $0.name : "\($0.name) \($0.arguments)" }
                                .joined(separator: "; ")
                    )
                    var next = messages
                    next.append(.calls(completion.calls, saying: completion.text))
                    self.execute(
                        completion.calls,
                        at: 0,
                        messages: next,
                        all: all,
                        round: round,
                        contextWindow: contextWindow,
                        model: model,
                        sink: sink
                    )
                }
            }
        )
    }

    /// Вызовы выполняются **по одному и по порядку**.
    ///
    /// Все службы приложения живут на главном потоке и отвечают замыканием,
    /// а пишущее посреди ряда обязано уметь остановить всё на человеке.
    private func execute(
        _ calls: [ToolCall],
        at index: Int,
        messages: [ModelClient.ChatMessage],
        all: [[String: Any]],
        round: Int,
        contextWindow: Int?,
        model: String?,
        sink: Sink
    ) {
        guard index < calls.count else {
            ask(
                messages: messages,
                all: all,
                round: round + 1,
                contextWindow: contextWindow,
                model: model,
                sink: sink
            )
            return
        }

        let call = calls[index]
        sink.onCall(call)

        let finish: (AgentToolResult) -> Void = { [weak self] result in
            guard let self, !self.stopped else { return }
            // Ответ дописывается **всегда**, чем бы дело ни кончилось.
            // Переписку, где у вызова нет пары, строгий сервер отвергает
            // целиком, а модели нужен текст, чтобы внятно объясниться.
            var next = messages
            next.append(.tool(result.text, id: call.id, name: call.name))
            // И ответ инструмента тоже: без него не отличить «модель получила
            // не то» от «модель получила то и сказала другое», а лечится это
            // в разных местах.
            DebugLog.write("помощник: \(call.name) вернул — " + result.text.prefix(300))
            sink.onStep(Step(call: call, result: result), next)
            self.execute(
                calls,
                at: index + 1,
                messages: next,
                all: all,
                round: round,
                contextWindow: contextWindow,
                model: model,
                sink: sink
            )
        }

        guard let perform else {
            // Исполнителя не подвесили — это ошибка сборки, а не человека.
            // Но круг всё равно обязан закончиться словами, а не тишиной.
            finish(AgentToolResult(
                text: t("Действие выполнить нечем."),
                label: t("Действие недоступно")
            ))
            return
        }
        perform(call, finish)
    }
}
