import TrunookXPC
import AVFoundation
import Foundation

/// Читает ответ модели вслух.
///
/// Кладёт **по предложениям, по мере поступления потока**, а не целиком.
/// Локальная модель отдаёт ответ секундами, и ждать конца значило бы всё это
/// время молчать: человек, спросивший голосом, к этому моменту решит, что
/// его не услышали. Синтезатор держит свою очередь, поэтому предложения,
/// поданные по одному, звучат непрерывной речью.
///
/// Отсюда же деление на предложения, а не на слова: слово, отданное
/// в озвучку отдельно, теряет интонацию фразы и звучит как список.
final class SpeechSpeaker: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    /// Договорил всё, что было в очереди.
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    /// Сколько текста уже ушло в очередь. Поток приносит ответ нарастающей
    /// строкой целиком, а озвучивать заново уже сказанное нельзя.
    private var spokenUpTo = 0
    /// Поток кончился — значит остаток можно дочитывать, не дожидаясь точки.
    private var isStreamOver = false

    /// Сколько реплик синтезатор ещё не дочитал.
    ///
    /// Считаем сами, а не спрашиваем `synthesizer.isSpeaking`. Спрашивали —
    /// и **полоса в вырезе висела после ответа навсегда**: в момент, когда
    /// делегат сообщает о дочитанной реплике, синтезатор ещё считает себя
    /// говорящим. Проверка `!isSpeaking` не проходила ни разу, а сообщать
    /// дальше было нечему — очередь-то пуста. Заход так и оставался
    /// в «отвечаю».
    private var pending = 0

    private var language: Language = .ru
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var voiceIdentifier: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Речь

    /// Начать новый ответ. Всё, что читалось до этого, обрывается.
    func begin(language: Language, rate: Float, voiceIdentifier: String?) {
        stop()
        self.language = language
        self.rate = rate
        self.voiceIdentifier = voiceIdentifier
        spokenUpTo = 0
        isStreamOver = false
        pending = 0
    }

    /// Ответ подрос — дочитать то, что стало целыми предложениями.
    ///
    /// Отрезаем от **сырого** ответа, а чистим уже отрезанное. Наоборот
    /// нельзя: чистка меняет длину — схлопывает пробелы, снимает маркеры, —
    /// и меняет её у всего текста разом, включая уже прочитанное. Счётчик
    /// «докуда дочитано» съезжал бы на каждом куске, и ответ читался бы
    /// внахлёст или с пропусками.
    ///
    /// Поток же только дописывает в конец, поэтому у сырой строки начало
    /// не меняется никогда — и отсчитывать от неё безопасно.
    func speak(answer: String) {
        guard answer.count > spokenUpTo else { return }

        let pending = String(answer.dropFirst(spokenUpTo))
        let ready = SpeechChunker.complete(in: pending, isFinal: isStreamOver)
        guard !ready.isEmpty else { return }
        spokenUpTo += ready.count

        // Разметку снимаем всегда: на экране её человек не видел, и вслух
        // ей взяться неоткуда. «Звёздочка звёздочка важно» — не ответ.
        // Следом чистим то, что снятие разметки переживает, но голосом
        // не читается: маркеры списка, адреса, эмодзи — см. `SpokenText`.
        let spoken = SpokenText.clean(MarkdownRender.plain(ready))
        guard !spoken.isEmpty else { return }
        enqueue(spoken)
    }

    /// Поток кончился: остаток дочитывается, даже если он без точки на конце.
    func finishStream(answer: String) {
        isStreamOver = true
        speak(answer: answer)
        if pending == 0 {
            // Читать было нечего — пустой ответ или одна разметка. Сообщить
            // всё равно надо, иначе заход завис бы в «отвечаю» навсегда.
            finished()
        }
    }

    /// Оборвать речь — кнопкой в вырезе или новым заходом.
    ///
    /// О завершении при этом не сообщаем: заход обрывает тот, кто нажал
    /// кнопку, и он же решает, что делать дальше. Счётчик обнуляется
    /// до остановки — отменённые реплики придут делегату, и без этого
    /// они увели бы его в минус.
    func stop() {
        guard synthesizer.isSpeaking || isSpeaking || pending > 0 else { return }
        pending = 0
        isStreamOver = false
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        DebugLog.write("голос: чтение прервано")
    }

    func shutdown() {
        pending = 0
        isStreamOver = false
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func enqueue(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = Self.voice(language: language, identifier: voiceIdentifier)
        pending += 1
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func finished() {
        guard isSpeaking || isStreamOver else { return }
        isSpeaking = false
        isStreamOver = false
        DebugLog.write("голос: ответ дочитан")
        onFinish?()
    }

    // MARK: - Голос

    /// Лучший голос для языка.
    ///
    /// Выбирается по качеству, а не берётся первый попавшийся: у русского
    /// в системе есть и компактная Milena, и нейронный премиальный голос,
    /// и разница между ними — это разница между «робот читает» и «человек
    /// говорит». Заданный руками важнее: человек выбрал сам.
    static func voice(language: Language, identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return best(for: language)
    }

    /// Голоса, установленные в системе для этого языка, лучшие первыми.
    static func voices(for language: Language) -> [AVSpeechSynthesisVoice] {
        let prefix = String(language.locale.identifier.prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
    }

    static func best(for language: Language) -> AVSpeechSynthesisVoice? {
        voices(for: language).first
    }

    /// Имя голоса для списка — с пометкой качества.
    ///
    /// Одного имени мало: системные имена ничего не говорят. Русский
    /// нейронный голос зовётся «Голос 2», и по названию не отличить его
    /// от компактной Milena — а это и есть разница между «человек говорит»
    /// и «робот читает». Пометка отвечает ровно на этот вопрос.
    static func title(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) — \(qualityName(voice.quality))"
    }

    private static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return t("премиальный")
        case .enhanced: return t("улучшенный")
        default: return t("компактный")
        }
    }

    // MARK: - Скорость

    /// Скорость чтения по ступеням: ноль — как у системы, дальше в обе
    /// стороны.
    ///
    /// Ступенями, а не готовым `rate`: у `AVSpeechUtterance` шкала своя
    /// и непрозрачная — умолчание не посередине между минимумом
    /// и максимумом, — и «скорость 0,5», записанная числом, означала бы
    /// разное в разных версиях системы.
    static func rate(forStep step: Int) -> Float {
        let base = AVSpeechUtteranceDefaultSpeechRate
        let span = step >= 0
            ? AVSpeechUtteranceMaximumSpeechRate - base
            : base - AVSpeechUtteranceMinimumSpeechRate
        let fraction = Float(step) / Float(rateSteps)
        return base + span * fraction
    }

    /// Сколько ступеней в каждую сторону от обычной скорости.
    static let rateSteps = 4
}

