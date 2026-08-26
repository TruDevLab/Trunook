import TrunookXPC
import AppKit
import Foundation

/// Голосовой заход целиком: услышать, спросить, прочитать вслух.
///
/// Связывает три части, у каждой из которых своя забота: `SpeechListener`
/// знает только микрофон, `SpeechSpeaker` — только синтезатор,
/// `AssistantSession` — только разговор с моделью. Здесь они сходятся,
/// и здесь же живёт фаза, по которой светится вырез.
///
/// Разговор берётся **существующий**, а не заводится второй. Иначе переписок
/// стало бы две: спросил голосом, открыл панель дописать текстом — и попал бы
/// в чужой разговор. Одна переписка на оба способа спрашивать.
///
/// Ничего не рисует и в вырез не лезет: как `PurrEffects` отвечает за звук
/// и дрожь, но не решает, гладят ли чёлку.
final class VoiceSession: ObservableObject {
    /// Чем заход занят прямо сейчас.
    ///
    /// От фазы зависит цвет свечения, поэтому она одна на всё: два признака
    /// («слушает» и «отвечает») разошлись бы в первом же случае, когда
    /// не верно ни то ни другое.
    enum Phase: Equatable {
        /// Слушает микрофон.
        case listening
        /// Вопрос ушёл, ответа ещё нет.
        case thinking
        /// Читает ответ вслух.
        case speaking
    }

    @Published private(set) var phase: Phase?

    /// Идёт ли заход прямо сейчас — по нему вырез решает, светиться ли.
    var isActive: Bool { phase != nil }

    /// Заход начался: вырезу пора вздрогнуть и засветиться.
    var onStart: (() -> Void)?
    /// Что-то пошло не так, и человеку надо сказать словами.
    var onFailure: ((String) -> Void)?

    let listener = SpeechListener()
    let speaker = SpeechSpeaker()

    private let assistant: AssistantSession
    private let notes: NotesService
    private let settings: Settings

    /// Спрашиваем по заметкам. Запоминается на старте: заметки собираются
    /// не сразу, а когда речь уже закончилась.
    private var usesNotes = false

    private var pollTimer: Timer?
    /// Сколько тиков подряд заход выглядит законченным, а фаза ещё держится.
    private var idleTicks = 0

    init(assistant: AssistantSession, notes: NotesService, settings: Settings = .shared) {
        self.assistant = assistant
        self.notes = notes
        self.settings = settings

        listener.onFinish = { [weak self] text in self?.ask(text) }
        listener.onFailure = { [weak self] reason in self?.fail(reason) }
        speaker.onFinish = { [weak self] in self?.stop() }
    }

    // MARK: - Заход

    /// Начать слушать. Повторный вызов во время речи означает «я всё сказал»:
    /// тем же жестом, каким заход начали, его и обрывают, не дожидаясь паузы.
    func toggle(usesNotes: Bool) {
        switch phase {
        case .listening:
            listener.finish()
        case .thinking, .speaking:
            // Говорить поверх ответа незачем: сначала оборвать, потом начать
            // заново — иначе микрофон слушал бы собственный синтезатор.
            stop()
            start(usesNotes: usesNotes)
        case nil:
            start(usesNotes: usesNotes)
        }
    }

    private func start(usesNotes: Bool) {
        guard settings.voiceEnabled else { return }
        guard settings.ollamaEnabled else {
            fail(t("Модель выключена — включите её в настройках"))
            return
        }
        if usesNotes, !settings.notesEnabled {
            fail(t("Заметки выключены — включите их в настройках"))
            return
        }

        self.usesNotes = usesNotes
        phase = .listening
        onStart?()
        listener.start(language: language, silence: settings.voiceSilence)
        DebugLog.write("голос: заход начат, по заметкам — \(usesNotes)")
    }

    /// Оборвать всё: и слушание, и чтение вслух.
    func stop() {
        listener.cancel()
        speaker.stop()
        stopWatchingAnswer()
        stopWatchdog()
        phase = nil
    }

    func shutdown() {
        stopWatchingAnswer()
        stopWatchdog()
        listener.shutdown()
        speaker.shutdown()
        phase = nil
    }

