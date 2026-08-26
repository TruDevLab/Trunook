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
    /// Позвали обычный голосовой вопрос или вопрос по заметкам.
    var onTrigger: ((_ usesNotes: Bool) -> Void)?

    private var monitors: [Any] = []
    private var plain: DoubleTapModifier?
    private var withNotes: DoubleTapModifier?

    /// Перечитывает настройки и заводит слежение заново.
    ///
    /// Как `installHotKeys` у остальных вызовов: набор пересобирается после
    /// каждой правки настроек, а не подстраивается на ходу.
    func install(plain: VoiceTrigger, withNotes: VoiceTrigger, isEnabled: Bool) {
        stop()
        guard isEnabled else { return }

        // Один и тот же модификатор на оба вызова означал бы, что второй
        // не позвать никогда: сработал бы тот, кого проверяют первым.
        let plainFlag = plain.flag
        let sameModifier = withNotes.flag == plain.flag && plain.flag != nil
        let notesFlag = sameModifier ? nil : withNotes.flag
        if sameModifier {
            DebugLog.write("голос: оба вызова на одном модификаторе — второй отключён")
        }

        self.plain = plainFlag.map { DoubleTapModifier(flag: $0) }
        self.withNotes = notesFlag.map { DoubleTapModifier(flag: $0) }
        guard self.plain != nil || self.withNotes != nil else { return }

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

        DebugLog.write(
            "голос: слежу за \(plain.title)" + (notesFlag != nil ? " и \(withNotes.title)" : "")
        )
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        plain = nil
        withNotes = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags
        let time = Date()
        // Оба спрашиваются всегда, а не «первый сработал — второго
        // не спрашиваем»: чужой модификатор обязан сбить начатый счёт
        // и у соседа тоже, иначе ⌃ посреди двойного ⌥ его не отменит.
        let plainFired = plain?.flagsChanged(to: flags, at: time) ?? false
        let notesFired = withNotes?.flagsChanged(to: flags, at: time) ?? false

        if plainFired {
            DebugLog.write("голос: позван двойным нажатием")
            onTrigger?(false)
        } else if notesFired {
            DebugLog.write("голос: позван двойным нажатием, по заметкам")
            onTrigger?(true)
        }
    }

    private func noteOtherInput() {
        plain?.otherInput()
        withNotes?.otherInput()
    }
}
