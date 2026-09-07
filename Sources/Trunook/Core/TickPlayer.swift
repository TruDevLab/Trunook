import TrunookXPC
import AVFoundation

/// Щелчок деления шкалы таймера.
///
/// Отдельно от `ChimePlayer`, хотя оба играют файл из бандла и оба короткие.
/// Разница в том, как часто их просят: сигнал звучит раз в двадцать пять
/// минут, а щелчок — по нескольку раз в секунду, пока тянут шкалу. Отсюда
/// два отличия, ради которых и заведён свой тип.
///
/// **Проигрывателей несколько, а не один.** Одиночному приходится перед
/// каждым щелчком возвращаться в начало, и предыдущий обрывается на полпути:
/// при быстром вращении слышен не ряд щелчков, а треск. Три по очереди дают
/// каждому догореть свои двенадцать миллисекунд.
///
/// **Частые просьбы отбрасываются.** Быстрое движение пальца проезжает
/// деления чаще, чем ухо их различает, и звук сливается в шум. Ближе
/// тридцати миллисекунд друг к другу щелчки не звучат — движение при этом
/// остаётся слышным, но перестаёт быть трещоткой.
final class TickPlayer {
    private var players: [AVAudioPlayer] = []
    private var next = 0
    private var lastPlayed: TimeInterval = 0

    /// Тише сигнала окончания вдвое: щелчок сопровождает движение руки,
    /// а не сообщает о событии.
    private static let volume: Float = 0.28
    /// Сколько проигрывателей по кругу. Три — это тридцать шесть миллисекунд
    /// звучания подряд, вчетверо больше порога ниже.
    private static let voices = 3
    /// Ближе этого щелчки не звучат.
    private static let minimumGap: TimeInterval = 0.03

    func play() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayed >= Self.minimumGap else { return }
        lastPlayed = now

        guard prepare() else { return }
        let player = players[next]
        next = (next + 1) % players.count
        player.currentTime = 0
        guard player.play() else {
            DebugLog.write("щелчок: воспроизвести не удалось")
            return
        }
    }

    /// Резкая остановка — на выходе из приложения.
    func shutdown() {
        players.forEach { $0.stop() }
        players = []
    }

    private func prepare() -> Bool {
        if !players.isEmpty { return true }
        guard let url = Bundle.main.url(forResource: "tick", withExtension: "wav") else {
            DebugLog.write("щелчок: tick.wav нет в бандле")
            return false
        }
        do {
            for _ in 0..<Self.voices {
                let made = try AVAudioPlayer(contentsOf: url)
                made.volume = Self.volume
                made.prepareToPlay()
                players.append(made)
            }
            return true
        } catch {
            DebugLog.write("щелчок: не открыть tick.wav — \(error.localizedDescription)")
            players = []
            return false
        }
    }
}
