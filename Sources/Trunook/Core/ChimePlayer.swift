import TrunookXPC
import AVFoundation

/// Одиночный сигнал окончания таймера.
///
/// Отдельно от `PurrPlayer`, хотя оба играют файл из бандла: мурчание живёт
/// петлёй с нарастанием и затуханием, а здесь нужен ровно один удар. Общий
/// на двоих тип пришлось бы уговаривать не зацикливать и не гасить.
final class ChimePlayer {
    private var player: AVAudioPlayer?

    /// Громкость. Заметно, но не пугающе: сигнал сообщает о факте, а не
    /// требует внимания как будильник.
    private static let volume: Float = 0.55

    func play() {
        guard let player = prepared() else { return }
        // Перевод в начало нужен, чтобы два подряд окончания — работа
        // и следом перерыв — звучали оба, а не только первое.
        player.currentTime = 0
        // Отказ разбирается: молчащий сигнал ничем не отличается от
        // выключенного, и без записи в журнал искать причину было бы негде.
        guard player.play() else {
            DebugLog.write("сигнал: воспроизвести не удалось")
            return
        }
    }

    /// Резкая остановка — на выходе из приложения.
    func shutdown() {
        player?.stop()
        player = nil
    }

    private func prepared() -> AVAudioPlayer? {
        if let player { return player }
        guard let url = Bundle.main.url(forResource: "chime", withExtension: "wav") else {
            DebugLog.write("сигнал: chime.wav нет в бандле")
            return nil
        }
        do {
            let made = try AVAudioPlayer(contentsOf: url)
            made.volume = Self.volume
            made.prepareToPlay()
            player = made
            return made
        } catch {
            DebugLog.write("сигнал: не открыть chime.wav — \(error.localizedDescription)")
            return nil
        }
    }
}
