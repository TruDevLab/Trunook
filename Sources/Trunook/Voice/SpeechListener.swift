import TrunookXPC
import AVFoundation
import Foundation
import Speech

/// Слушает микрофон и переводит речь в текст.
///
/// **Распознаёт на самом компьютере** — `requiresOnDeviceRecognition = true`.
/// Проверено до того, как это было заложено в устройство: для `ru-RU`
/// и `en-US` система отдаёт `supportsOnDeviceRecognition = true`. Это
/// то же правило, на котором стоит вся остальная работа с моделью: наружу
/// уходит только погода.
///
/// Отдаёт наружу три вещи, и все три нужны:
///
/// - **текст по мере набора** — им живёт панель, если её открыли;
/// - **уровень громкости** — по нему видно, что тебя слышат. Одно свечение
///   этого не показывает: оно светилось бы одинаково и при выключенном
///   микрофоне, и при говорящем человеке;
/// - **признак «замолчал»** — по нему вопрос уходит модели.
final class SpeechListener: NSObject, ObservableObject {
    /// Что услышано на эту секунду. Частичный результат, а не окончательный:
    /// окончательного пришлось бы ждать до конца речи.
    @Published private(set) var text = ""

    /// Громкость последнего куска звука, от нуля до единицы.
    @Published private(set) var level: Double = 0

    @Published private(set) var isListening = false

    /// Речь закончилась — сказанное уходит наружу.
    var onFinish: ((String) -> Void)?
    /// Слушать не вышло. Причина уже человеческая, её показывают плашкой:
    /// молчаливый отказ неотличим от сломанного микрофона.
    var onFailure: ((String) -> Void)?

    /// Сколько тишины считается концом фразы.
    ///
    /// Полторы секунды — это пауза между мыслями, а не между словами.
    /// Меньше — и вопрос обрывается на середине, пока человек подбирает
    /// слово; больше — приходится ждать после того, как всё сказано.
    static let defaultSilence: TimeInterval = 1.5

    /// Сколько ждать **первого** слова.
    ///
    /// Заметно дольше, чем паузы внутри речи, и это не запас на всякий
    /// случай. Между жестом и первым словом человек делает то, чего внутри
    /// фразы уже не делает: убеждается, что вызов сработал, и соображает,
    /// как сформулировать. Полторы секунды на это не хватает — заход
    /// закрывался раньше, чем успевали открыть рот.
    ///
    /// Считается от обычной паузы, а не задаётся отдельным числом: настройка
    /// одна, и второе число разошлось бы с ней при первой же правке.
    static func leadIn(for silence: TimeInterval) -> TimeInterval {
        max(5, silence * 3)
    }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var silence: TimeInterval = defaultSilence
    /// Услышали ли хоть слово. Пока нет — ждём дольше.
    private var hasHeardAnything = false

    /// Отдали ли уже результат наружу.
    ///
    /// Концов у речи два — наш таймер тишины и собственное завершение задачи
    /// распознавания, — и прийти они могут оба. Без этого признака вопрос
    /// уходил бы модели дважды.
    private var hasFinished = false

    // MARK: - Начать и закончить

    func start(language: Language, silence: TimeInterval = defaultSilence) {
        guard !isListening else { return }
        self.silence = silence

        guard VoiceAccess.isReady else {
            onFailure?(t("Нужен доступ к микрофону и распознаванию речи"))
            return
        }

        // Распознаватель заводится под язык, а не берётся один на всё время:
        // язык интерфейса меняют на ходу, и вопрос по-русски, поданный
        // английскому распознавателю, превращается в набор созвучий.
        let locale = language.locale
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            onFailure?(t("Распознавание речи для этого языка недоступно"))
            DebugLog.write("голос: нет распознавателя для \(locale.identifier)")
            return
        }

