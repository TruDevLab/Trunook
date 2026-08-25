import Foundation

/// Короткое подтверждение внутри открытой панели.
///
/// Нужно потому, что обычные плашки событий (`ActivityCenter`) из-под накладки
/// не видны вовсе: накладка важнее плашки по расчёту состояния выреза и просто
/// занимает её место. Сохранив ответ в заметки, человек не видел ничего —
/// действие выглядело как не сработавшее, и его повторяли, заводя вторую
/// такую же запись.
///
/// Живёт в своём объекте, а не в панели: `@State` в этом тулчейне недоступен,
/// а гаснуть подтверждение должно само, по времени.
final class PanelFlash: ObservableObject {
    @Published private(set) var text: String?

    /// Сколько держится. Полторы секунды — успеть прочесть три слова
    /// и не начать мешать.
    private static let lifetime: TimeInterval = 1.6

    private var timer: Timer?

    func show(_ text: String) {
        self.text = text
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.lifetime, repeats: false) { [weak self] _ in
            self?.clear()
        }
        // В `.common`: на обычной очереди подтверждение зависало бы на всё
        // время, пока человек держит мышь на кнопке.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clear() {
        timer?.invalidate()
        timer = nil
        text = nil
    }
}
