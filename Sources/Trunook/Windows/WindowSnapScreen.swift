import TrunookXPC
import AppKit
import SwiftUI

/// Что показывает разметка прямо сейчас.
final class WindowSnapModel: ObservableObject {
    /// Плитка или отмена под курсором.
    @Published var target: WindowSnapBoard.Target?
    /// Окно отпустили над чёлкой — раскладку выбирают щелчком.
    @Published var clickMode = false
    /// На какой экран встанет окно — номер в ряду экранов слева направо.
    /// Выбор держится: навели на плашку экрана, повели к плитке — экран
    /// остался выбранным.
    @Published var screenIndex = 0
    /// Экран, на котором открыта разметка, — «этот».
    @Published var homeIndex = 0
    /// Подписи плашек экранов.
    @Published var screenNames: [String] = []

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
    /// Подсветка на других мониторах: рамка выбранного экрана и контур окна.
    private var targetPanels: [NSPanel] = []
    private var monitors: [Any] = []
    private(set) var layout: WindowSnapBoard.Layout?
    private(set) var screen: NSScreen?
    /// Мониторы слева направо — в том же порядке, что плашки.
    private(set) var screens: [NSScreen] = []

    /// Экран, на который встанет окно: выбранный плашкой или этот.
    var targetScreen: NSScreen? {
        screens.indices.contains(model.screenIndex) ? screens[model.screenIndex] : screen
    }

    var isShown: Bool { panel != nil }

