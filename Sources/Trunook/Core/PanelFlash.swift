import Foundation
import SwiftUI

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

/// Сама плашка подтверждения — накладкой поверх содержимого панели.
///
/// Вынесена из панели модели, когда откладывать в заметки научилась и панель
/// буфера: подтверждение у них одно и то же, и второй раз рисовать его
/// значило бы завести вторую плашку, которая разойдётся с первой в цвете
/// и высоте при первой же правке.
///
/// Поверх содержимого, а не вместо строки: вместо строки — значит на полторы
/// секунды убрать то, чем человек прямо сейчас пользуется; поверх — ничего
/// не двигается, а не заметить всё равно нельзя.
struct PanelFlashPill: View {
    @ObservedObject var flash: PanelFlash

    var body: some View {
        if let text = flash.text {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: NotchStyle.font(10), weight: .semibold))
                Text(text)
                    .font(.system(size: NotchStyle.font(11), weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.positive)
            .padding(.horizontal, 9)
            .frame(height: NotchStyle.scaled(22))
            .background(Capsule().fill(.black.opacity(0.82)))
            .overlay(Capsule().strokeBorder(Palette.positive.opacity(0.35), lineWidth: 0.5))
            .padding(6)
            .allowsHitTesting(false)
        }
    }
}
