import TrunookXPC
import AppKit
import SwiftUI

/// Что показывает разметка прямо сейчас.
final class WindowSnapModel: ObservableObject {
    /// Плитка или отмена под курсором.
    @Published var target: WindowSnapBoard.Target?
    /// Окно отпустили над чёлкой — раскладку выбирают щелчком.
    @Published var clickMode = false

    var slot: WindowSlot? {
        if case let .slot(slot) = target { return slot }
        return nil
    }
}

/// Плитки раскладок прямо на экране — каждая на месте будущего окна.
/// Под курсором плитка загорается, а поверх рисуется контур окна в настоящем
/// размере.
///
/// Окно разметки — во весь экран, на ступень ниже окна выреза: поверх
/// перетаскиваемого окна, иначе оно закроет плитки, но под чёлкой.
/// Пока окно несут, разметка пропускает мышь насквозь — перенос ведёт
/// система, и нажатия разметке не нужны. В режиме щелчка она их ловит:
/// выбор там и делается щелчком, а Esc и щелчок мимо плиток — отмена.
final class WindowSnapScreen {
    let model = WindowSnapModel()
    /// Щелчок в режиме щелчка: по плитке, по отмене или мимо (`nil`).
    var onChoose: ((WindowSnapBoard.Target?) -> Void)?
    /// Esc в режиме щелчка.
    var onCancel: (() -> Void)?

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private(set) var layout: WindowSnapBoard.Layout?
    private(set) var screen: NSScreen?

    var isShown: Bool { panel != nil }

    private static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

    func show(on screen: NSScreen, notch: CGRect) {
        guard panel == nil else { return }
        self.screen = screen
        model.target = nil
        model.clickMode = false
        let full = screen.frame
        let layout = WindowSnapBoard.layout(screen: full, visible: screen.visibleFrame, notch: notch)
        self.layout = layout

        // Рамки окон — в координатах окна разметки, от левого верхнего угла.
        var frames: [WindowSlot: CGRect] = [:]
        for slot in WindowSlot.allCases {
            let rect = slot.frame(in: screen.visibleFrame)
            frames[slot] = CGRect(x: rect.minX - full.minX, y: full.maxY - rect.maxY, width: rect.width, height: rect.height)
        }

        let panel = KeyPanel(contentRect: full, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // Сеттер `isFloatingPanel` сам ставит уровень — свой строго после него.
        panel.isFloatingPanel = true
        panel.level = Self.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: WindowSnapScreenView(model: model, layout: layout, frames: frames)
            .environment(\.colorScheme, .dark))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(full, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchMotion.reduced ? 0.08 : 0.16
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        DebugLog.write("окна: разметка экрана \(NSStringFromRect(full))")
    }

    /// Окно отпустили над чёлкой: разметка остаётся, выбор — щелчком.
    func enterClickMode() {
        guard let panel, !model.clickMode else { return }
        model.clickMode = true
        panel.ignoresMouseEvents = false
        // Ключевым — ради Esc. Панель не активирующая: приложение под ней
        // не теряет активность, а клавиши идут разметке.
        panel.makeKey()
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            self?.handle(event) ?? event
        }) {
            monitors.append(local)
        }
        DebugLog.write("окна: разметка ждёт щелчка")
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown where event.keyCode == 53:
            onCancel?()
            return nil
        case .leftMouseDown where event.window === panel:
            onChoose?(target(at: NSEvent.mouseLocation))
            return nil
        case .rightMouseDown where event.window === panel:
            onCancel?()
            return nil
        default:
            return event
        }
    }

    /// Что под точкой экрана в координатах AppKit. `nil` — мимо плиток.
    func target(at point: CGPoint) -> WindowSnapBoard.Target? {
        guard let layout, let full = screen?.frame else { return nil }
        return WindowSnapBoard.target(at: CGPoint(x: point.x - full.minX, y: full.maxY - point.y), in: layout)
    }

    /// Курсор на экране разметки.
    func contains(_ point: CGPoint) -> Bool {
        screen?.frame.contains(point) == true
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        layout = nil
        screen = nil
        model.target = nil
        model.clickMode = false
    }

    /// Снимок разметки — проверить вёрстку без глаз человека.
    func snapshot() {
        WindowSnapshot.write(panel, named: "window-board")
    }
}

