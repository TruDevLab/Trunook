import AppKit
import SwiftUI
import TrunookXPC

/// Ручка, которой файл вытаскивают с полки.
///
/// Модификатор SwiftUI `.onDrag` здесь не работает вовсе: он заводит сессию
/// перетаскивания только из окна, которое становится ключевым, а вырез
/// намеренно фокус не отбирает — на этом держится сценарий «выделил текст,
/// спросил у модели, вставил обратно». Плитка с `.onDrag` просто не двигалась.
/// Поэтому сессия заводится вручную, средствами AppKit.
///
/// Заодно решается и вторая задача: `NSDraggingSource` сообщает, когда
/// перетаскивание закончилось. Без этого конец приходилось бы ловить опросом
/// кнопки мыши — события при перетаскивании файлов до мониторов не доходят.
struct ShelfDragOut: NSViewRepresentable {
    let item: ShelfItem
    let icon: NSImage
    let onBegin: () -> Void
    /// Перетаскивание кончилось. Аргумент — ушёл ли файл на самом деле.
    let onEnd: (Bool) -> Void
    let onClick: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    func makeNSView(context: Context) -> ShelfDragOutView {
        let view = ShelfDragOutView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: ShelfDragOutView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: ShelfDragOutView) {
        view.item = item
        view.icon = icon
        view.onBegin = onBegin
        view.onEnd = onEnd
        view.onClick = onClick
        view.onReveal = onReveal
        view.onRemove = onRemove
        view.rebuildMenu()
    }
}

/// Прозрачная накладка поверх плитки: ловит нажатие, перетаскивание
/// и правую кнопку.
final class ShelfDragOutView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var icon: NSImage?
    var onBegin: (() -> Void)?
    var onEnd: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onReveal: (() -> Void)?
    var onRemove: (() -> Void)?

    /// Откуда начали тянуть. Ниже порога это ещё нажатие, а не перетаскивание:
    /// без порога любое дрожание руки на плитке уносило бы файл.
    private var pressedAt: NSPoint?
    private static let dragThreshold: CGFloat = 4
    /// Размер картинки, которая едет за курсором.
    private static let dragImageSide: CGFloat = 48

    // MARK: - Мышь

    /// Вырез — неактивное окно и ключевым не становится намеренно. Без этого
    /// разрешения первое нажатие уходило бы на активацию окна, а до вида
    /// не доходило вовсе — и файл не сдвинулся бы с места.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
        DebugLog.write("полка: нажатие на плитке")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressedAt, let item else { return }
        let moved = hypot(
            event.locationInWindow.x - pressedAt.x,
            event.locationInWindow.y - pressedAt.y
        )
        guard moved >= Self.dragThreshold else { return }
        self.pressedAt = nil
        beginDrag(item: item, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        // Кнопку отпустили, не сдвинувшись — значит это было нажатие.
        if pressedAt != nil { onClick?() }
        pressedAt = nil
    }

    private func beginDrag(item: ShelfItem, event: NSEvent) {
        let dragItem = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let side = Self.dragImageSide
        let origin = convert(event.locationInWindow, from: nil)
        dragItem.setDraggingFrame(
            CGRect(x: origin.x - side / 2, y: origin.y - side / 2, width: side, height: side),
            contents: icon
        )
        beginDraggingSession(with: [dragItem], event: event, source: self)
        DebugLog.write("полка: выдача «\(item.name)» начата")
        onBegin?()
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Наружу — перемещением, а не копией: полка отдаёт файл насовсем,
        // и в исходной папке его после этого быть не должно. Сам перенос
        // выполняет принимающая сторона; нам остаётся снять запись с полки,
        // когда система подтвердит, что файл ушёл.
        //
        // Внутри своего же приложения — ничего: под полкой лежит её
        // собственная зона приёма, и без этого запрета вынесенный файл
        // немедленно возвращался бы обратно на полку.
        context == .outsideApplication ? [.move, .delete] : []
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // «Ушёл» — не то же самое, что «получатель отчитался о переносе».
        // Часть приложений сообщает .move, но файл не трогает, часть
        // переносит и отвечает пустой операцией. Верим диску: если по старому
        // пути пусто, файл действительно переехал.
        let reported = operation.contains(.move) || operation.contains(.delete)
        let gone = item.map { !$0.exists } ?? false
        let moved = reported || gone
        DebugLog.write(
            "полка: выдача закончена, операция \(operation.rawValue), "
            + "по старому пути \(gone ? "пусто" : "файл на месте")"
        )
        onEnd?(moved)
    }

    // MARK: - Меню правой кнопки

    /// Меню собирается на AppKit, а не модификатором `contextMenu`: накладка
    /// лежит поверх плитки и правую кнопку до SwiftUI уже не пропустит.
    func rebuildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: t("Открыть"), action: #selector(menuOpen), keyEquivalent: "")
        menu.addItem(withTitle: t("Показать в Finder"), action: #selector(menuReveal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: t("Убрать с полки"), action: #selector(menuRemove), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        self.menu = menu
    }

    @objc private func menuOpen() { onClick?() }
    @objc private func menuReveal() { onReveal?() }
    @objc private func menuRemove() { onRemove?() }
}
