import TrunookXPC
import AppKit
import Foundation

/// Ответ выреза на поглаживание: звук, вибрация и дрожь.
///
/// Отделено от распознавания намеренно: `NotchInput` решает, гладят ли,
/// а этот тип — как это выглядит и звучит.
final class PurrEffects {
    private let state: NotchState
    private let purr = PurrPlayer()
    private var hapticTimer: Timer?
    private var trembleTimer: Timer?

    init(state: NotchState) {
        self.state = state
    }

    func start() {
        state.isPurring = true
        purr.start()
        startHaptics()
        startTremble()
    }

    func stop() {
        state.isPurring = false
        purr.stop()
        stopHaptics()
        stopTremble()
    }

    func shutdown() {
        stopHaptics()
        stopTremble()
        purr.shutdown()
    }

    /// Отладочный вход: поглаживание курсором из скрипта не изобразить,
    /// а слушать звук и щупать вибрацию нужно.
    func run(seconds: TimeInterval) {
        DebugLog.write("отладка: мурчим \(Int(seconds)) с")
        start()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.stop()
        }
    }

    /// Настоящее мурчание — это частые толчки, а не ровный гул. Виброотклик
    /// системы такой частоты не даёт, поэтому берём самый мягкий рисунок
    /// и повторяем его так часто, как он успевает отрабатывать.
    private func startHaptics() {
        guard hapticTimer == nil else { return }
        Haptics.tap()
        let timer = Timer(timeInterval: 0.16, repeats: true) { _ in
            Haptics.tap()
        }
        RunLoop.main.add(timer, forMode: .common)
        hapticTimer = timer
    }

    private func stopHaptics() {
        hapticTimer?.invalidate()
        hapticTimer = nil
    }

    /// Дрожь острова. Частоты по осям намеренно разные и не кратные:
    /// одинаковые дали бы ровное качание по диагонали, а нужно живое
    /// подрагивание.
    private func startTremble() {
        guard trembleTimer == nil else { return }
        // Дрожь — то самое движение, от которого настройка и защищает.
        // Мурчание при этом остаётся: звук и виброотклик к движению
        // на экране отношения не имеют.
        guard !MotionPreference.shared.reduceMotion else { return }
        let started = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let time = Date().timeIntervalSince(started)
            // Вниз остров не уходит никогда: окно приклеено к верхней кромке
            // экрана, и смещение вниз открывает под чёлкой незакрашенную
            // полосу рабочего стола. Вверх уезжать безопасно — там экран
            // просто обрезает.
            self.state.tremble = CGSize(
                width: 0.7 * sin(time * 2 * .pi * 9),
                height: -0.45 + 0.45 * sin(time * 2 * .pi * 11.3 + 0.9)
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        trembleTimer = timer
    }

    private func stopTremble() {
        trembleTimer?.invalidate()
        trembleTimer = nil
        state.tremble = .zero
    }

    /// Одиночное вздрагивание — отклик на то, что случилось прямо сейчас.
    ///
    /// Живёт здесь, а не у того, кто его зовёт, потому что `state.tremble`
    /// один на весь вырез. Два владельца у одного поля разошлись бы
    /// в первом же случае, когда вздрогнуть попросили посреди мурчания:
    /// один затирал бы смещение другого, и остров дёргался бы рывками.
    ///
    /// Затухающее, а не ровное: ровное подрагивание в полсекунды читается
    /// как неисправность, а затухающее — как отклик.
    func jolt() {
        // Ровно то движение, от которого защищает настройка. Голосовой заход
        // от этого не страдает: он и без вздрагивания виден свечением.
        guard !MotionPreference.shared.reduceMotion else { return }
        // Мурчание важнее: оно идёт непрерывно, и вклиниваться в него
        // одиночным толчком значило бы его оборвать.
        guard trembleTimer == nil else { return }

        let started = Date()
        let duration: TimeInterval = 0.45
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let time = Date().timeIntervalSince(started)
            guard time < duration else {
                self.stopTremble()
                return
            }
            let decay = 1 - time / duration
            // Вниз остров не уходит: окно приклеено к верхней кромке,
            // и смещение вниз открывает под чёлкой незакрашенную полосу
            // рабочего стола.
            self.state.tremble = CGSize(
                width: 1.6 * decay * sin(time * 2 * .pi * 12),
                height: -1.0 * decay * abs(sin(time * 2 * .pi * 8))
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        trembleTimer = timer
    }
}
