import TrunookXPC
import AppKit
import SwiftUI

/// Окно залпа: во весь экран, поверх всего, живёт пару секунд.
///
/// Отдельным окном, а не внутри выреза, и причина не в удобстве. Окно выреза
/// прибито к верхней кромке и ровно того размера, какой посчитал `NotchSizing`:
/// бумажке в нём некуда лететь, а растянуть его на экран нельзя — под чёлкой
/// откроется незакрашенная полоса рабочего стола.
final class ConfettiWindowController {
    private var window: NSWindow?

    /// Пускает залп из-под чёлки.
    ///
    /// Молчит при включённом «уменьшить движение»: летящие через весь экран
    /// бумажки — ровно то, ради чего эту настройку и включают.
    func fire() {
        guard !MotionPreference.shared.reduceMotion else {
            DebugLog.write("конфетти: движение уменьшено, залпа нет")
            return
        }
        guard let geometry = NotchGeometry.current() else { return }
        close()

        let screen = geometry.screen
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        // Обязательно и без исключений. Непрозрачное для мыши окно съедает
        // нажатия во всей своей рамке, а рамка здесь — весь экран: на две
        // секунды человек остался бы без единой кнопки в любом приложении.
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // Порядок важен: сеттер `isFloatingPanel` сам ставит уровень
        // `.floating`, поэтому свой уровень назначается строго после него.
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        // Вылет — из-под нижней кромки чёлки, по её середине. Координаты окна
        // считаются от левого верхнего угла, экранные — от левого нижнего.
        let origin = CGPoint(
            x: geometry.notchRect.midX - screen.frame.minX,
            y: screen.frame.maxY - geometry.notchRect.minY
        )
        let hosting = NSHostingView(
            rootView: ConfettiView(origin: origin, started: Date())
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: false)
        // Без отбора фокуса: залп идёт поверх чужой работы и не должен её
        // прерывать. По той же причине так устроено и окно выреза.
        panel.orderFrontRegardless()

        window = panel
        DebugLog.write("конфетти: залп из чёлки")

        // Небольшой запас сверх срока залпа: последний кадр должен успеть
        // нарисоваться, иначе бумажки пропадают не догаснув.
        DispatchQueue.main.asyncAfter(deadline: .now() + Confetti.duration + 0.3) { [weak self] in
            self?.close()
        }
    }

    /// Залп и снимок его середины.
    ///
    /// Иначе вёрстку залпа не проверить вовсе: снимок экрана целиком сессии
    /// недоступен — нет разрешения «Запись экрана», — а окно рисует свой слой
    /// в файл и без него. Подложка на снимке прозрачная: она и на экране такая.
    func snapshotMidflight() {
        fire()
        DispatchQueue.main.asyncAfter(deadline: .now() + Confetti.duration / 2) { [weak self] in
            WindowSnapshot.write(self?.window, named: "confetti")
        }
    }

    private func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}
