import TrunookXPC
import Foundation

/// Надиктовать текст в поле.
///
/// Не `VoiceSession` и не её кусок: там речь — это **вопрос**, после которого
/// идут модель и синтезатор. Здесь речь — это **текст**, и кончается она
/// ровно там, где человек перестал говорить. Своего слушателя держит по той
/// же причине: одновременно диктовать в заметку и спрашивать голосом нельзя,
/// но и мешать друг другу они не должны — заход голоса не обязан гаснуть
/// оттого, что кто-то начал диктовать, и наоборот.
///
/// Ничего не рисует и в вырез не лезет: отдаёт текст замыканием, а куда
/// его класть, решает тот, кто диктовку позвал.
final class Dictation: ObservableObject {
    let listener = SpeechListener()

    /// Текст по мере распознавания — его видно в поле, пока говорят.
    var onText: ((String) -> Void)?
    /// Договорили. Текст тот же, что и в последнем `onText`.
    var onFinish: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    @Published private(set) var isListening = false

    private let settings: Settings
    private var pollTimer: Timer?

    init(settings: Settings = .shared) {
        self.settings = settings
        listener.onFinish = { [weak self] text in self?.finish(text) }
        listener.onFailure = { [weak self] reason in
            self?.stop()
            DebugLog.write("диктовка: \(reason)")
            self?.onFailure?(reason)
        }
    }

    /// Начать или закончить. Тем же нажатием, каким начали: пока диктуют,
    /// других дел у кнопки нет, а искать вторую ради остановки — лишняя
    /// работа памяти.
    func toggle() {
        isListening ? listener.finish() : start()
    }

    func start() {
        guard !isListening else { return }
        isListening = true
        listener.start(language: language, silence: settings.voiceSilence)
        watch()
        DebugLog.write("диктовка: начата")
    }

    func cancel() {
        listener.cancel()
        stop()
        DebugLog.write("диктовка: отменена")
    }

    func shutdown() {
        stopWatching()
        listener.shutdown()
        isListening = false
    }

    // MARK: - Ход

    private func finish(_ text: String) {
        stop()
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        DebugLog.write("диктовка: \(clean.count) симв.")
        guard !clean.isEmpty else { return }
        onText?(clean)
        onFinish?(clean)
    }

    private func stop() {
        stopWatching()
        isListening = false
    }

    /// Текст пробрасывается по мере распознавания, опросом.
    ///
    /// Тем же шагом, каким `VoiceSession` следит за ответом модели: поле,
    /// заполняющееся только в конце, выглядит как неработающий микрофон —
    /// человек говорит, а на экране пусто, и он начинает говорить громче.
    private func watch() {
        stopWatching()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.isListening else { return }
            let text = self.listener.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self.onText?(text)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private var language: Language {
        settings.voiceLanguage ?? Localization.shared.resolved
    }
}