/// Панель без заголовка, которая может стать ключевой — ради клавиш.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Разметка экрана: плитки, отмена и контур будущего окна.
struct WindowSnapScreenView: View {
    @ObservedObject var model: WindowSnapModel
    let layout: WindowSnapBoard.Layout
    let frames: [WindowSlot: CGRect]

    var body: some View {
        let slot = model.slot
        ZStack(alignment: .topLeading) {
            // Лёгкая вуаль: на пёстром рабочем столе тонкие контуры иначе
            // теряются.
            Color.black.opacity(0.35)

            ForEach(WindowSnapBoard.cells, id: \.slot) { cell in
                if let rect = layout.tiles[cell.slot] {
                    tile(cell.slot, active: slot == cell.slot, dimmed: slot != nil && slot != cell.slot)
                        .place(rect.insetBy(dx: WindowSnapBoard.spacing / 2, dy: WindowSnapBoard.spacing / 2))
                }
            }

            contour(slot)

            cancel
                .place(layout.cancel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }

    /// Контур окна в настоящем размере. Нет плитки под курсором — гаснет
    /// и стягивается к отмене, откуда в следующий раз и вырастет.
    private func contour(_ slot: WindowSlot?) -> some View {
        let rect = slot.flatMap { frames[$0] }?.insetBy(dx: 3, dy: 3) ?? layout.cancel
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(Palette.cyan.opacity(0.1))
            .overlay(shape.strokeBorder(Palette.cyan, lineWidth: 3))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .opacity(slot == nil ? 0 : 1)
            // «Уменьшить движение» — контур не летит, а сменяется на месте.
            .animation(NotchMotion.reduced ? nil : .spring(duration: 0.3, bounce: 0.12), value: slot)
            .allowsHitTesting(false)
    }

    private func tile(_ slot: WindowSlot, active: Bool, dimmed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: 8) {
            miniature(slot, active: active)
                .frame(width: 46, height: 29)
            Text(slot.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(active ? 1 : dimmed ? 0.5 : 0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Без размытия подложки (энергоаудит 18 октября): восемнадцать
        // размытых плиток почти во весь экран сервер окон пересчитывал на
        // каждом движении под ними — а под ними как раз едет перетаскиваемое
        // окно. WindowServer поднимался с 5% до 20–44%. Заливка и так
        // плотная, размытие сквозь неё почти не видно.
        .background(shape.fill(active ? Palette.cyan.opacity(0.3) : .black.opacity(0.82)))
        .overlay(shape.strokeBorder(active ? Palette.cyan : .white.opacity(0.35), lineWidth: active ? 2 : 1))
        .animation(.easeOut(duration: 0.12), value: active)
        .animation(.easeOut(duration: 0.12), value: dimmed)
        .accessibilityLabel(slot.title)
    }

    /// Значок плитки — маленький экран с закрашенной долей окна.
    private func miniature(_ slot: WindowSlot, active: Bool) -> some View {
        Canvas { ctx, size in
            let screen = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let unit = slot.unit
            // Доля считается от левого нижнего угла, а холст рисует сверху.
            let window = CGRect(
                x: screen.minX + screen.width * unit.minX,
                y: screen.minY + screen.height * (1 - unit.maxY),
                width: screen.width * unit.width,
                height: screen.height * unit.height
            ).insetBy(dx: 2, dy: 2)
            ctx.stroke(Path(roundedRect: screen, cornerRadius: 4), with: .color(.white.opacity(0.6)), lineWidth: 1)
            ctx.fill(Path(roundedRect: window, cornerRadius: 2), with: .color(active ? Palette.cyan : .white.opacity(0.75)))
        }
    }

    /// Отмена — первой под чёлкой: случайно донёс окно до выреза — отпусти
    /// здесь или щёлкни, и ничего не случится.
    private var cancel: some View {
        let active = model.target == .cancel
        return HStack(spacing: 6) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
            Text(model.clickMode ? t("Отмена · Esc") : t("Отмена"))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(active ? .white : .white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(active ? Palette.rose.opacity(0.7) : .black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(active ? Palette.rose : .white.opacity(0.35), lineWidth: active ? 2 : 1))
        .animation(.easeOut(duration: 0.1), value: active)
        .accessibilityLabel(t("Отмена"))
    }
}

private extension View {
    /// Поставить вид в рамку от левого верхнего угла экрана.
    func place(_ frame: CGRect) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}
