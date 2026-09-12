import TrunookXPC
import AppKit
import Foundation

/// Ловит двойное нажатие модификатора и зовёт голосовой заход.
///
/// Не через `HotKeyCenter`, и это не выбор из удобства: `RegisterEventHotKey`
/// умеет только «модификаторы плюс обычная клавиша». Жест, состоящий
/// из одного модификатора, Carbon выразить не может вовсе.
///
/// Отсюда две цены, обе известны заранее:
///
/// - **Нужен Универсальный доступ.** Монитор событий без него не получает
///   нажатий — ровно то, о чём предупреждает шапка `HotKeyCenter`.
/// - **Монитор молчит, пока открыто меню чужого приложения или пока
///   что-то тащат.** Свойство глобальных мониторов, уже описанное
///   в `DEVELOPMENT.md`. Для голоса терпимо: с раскрытым чужим меню
///   ассистента не зовут.
///
/// Взамен жест **ничего не отбирает у набора текста**: модификатор сам
/// по себе не печатает ничего, в отличие от любого короткого сочетания.
final class VoiceHotKey {
    /// Позвали голос.
    var onTrigger: (() -> Void)?

    private var monitors: [Any] = []
    private var gesture: DoubleTapModifier?

    /// Перечитывает настройки и заводит слежение заново.
    ///
    /// Как `installHotKeys` у остальных вызовов: набор пересобирается после
    /// каждой правки настроек, а не подстраивается на ходу.
    func install(_ trigger: VoiceTrigger, isEnabled: Bool) {
        stop()
        guard isEnabled else { return }

        // Жест один. Прежде их было два — обычный вопрос и вопрос
        // по заметкам, — и половина этого класса уходила на то, чтобы они
        // не наступали друг другу на ноги. Теперь заметки не отдельный
        // вход, а инструмент, и второму жесту стало нечего звать.
        guard let flag = trigger.flag else { return }
        gesture = DoubleTapModifier(flag: flag)

        // Флаги ловим и глобально, и локально: глобальный монитор молчит
        // о событиях, ушедших в наше же окно, а вырез забирает фокус, когда
        // в нём открыта панель.
        let flagEvents: NSEvent.EventTypeMask = [.flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: flagEvents, handler: {
            [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: flagEvents, handler: {
            [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }

        // Обычные клавиши и щелчки — не сам жест, но его отмена. ⌃C — это
        // ⌃ вниз, C, ⌃ вверх, и без этой отметки второе копирование подряд
        // звало бы ассистента.
        let otherEvents: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: otherEvents, handler: {
            [weak self] _ in
            self?.noteOtherInput()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: otherEvents, handler: {
            [weak self] event in
            self?.noteOtherInput()
            return event
        }) {
            monitors.append(local)
        }

        DebugLog.write("голос: слежу за \(trigger.title)")
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        gesture = nil
    }

    private func handle(_ event: NSEvent) {
        guard gesture?.flagsChanged(to: event.modifierFlags, at: Date()) == true else { return }
        DebugLog.write("голос: позван двойным нажатием")
        onTrigger?()
    }

    private func noteOtherInput() {
        gesture?.otherInput()
    }
}
