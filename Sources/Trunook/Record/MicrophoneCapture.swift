import TrunookXPC
import AVFoundation
import Foundation

/// Пишет микрофон в файл.
///
/// Отдельно от `SpeechListener`, хотя оба слушают тот же вход: тот кормит
/// распознавание кусками и ничего не хранит, а здесь нужна дорожка целиком.
/// Свести их в один класс не выйдет — у них разная жизнь: голосовой заход
/// длится секунды и обрывается тишиной, запись встречи идёт час и кончается
/// только по команде.
///
/// **Одновременно с голосовым заходом не работает.** Два движка на одном
/// входе система разводит непредсказуемо: то делит звук, то отдаёт его
/// первому. Кто кого не пускает — решает `RecorderService`, здесь для этого
/// нет ни знания, ни права.
final class MicrophoneCapture {
    /// Громкость последнего куска, от нуля до единицы. Ею живёт полоска
    /// в вырезе: без неё не отличить идущую запись от молчащего микрофона.
    var onLevel: ((Double) -> Void)?

    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var isRunning = false

    /// Сколько всего записано. Считается по кадрам, а не по часам: часы
    /// врут при засыпании крышки, а кадры — это ровно то, что в файле.
    private(set) var frames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(frames) / sampleRate
    }

    // MARK: - Запись

    /// Начинает писать в файл по указанному пути.
    ///
    /// Формат берётся у самого входа, а не задаётся своим: у встроенного
    /// микрофона он один, у внешней карты другой, и навязанный формат
    /// заставил бы систему пересчитывать поток на лету — лишняя работа
    /// на час записи. Сведение всё равно будет потом, в один заход.
    func start(to url: URL) -> Bool {
        guard !isRunning else { return true }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Нулевая частота — верный признак того, что входа нет: микрофон
        // занят, отключён или доступ на самом деле не выдан. Без проверки
        // `installTap` роняет приложение исключением. Та же ловушка, что
        // в `SpeechListener`.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            DebugLog.write("запись: у входа нет формата — микрофона нет")
            return false
        }

        do {
            file = try AVAudioFile(forWriting: url, settings: format.settings)
        } catch {
            DebugLog.write("запись: файл микрофона не открылся — \(error.localizedDescription)")
            return false
        }
        frames = 0
        sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.write(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            DebugLog.write("запись: движок не запустился — \(error.localizedDescription)")
            cleanUp()
            return false
        }

        isRunning = true
        DebugLog.write("запись: микрофон пошёл, \(Int(format.sampleRate)) Гц")
        return true
    }

    /// Останавливает запись и закрывает файл.
    func stop() {
        guard isRunning else { return }
        let seconds = Int(duration)
        cleanUp()
        DebugLog.write("запись: микрофон остановлен, \(seconds) с")
    }

    // MARK: - Внутреннее

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let file else { return }
        do {
            try file.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
        } catch {
            DebugLog.write("запись: кусок не записался — \(error.localizedDescription)")
        }
        report(level: buffer)
    }

    /// Громкость — среднеквадратичная, как в голосовом заходе: пиковая
    /// скачет от каждого щелчка и рисует дёрганую шкалу.
    private func report(level buffer: AVAudioPCMBuffer) {
        guard onLevel != nil, let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for index in 0..<count {
            let sample = channel[index]
            sum += sample * sample
        }
        let normalized = SpeechLevel.normalize(rms: Double(sqrt(sum / Float(count))))

        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(normalized)
        }
    }

    /// Снимать отвод до остановки движка: снятый после — оставляет висящий
    /// обработчик, который продолжает писать в закрытый файл.
    private func cleanUp() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        file = nil
        isRunning = false
    }
}