    /// Прогнать заход от ответа до тишины, минуя микрофон и модель.
    ///
    /// Ровно этот путь и оказался сломан: полоса в вырезе висела после
    /// ответа, потому что «договорил» до захода не доходило. Из сессии
    /// проверить его иначе нечем — микрофон не поговорит, а модель отвечает
    /// не тем и не тогда.
    func debugAnswer(_ text: String, settings: Settings = .shared) {
        stop()
        phase = .speaking
        onStart?()
        speaker.begin(
            language: settings.voiceLanguage ?? Localization.shared.resolved,
            rate: SpeechSpeaker.rate(forStep: settings.voiceRateStep),
            voiceIdentifier: settings.voiceIdentifier
        )
        speaker.finishStream(answer: text)
        startWatchdog()
        DebugLog.write("голос: отладочный ответ, знаков \(text.count)")
    }

    /// Показать фазу, не запуская захода, — для съёмки свечения.
    ///
    /// Настоящий заход снимком не поймать: он идёт своим ходом, микрофон
    /// в отладочной сессии не поговорит, а фазы сменяются быстрее, чем
    /// успеваешь нажать. Здесь фаза просто ставится и держится.
    func debugShow(phase: Phase) {
        self.phase = phase
    }

    // MARK: - Вопрос

    private func ask(_ text: String) {
        guard !text.isEmpty else {
            // Молчать нельзя: человек звал ассистента и ждёт хоть чего-то.
            fail(t("Ничего не расслышал"))
            return
        }

        phase = .thinking

        var context: String?
        if usesNotes {
            context = notes.contextText(budget: settings.voiceNotesContextLimit)
            guard context != nil else {
                fail(t("Заметок пока нет"))
                return
            }
        }

        assistant.send(text, notesContext: context, style: .spoken)
        speaker.begin(
            language: language,
            rate: SpeechSpeaker.rate(forStep: settings.voiceRateStep),
            voiceIdentifier: settings.voiceIdentifier
        )
        watchAnswer()
    }

    /// Язык захода: заданный для голоса, а иначе язык интерфейса.
    private var language: Language {
        settings.voiceLanguage ?? Localization.shared.resolved
    }

    private func fail(_ reason: String) {
        stop()
        DebugLog.write("голос: \(reason)")
        onFailure?(reason)
    }

    // MARK: - Ответ

    /// Следит за ответом и скармливает его синтезатору по мере поступления.
    ///
    /// Опросом, а не подпиской: поток и так приходит кусками по нескольку раз
    /// в секунду, а десятая доля — тот же шаг, которым в вырезе опрашивается
    /// положение курсора.
    private func watchAnswer() {
        stopWatchingAnswer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pumpAnswer()
        }
        startWatchdog()
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopWatchingAnswer() {
        pollTimer?.invalidate()
        pollTimer = nil
        idleTicks = 0
    }

    /// Сторож: гасит заход, если он выглядит законченным, а фаза держится.
    ///
    /// Заход кончается по сигналу синтезатора — и однажды этот сигнал
    /// **не пришёл ни разу**: делегат спрашивал `synthesizer.isSpeaking`,
    /// а тот в этот самый миг ещё считал себя говорящим. Полоса висела
    /// в вырезе до перезапуска приложения.
    ///
    /// Корень починен, но класс ошибок дорогой: залипшее состояние человек
    /// видит и не может убрать. Сторож ловит его, откуда бы оно ни взялось,
    /// и стоит одного таймера.
    ///
    /// Два тика подряд, а не один: между постановкой реплики в очередь
    /// и началом чтения есть окно, в котором синтезатор ещё молчит, —
    /// оборвать ответ на этом окне было бы хуже, чем подождать полсекунды.
    private func watchStall() {
        guard phase == .speaking else {
            idleTicks = 0
            return
        }
        guard !assistant.isStreaming, !speaker.isSpeaking else {
            idleTicks = 0
            return
        }
        idleTicks += 1
        guard idleTicks >= 2 else { return }
        DebugLog.write("голос: заход завис в «отвечаю» — гашу сторожем")
        stop()
    }

    private var watchdog: Timer?

    private func startWatchdog() {
        watchdog?.invalidate()
        idleTicks = 0
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.watchStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
        idleTicks = 0
    }

    private func pumpAnswer() {
        if let error = assistant.error {
            fail(error)
            return
        }
        // Первые же слова переводят фазу в «отвечает»: свечение обязано
        // смениться тогда, когда пошёл ответ, а не когда он дочитан.
        if !assistant.answer.isEmpty, phase == .thinking {
            phase = .speaking
        }
        if assistant.isStreaming {
            speaker.speak(answer: assistant.answer)
        } else {
            stopWatchingAnswer()
            speaker.finishStream(answer: assistant.answer)
        }
    }
}
