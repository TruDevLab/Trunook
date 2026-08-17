import CoreGraphics
import Foundation

/// Распознаёт поглаживание: курсор ходит по чёлке из стороны в сторону.
///
/// Считаются не события мыши, а развороты: важно, что рука ведёт туда-обратно,
/// а не сколько раз система прислала координату. Ход засчитывается только
/// после ощутимого пути в одну сторону — иначе дрожание руки на месте
/// набирало бы поглаживания само.
final class PettingDetector {
    /// Насколько нужно отойти от крайней точки, чтобы разворот засчитался.
    /// Чёлка шириной около двухсот точек, так что ход в тридцать —
    /// это заметное движение, а не подрагивание.
    private static let minimumStroke: CGFloat = 32
    /// Сколько ходов подряд будят кота. «Больше трёх раз из стороны в сторону».
    private static let strokesToPurr = 4
    /// Пауза, после которой набранное сбрасывается: гладят непрерывно,
    /// а не по одному движению в секунду.
    private static let idleTimeout: TimeInterval = 1.4

    private(set) var isPurring = false

    /// Куда идёт курсор: +1 вправо, −1 влево, 0 — направление ещё не задано.
    private var direction: CGFloat = 0
    /// Самая дальняя точка в текущем направлении.
    private var extreme: CGFloat?
    private var strokes = 0
    private var lastStrokeAt = Date.distantPast

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?

    func update(x: CGFloat, now: Date = Date()) {
        // Рука остановилась — начинаем счёт заново. Проверка привязана
        // к набранным ходам, поэтому после сброса сюда больше не попадаем.
        if strokes > 0, now.timeIntervalSince(lastStrokeAt) > Self.idleTimeout {
            reset()
        }

        guard let previous = extreme else {
            extreme = x
            return
        }

        guard direction != 0 else {
            guard abs(x - previous) >= Self.minimumStroke else { return }
            direction = x > previous ? 1 : -1
            extreme = x
            register(at: now)
            return
        }

        let advance = (x - previous) * direction
        if advance > 0 {
            // Едем дальше в ту же сторону: двигаем крайнюю точку.
            extreme = x
        } else if -advance >= Self.minimumStroke {
            direction = -direction
            extreme = x
            register(at: now)
        }
    }

    func reset() {
        direction = 0
        extreme = nil
        strokes = 0
        guard isPurring else { return }
        isPurring = false
        onStop?()
    }

    private func register(at now: Date) {
        strokes += 1
        lastStrokeAt = now
        guard !isPurring, strokes >= Self.strokesToPurr else { return }
        isPurring = true
        onStart?()
    }
}
