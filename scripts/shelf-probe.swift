// Прототип полки: можно ли вырастить окно приёма посреди перетаскивания.
//
//   swift scripts/shelf-probe.swift
//
// Что уже выяснено предыдущими заходами:
//   — приёмник обязан стоять не выше kCGDraggingWindowLevel (500): на этом
//     уровне живёт окно с картинкой перетаскиваемого файла, и приёмник над ней
//     система целью не считает. 500 принимает, 501 уже нет;
//   — перекрытие меню-бара приёму не мешает;
//   — окно уровня 1000 над полосой не мешает тоже, ни в каком состоянии;
//   — прозрачность для мыши и приём файлов — один выключатель:
//     ignoresMouseEvents = true убивает приём, а hitTest = nil нажатия
//     всё равно съедает. Значит полоса приёма может быть только шириной
//     с чёлку, где под ней и так пусто.
//
// Отсюда последний вопрос: ронять файлы надо в раскрытую панель полки,
// а она ниже чёлки. Проверяем приём «на вырост»: окно начинается размером
// с чёлку, а по первому draggingEntered растёт до панели.
//
// Пишет в stdout. Останавливается по Ctrl+C.

import AppKit

func log(_ text: String) {
    let stamp = DateFormatter()
    stamp.dateFormat = "HH:mm:ss.SSS"
    print("[\(stamp.string(from: Date()))] \(text)")
    fflush(stdout)
}

/// Размер раскрытой полки — во что окно вырастает на время перетаскивания.
let grownSize = CGSize(width: 460, height: 260)

final class DropView: NSView {
    var isDragActive = false { didSet { needsDisplay = true } }
    var updateCount = 0
    /// Куда вырасти и куда вернуться — считает владелец.
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]
        registerForDraggedTypes(types)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = isDragActive ? .systemGreen : .systemRed
        color.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updateCount = 0
        log("draggingEntered в точке \(sender.draggingLocation) — растём")
        onEnter?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateCount += 1
        // Журнал не должен захлебнуться: важна не каждая точка, а то,
        // приходят ли обновления ниже исходной полосы.
        if updateCount % 15 == 0 {
            log("draggingUpdated №\(updateCount), точка в окне: \(sender.draggingLocation), размер окна: \(bounds.size)")
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragActive = false
        log("draggingExited после \(updateCount) обновлений — схлопываемся")
        onLeave?()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragActive = false
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        log("ПРИНЯЛ \(urls.count) шт. в точке \(sender.draggingLocation), размер окна: \(bounds.size)")
        for url in urls { log("    \(url.lastPathComponent)") }
        onLeave?()
        return !urls.isEmpty
    }
}

final class ProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Delegate: NSObject, NSApplicationDelegate {
    private var window: ProbePanel?
    private var collapsedFrame: NSRect = .zero
    private var grownFrame: NSRect = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            log("экрана нет")
            exit(1)
        }
        let f = screen.frame

        // Ширина чёлки: экран минус две области меню-бара по бокам от неё.
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = left > 0 && right > 0 ? f.width - left - right : 200
        let notchHeight = max(screen.safeAreaInsets.top, 32)

        collapsedFrame = NSRect(
            x: f.midX - notchWidth / 2,
            y: f.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        grownFrame = NSRect(
            x: f.midX - grownSize.width / 2,
            y: f.maxY - grownSize.height,
            width: grownSize.width,
            height: grownSize.height
        )

        let window = ProbePanel(
            contentRect: collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = DropView(frame: NSRect(origin: .zero, size: collapsedFrame.size))
        view.onEnter = { [weak self] in
            guard let self else { return }
            self.window?.setFrame(self.grownFrame, display: true)
        }
        view.onLeave = { [weak self] in
            guard let self else { return }
            self.window?.setFrame(self.collapsedFrame, display: true)
        }
        window.contentView = view
        let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .string]
        window.registerForDraggedTypes(types)
        window.orderFrontRegardless()
        self.window = window

        log("чёлка: ширина \(notchWidth), высота \(notchHeight)")
        log("полоса приёма: \(collapsedFrame)")
        log("вырастает в: \(grownFrame)")
        log("ведите файл на чёлку, потом спуститесь ниже неё и там отпустите")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
