import TrunookXPC
import AVFoundation
import Foundation

/// Сводит записанные дорожки в один файл.
///
/// **После остановки, а не на ходу.** Живое сведение потребовало бы
/// согласовать часы двух разных устройств: микрофон идёт по своим, отвод
/// звука системы — по часам устройства вывода, и расходятся они тем сильнее,
/// чем дольше запись. Офлайн этой задачи нет вовсе: каждая дорожка лежит
/// в файле целиком, а временные файлы всё равно удаляются следом.
///
/// **Моно и AAC.** Разговор слушают, чтобы вспомнить сказанное, а не ради
/// стереопанорамы. В хранилище Obsidian, где файл ляжет рядом с заметкой,
/// разница заметна: час без сжатия занял бы сотни мегабайт.
enum AudioMixdown {
    /// Частота сведённого файла.
    ///
    /// 16 кГц: расшифровка на устройстве всё равно приводит звук к этой
    /// частоте, а человеческая речь выше восьми килогерц ничего не теряет.
    /// Файл при этом заметно меньше, а слушать его так же разборчиво.
    static let sampleRate: Double = 16_000

    /// Поток сведённого файла. Речь при таком потоке разборчива полностью,
    /// а час разговора занимает около четырнадцати мегабайт.
    static let bitRate = 32_000

    /// Сколько кадров берётся за раз. Час записи не влезает в память
    /// целиком — сведение идёт кусками от начала к концу.
    private static let chunk = AVAudioFrameCount(8192)

    enum Failure: Error {
        /// Ни одна дорожка не открылась: сводить нечего.
        case noSources
        case cannotWrite
    }

    /// Сводит дорожки в один файл.
    ///
    /// Дорожек бывает одна — аудиозаметка пишет только микрофон. Отдельной
    /// ветки для этого случая нет намеренно: сложение одной дорожки ни с чем
    /// даёт её саму, и разводить два пути ради этого незачем.
    ///
    /// Дорожки разной длины — обычное дело: отвод звука системы стартует
    /// на мгновение позже микрофона. Короткая просто кончается раньше,
    /// длинная доигрывает до конца.
    static func mix(_ sources: [URL], to output: URL) throws {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )
        guard let target else { throw Failure.cannotWrite }

        let tracks = sources.compactMap { Track(url: $0, target: target) }
        guard !tracks.isEmpty else { throw Failure.noSources }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        let file = try AVAudioFile(forWriting: output, settings: settings)

        guard let mixed = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: chunk) else {
            throw Failure.cannotWrite
        }

        while true {
            let pieces = tracks.compactMap { $0.next(frames: chunk) }
            let length = pieces.map(\.frameLength).max() ?? 0
            guard length > 0 else { break }

            sum(pieces, into: mixed, length: length)
            try file.write(from: mixed)
        }

        DebugLog.write("запись: сведено дорожек — \(tracks.count) → \(output.lastPathComponent)")
    }

    /// Складывает куски дорожек в один.
    ///
    /// С ограничением по краям: сумма двух громких дорожек выходит за
    /// единицу, и без него на громких местах пошёл бы треск. Делить пополам
    /// вместо этого нельзя — тихая запись стала бы вдвое тише, а громкие
    /// места в разговоре редки.
    private static func sum(
        _ pieces: [AVAudioPCMBuffer],
        into mixed: AVAudioPCMBuffer,
        length: AVAudioFrameCount
    ) {
        guard let out = mixed.floatChannelData?[0] else { return }
        for index in 0..<Int(length) { out[index] = 0 }

        for piece in pieces {
            guard let data = piece.floatChannelData?[0] else { continue }
            for index in 0..<Int(piece.frameLength) {
                out[index] += data[index]
            }
        }

        for index in 0..<Int(length) {
            out[index] = min(max(out[index], -1), 1)
        }
        mixed.frameLength = length
    }

    /// Одна дорожка на чтении: файл, пересчёт формата и запас под кусок.
    private final class Track {
        private let file: AVAudioFile
        private let converter: AVAudioConverter
        private let source: AVAudioPCMBuffer
        private let target: AVAudioFormat
        private var isDone = false

        init?(url: URL, target: AVAudioFormat) {
            guard let file = try? AVAudioFile(forReading: url),
                  let converter = AVAudioConverter(from: file.processingFormat, to: target),
                  let source = AVAudioPCMBuffer(
                      pcmFormat: file.processingFormat, frameCapacity: AudioMixdown.chunk
                  )
            else {
                DebugLog.write("запись: дорожка \(url.lastPathComponent) не открылась")
                return nil
            }
            self.file = file
            self.converter = converter
            self.source = source
            self.target = target
        }

        /// Следующий кусок в общем формате. `nil` — дорожка кончилась.
        func next(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
            guard !isDone,
                  let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: frames)
            else { return nil }

            var error: NSError?
            let status = converter.convert(to: out, error: &error) { [self] _, outStatus in
                do {
                    try file.read(into: source)
                } catch {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard source.frameLength > 0 else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return source
            }

            if status == .endOfStream || status == .error { isDone = true }
            if let error {
                DebugLog.write("запись: пересчёт дорожки — \(error.localizedDescription)")
            }
            return out.frameLength > 0 ? out : nil
        }
    }
}
