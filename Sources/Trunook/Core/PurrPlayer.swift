import TrunookXPC
import AVFoundation

/// Мурчание: звучит, пока вырез гладят.
///
/// Громкость намеренно низкая, а начало и конец сглажены: резко включённый
/// звук читается как системное уведомление, а не как отклик на движение руки.
final class PurrPlayer {
    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var target: Float = 0

    /// Потолок громкости. Это пасхалка, её не должно быть слышно из-за стены.
    private static let fullVolume: Float = 0.14
    /// Шаг и период нарастания дают примерно треть секунды на разгон.
    private static let fadeStep: Float = 0.014
    private static let fadeInterval: TimeInterval = 0.03

    func start() {
        guard let player = prepared() else { return }
        target = Self.fullVolume
        if !player.isPlaying {
            player.volume = 0
            player.currentTime = 0
            player.play()
        }
        runFade()
    }

    func stop() {
        guard player != nil, target != 0 else { return }
        target = 0
        runFade()
    }

    /// Резкая остановка без затухания — на выходе из приложения.
    func shutdown() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        player?.stop()
        target = 0
    }

    // MARK: - Внутреннее

    private func prepared() -> AVAudioPlayer? {
        if let player { return player }
        guard let url = Bundle.main.url(forResource: "purr", withExtension: "wav") else {
            DebugLog.write("мурчание: purr.wav нет в бандле")
            return nil
        }
        do {
            let created = try AVAudioPlayer(contentsOf: url)
            // Петля бесконечная: файл склеен так, что стык не слышен.
            created.numberOfLoops = -1
            created.volume = 0
            created.prepareToPlay()
            player = created
            return created
        } catch {
            DebugLog.write("мурчание: не открылось — \(error.localizedDescription)")
            return nil
        }
    }

    private func runFade() {
        guard fadeTimer == nil else { return }
        let timer = Timer(timeInterval: Self.fadeInterval, repeats: true) { [weak self] _ in
            self?.stepFade()
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
    }

    private func stepFade() {
        guard let player else {
            fadeTimer?.invalidate()
            fadeTimer = nil
            return
        }

        if abs(player.volume - target) <= Self.fadeStep {
            player.volume = target
        } else {
            player.volume += player.volume < target ? Self.fadeStep : -Self.fadeStep
        }

        guard player.volume == target else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        // Дошли до тишины — снимаем воспроизведение, чтобы не крутить
        // беззвучную петлю впустую.
        if target == 0 { player.stop() }
    }
}
