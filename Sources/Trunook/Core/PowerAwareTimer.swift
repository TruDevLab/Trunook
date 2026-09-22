import Combine
import Foundation

/// Повторяющийся опрос с двумя шагами: обычным и для энергосбережения.
///
/// Сам следит за `PowerPreference` и переставляет шаг, когда режим
/// включается или выключается, — службе не нужно ни подписываться, ни
/// пересоздавать таймер (`ENERGY.md`, Р3). Допуск — десятая доля шага,
/// как у всех фоновых опросов (`Timer.allowCoalescing`).
final class PowerAwareTimer {
    private let normal: TimeInterval
    private let saving: TimeInterval
    private let action: () -> Void
    private var timer: Timer?
    private var observation: AnyCancellable?

    init(every normal: TimeInterval, whenSaving saving: TimeInterval, action: @escaping () -> Void) {
        self.normal = normal
        self.saving = saving
        self.action = action
        schedule(saving: PowerPreference.shared.saving)
        // `$saving` отдаёт новое значение ещё до записи — его и берём.
        observation = PowerPreference.shared.$saving
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.schedule(saving: $0) }
    }

    func invalidate() {
        observation = nil
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func schedule(saving isSaving: Bool) {
        timer?.invalidate()
        let timer = Timer(timeInterval: isSaving ? saving : normal, repeats: true) { [weak self] _ in
            self?.action()
        }
        timer.allowCoalescing()
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