extension SpeechSpeaker: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        pending = max(0, pending - 1)
        // Очередь могла ещё не опуститься: поток приносит предложения
        // быстрее, чем они прочитываются. «Договорил» — это когда и очередь
        // пуста, и поток кончился.
        //
        // Считаем по своему счётчику, а не по `synthesizer.isSpeaking`:
        // в этот самый миг синтезатор ещё считает себя говорящим, условие
        // не выполнялось никогда — и полоса висела в вырезе после ответа
        // до самого перезапуска.
        guard pending == 0, isStreamOver else { return }
        finished()
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        pending = max(0, pending - 1)
        isSpeaking = pending > 0
    }
}

/// Нарезка потока на то, что уже можно читать вслух.
///
/// Отдельно от синтезатора, чтобы проверить тестом: без этого правило
/// «читаем целыми предложениями» пришлось бы ловить на слух.
enum SpeechChunker {
    /// Чем кончается кусок, который уже можно читать.
    ///
    /// **Только концы предложений.** Двоеточие и точка с запятой здесь
    /// побывали — казалось, что так первые слова зазвучат раньше. На слух
    /// вышло наоборот: каждый кусок — отдельная реплика синтезатора, и он
    /// **начинает интонацию заново** на каждой из них. Фраза, разорванная
    /// по двоеточию, звучит двумя огрызками, а не фразой. Ради полусекунды
    /// выигрыша ломалось главное — то, как ответ звучит.
    private static let enders: Set<Character> = [".", "!", "?", "…", "\n"]

    /// Короче этого кусок не отдаём, пока поток идёт.
    ///
    /// «Да.» отдельной репликой звучит обрывком: синтезатор произносит его
    /// с законченной интонацией и умолкает, а следом начинает заново.
    /// Дождаться следующего предложения дешевле, чем так разорвать ответ.
    static let minimumChunk = 40

    /// Та часть текста, которую уже можно отдать в озвучку.
    ///
    /// Пока поток идёт — только до последнего законченного предложения:
    /// хвост может дописаться. Когда поток кончился — всё целиком, точка
    /// там уже не появится.
    static func complete(in text: String, isFinal: Bool) -> String {
        if isFinal { return text }
        guard let last = text.lastIndex(where: { enders.contains($0) }) else { return "" }
        let ready = String(text[...last])
        // Короткий кусок ждёт продолжения — но только пока поток идёт.
        guard ready.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumChunk else {
            return ""
        }
        return ready
    }
}