        // Речь остаётся на этом компьютере. Если система локально не умеет,
        // честнее отказать вслух, чем молча отправить голос наружу.
        guard recognizer.supportsOnDeviceRecognition else {
            DebugLog.write("голос: локальное распознавание недоступно для \(locale.identifier)")
            onFailure?(t("Локальное распознавание для этого языка не установлено"))
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        text = ""
        level = 0
        hasFinished = false
        hasHeardAnything = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Нулевая частота — верный признак того, что входа нет: микрофон
        // занят, отключён или доступ на самом деле не выдан. Без проверки
        // `installTap` роняет приложение исключением.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onFailure?(t("Микрофон недоступен"))
            DebugLog.write("голос: у входа нет формата — микрофона нет")
            cleanUp()
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.noteLevel(of: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            onFailure?(t("Не удалось включить микрофон"))
            DebugLog.write("голос: движок не запустился — \(error.localizedDescription)")
            cleanUp()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let heard = result.bestTranscription.formattedString
                self.text = heard
                // Первое же слово переводит отсчёт на обычную паузу: длинное
                // ожидание нужно было ровно до того, как человек заговорил.
                if !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.hasHeardAnything = true
                }
                // Слова идут — значит человек говорит: отсчёт тишины
                // начинается заново.
                self.restartSilenceTimer()
            }
            if error != nil || result?.isFinal == true {
                self.finish()
            }
        }

        isListening = true
        restartSilenceTimer()
        DebugLog.write("голос: слушаю на \(locale.identifier)")
    }

    /// Закончить и отдать сказанное — то же, что делает пауза в речи.
    ///
    /// Пустой результат тоже отдаётся: наверху из него получится внятное
    /// «ничего не расслышал». Промолчать нельзя — человек звал ассистента
    /// и ждёт хоть какого-то ответа.
    func finish() {
        guard isListening, !hasFinished else { return }
        hasFinished = true
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanUp()
        DebugLog.write("голос: услышано \(heard.count) симв.")
        onFinish?(heard)
    }

    /// Бросить заход, ничего не отдавая, — Esc или повторный вызов.
    func cancel() {
        guard isListening else { return }
        hasFinished = true
        cleanUp()
        DebugLog.write("голос: слушать перестал, сказанное отброшено")
    }

    func shutdown() {
        cleanUp()
    }

    // MARK: - Внутреннее

    private func cleanUp() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        // Снимать отвод до остановки движка: снятый после — оставляет
        // висящий обработчик, который продолжает кормить закрытый запрос.
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil
        isListening = false
        level = 0
    }

    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        // До первого слова ждём дольше: человеку надо убедиться, что вызов
        // сработал, и собраться с мыслью. Дальше — обычная пауза между
        // фразами.
        let wait = hasHeardAnything ? silence : Self.leadIn(for: silence)
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            self?.finish()
        }
        // `.common`: на обычной очереди отсчёт тишины замирал бы, пока
        // человек держит открытым чужое меню или тянет ползунок.
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    /// Громкость куска звука — среднеквадратичная, а не пиковая.
    ///
    /// Пиковая скачет от каждого щелчка и рисует дёрганую шкалу; RMS даёт
    /// то, что человек и слышит как громкость.
    private func noteLevel(of buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let normalized = SpeechLevel.normalize(rms: Double(rms))

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            // Сглаживание: голос прыгает между слогами, а шкала, скачущая
            // в такт слогам, читается как помеха, а не как громкость.
            self.level = SpeechLevel.smooth(previous: self.level, next: normalized)
        }
    }
}

/// Перевод громкости в то, что видно глазом.
///
/// Отдельно от слушателя, чтобы проверить тестом: сам слушатель без живого
/// микрофона не поднять, а шкала, которая молчит на речи или упирается
/// в потолок на шёпоте, — это в точности то, за чем сюда и смотрят.
enum SpeechLevel {
    /// Ниже этого — тишина. Комнатный шум держится около −55 дБ.
    static let floorDecibels: Double = -55

    /// Из линейной величины в долю от нуля до единицы.
    ///
    /// Через децибелы, а не напрямую: речь в линейной шкале жмётся к нулю,
    /// и шкала стояла бы почти неподвижно всё время разговора.
    static func normalize(rms: Double) -> Double {
        let decibels = 20 * log10(max(rms, 0.000_001))
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }

    /// Насколько новое значение перебивает прежнее.
    static let smoothing: Double = 0.4

    static func smooth(previous: Double, next: Double) -> Double {
        previous * (1 - smoothing) + next * smoothing
    }
}