    private static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)

    func show(on screen: NSScreen, notch: CGRect) {
        guard panel == nil else { return }
        self.screen = screen
        model.target = nil
        model.clickMode = false
        // Порядок — как мониторы стоят на столе: слева направо, при равенстве
        // сверху вниз. Плашки читаются картой, а не списком.
        let ordered = NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.maxY > $1.frame.maxY
        }
        screens = ordered
        let home = ordered.firstIndex { $0 == screen } ?? 0
        model.homeIndex = home
        model.screenIndex = home
        model.screenNames = Self.names(ordered, home: home)
        let full = screen.frame
        let layout = WindowSnapBoard.layout(screen: full, visible: screen.visibleFrame, notch: notch,
                                            screenCount: ordered.count)
        self.layout = layout

        let panel = Self.makePanel(frame: full)
        let hosting = NSHostingView(rootView: WindowSnapScreenView(model: model, layout: layout,
                                                                   frames: Self.frames(on: screen))
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

        // На остальных мониторах — прозрачные окна, которые оживают, только
        // когда их экран выбран: рамка и контур окна там, где оно встанет.
        for (index, other) in ordered.enumerated() where index != home {
            let target = Self.makePanel(frame: other.frame)
            let view = WindowSnapTargetView(
                model: model, index: index,
                visible: Self.local(other.visibleFrame, in: other.frame),
                frames: Self.frames(on: other)
            )
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
            host.sizingOptions = []
            target.contentView = host
            target.setFrame(other.frame, display: false)
            target.orderFrontRegardless()
            targetPanels.append(target)
        }
        DebugLog.write("окна: разметка экрана \(NSStringFromRect(full)), мониторов \(ordered.count)")
    }

    private static func makePanel(frame: CGRect) -> KeyPanel {
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // Сеттер `isFloatingPanel` сам ставит уровень — свой строго после него.
        panel.isFloatingPanel = true
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Рамка в координатах окна на экране — от его левого верхнего угла.
    private static func local(_ rect: CGRect, in full: CGRect) -> CGRect {
        CGRect(x: rect.minX - full.minX, y: full.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Рамки окон по всем раскладкам — в координатах окна на этом экране.
    private static func frames(on screen: NSScreen) -> [WindowSlot: CGRect] {
        var frames: [WindowSlot: CGRect] = [:]
        for slot in WindowSlot.allCases {
            frames[slot] = local(slot.frame(in: screen.visibleFrame), in: screen.frame)
        }
        return frames
    }

    /// Подписи плашек: «Этот экран», у остальных — имя монитора со стрелкой,
    /// где он стоит относительно этого. Два одинаковых монитора различает
    /// стрелка, а одинаковые и по стрелке — номер.
    static func names(_ screens: [NSScreen], home: Int) -> [String] {
        let frames = screens.map(\.frame)
        return SnapScreenNames.names(frames: frames, titles: screens.map(\.localizedName), home: home)
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
        targetPanels.forEach { $0.orderOut(nil); $0.contentView = nil }
        targetPanels.removeAll()
        screens = []
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

            contour(model.screenIndex == model.homeIndex ? slot : nil)

            cancel
                .place(layout.cancel)

            ForEach(Array(layout.screens.enumerated()), id: \.offset) { index, rect in
                screenChip(index)
                    .place(rect)
            }
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

    /// Плашка экрана. Выбранная — залита: туда встанет окно. Под курсором —
    /// обведена ярче.
    private func screenChip(_ index: Int) -> some View {
        let chosen = model.screenIndex == index
        let hovered = model.target == .screen(index)
        let name = model.screenNames.indices.contains(index) ? model.screenNames[index] : ""
        return HStack(spacing: 6) {
            Image(systemName: index == model.homeIndex ? "laptopcomputer" : "display")
                .font(.system(size: 12, weight: .semibold))
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(chosen ? .white : .white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(chosen ? Palette.cyan.opacity(0.35) : .black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(chosen || hovered ? Palette.cyan : .white.opacity(0.35),
                                        lineWidth: chosen || hovered ? 2 : 1))
        .animation(.easeOut(duration: 0.12), value: chosen)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
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

/// Выбранный монитор: рамка по рабочей области, имя сверху и контур окна
/// в настоящем размере. Пока выбран другой экран — ничего не рисует.
struct WindowSnapTargetView: View {
    @ObservedObject var model: WindowSnapModel
    let index: Int
    let visible: CGRect
    let frames: [WindowSlot: CGRect]

    var body: some View {
        let chosen = model.screenIndex == index
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack(alignment: .topLeading) {
            if chosen {
                shape
                    .strokeBorder(Palette.cyan.opacity(0.8), lineWidth: 4)
                    .place(visible.insetBy(dx: 6, dy: 6))
                if let slot = model.slot, let rect = frames[slot] {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.cyan.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.cyan, lineWidth: 3))
                        .place(rect.insetBy(dx: 3, dy: 3))
                }
                Text(model.slot.map { tf("Окно встанет сюда: %@", $0.title) } ?? t("Окно встанет на этот экран"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(.black.opacity(0.82)))
                    .overlay(Capsule().strokeBorder(Palette.cyan, lineWidth: 1.5))
                    .frame(width: visible.width)
                    .offset(x: visible.minX, y: visible.minY + 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .animation(NotchMotion.reduced ? nil : .easeOut(duration: 0.15), value: chosen)
        .animation(NotchMotion.reduced ? nil : .spring(duration: 0.3, bounce: 0.12), value: model.slot)
        .allowsHitTesting(false)
    }
}

/// Подписи плашек экранов — чистая функция под тестом.
enum SnapScreenNames {
    /// Куда сдвинут монитор: прямо или по диагонали. Диагональ — когда меньший
    /// сдвиг больше двух пятых большего: два монитора над ноутбуком, левее
    /// и правее, иначе оба читались бы «↑» или один «↑», другой «→».
    /// `dy` — вверх, как в AppKit.
    static func arrow(dx: CGFloat, dy: CGFloat) -> String {
        let big = max(abs(dx), abs(dy)), small = min(abs(dx), abs(dy))
        if big > 0, small / big > 0.4 {
            switch (dx < 0, dy > 0) {
            case (true, true): return "↖"
            case (false, true): return "↗"
            case (true, false): return "↙"
            case (false, false): return "↘"
            }
        }
        return abs(dx) >= abs(dy) ? (dx < 0 ? "←" : "→") : (dy > 0 ? "↑" : "↓")
    }

    /// `frames` — рамки мониторов в порядке плашек, `titles` — их имена,
    /// `home` — номер экрана с разметкой.
    static func names(frames: [CGRect], titles: [String], home: Int) -> [String] {
        guard frames.indices.contains(home) else { return titles }
        let center = CGPoint(x: frames[home].midX, y: frames[home].midY)
        var labels = frames.enumerated().map { index, frame -> String in
            guard index != home else { return t("Этот экран") }
            return "\(arrow(dx: frame.midX - center.x, dy: frame.midY - center.y)) \(titles[index])"
        }
        // Одинаковые подписи — с номером по порядку.
        let original = labels
        var seen: [String: Int] = [:]
        for (index, label) in original.enumerated() where original.filter({ $0 == label }).count > 1 {
            seen[label, default: 0] += 1
            labels[index] = "\(label) \(seen[label]!)"
        }
        return labels
    }
}

private extension View {
    /// Поставить вид в рамку от левого верхнего угла экрана.
    func place(_ frame: CGRect) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}
