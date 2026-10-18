import TrunookXPC
import AppKit
import ApplicationServices
import SwiftUI

/// Окно, которое можно поставить в остаток экрана.
struct WindowCandidate: Identifiable {
    let id: CGWindowID
    let element: AXUIElement
    let appName: String
    let title: String
    let icon: NSImage?
}

/// Окна на экране, кроме уже разложенных, — спереди назад.
///
/// Порядок и рамки — из списка окон CoreGraphics: он отдаёт окна в порядке
/// наложения и не требует «Записи экрана», пока не просить заголовков.
/// Заголовок и сам элемент для перестановки — из Универсального доступа:
/// окно приложения ищется по совпадению рамки.
enum WindowCandidates {
    static func list(excluding excluded: [AXUIElement], limit: Int = 8) -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        var windowsByApp: [pid_t: [AXUIElement]] = [:]
        var result: [WindowCandidate] = []

        for entry in info {
            guard result.count < limit,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width >= 120, bounds.height >= 80,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }

            let windows = windowsByApp[pid] ?? DraggedWindow.windows(ofApp: pid)
            windowsByApp[pid] = windows
            // Рамка CoreGraphics и Универсального доступа — обе от левого
            // верхнего угла основного экрана, сравниваются напрямую.
            guard let element = windows.first(where: { matches($0, bounds) }) else { continue }
            if excluded.contains(where: { CFEqual($0, element) }) { continue }
            let title = DraggedWindow.title(of: element) ?? ""
            result.append(WindowCandidate(
                id: number,
                element: element,
                appName: app.localizedName ?? "",
                title: title.isEmpty ? (app.localizedName ?? "") : title,
                icon: app.icon
            ))
        }
        return result
    }

    private static func matches(_ element: AXUIElement, _ bounds: CGRect) -> Bool {
        guard let position = DraggedWindow.position(of: element), let size = DraggedWindow.size(of: element) else {
            return false
        }
        return abs(position.x - bounds.minX) <= 2 && abs(position.y - bounds.minY) <= 2
            && abs(size.width - bounds.width) <= 2 && abs(size.height - bounds.height) <= 2
    }
}

/// Выбор второго окна для остатка экрана.
final class WindowFillModel: ObservableObject {
    @Published var candidates: [WindowCandidate] = []
    @Published var highlighted: CGWindowID?
    var pick: (WindowCandidate) -> Void = { _ in }
    var dismiss: () -> Void = {}

    /// Сдвинуть подсветку на `step` карточек.
    func move(_ step: Int) {
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0.id == highlighted } ?? (step > 0 ? -1 : candidates.count)
        let next = min(max(index + step, 0), candidates.count - 1)
        highlighted = candidates[next].id
    }
}

/// Окно разложили на половину, треть, четверть или в угол — в свободном
/// месте сразу предлагаются другие окна. Щелчок по карточке ставит окно туда.
///
/// Уходит по Esc, крестику и любому щелчку мимо: предложение не должно
/// мешать, если второе окно не нужно.
final class WindowFillPicker {
    private let model = WindowFillModel()
    private var panel: NSPanel?
    private var monitors: [Any] = []

    var isShown: Bool { panel != nil }

    /// `frame` — остаток экрана в координатах AppKit.
    func show(_ candidates: [WindowCandidate], in frame: CGRect, title: String,
              onPick: @escaping (WindowCandidate) -> Void) {
        close()
        model.candidates = candidates
        model.highlighted = candidates.first?.id
        model.pick = { [weak self] candidate in
            self?.close()
            onPick(candidate)
        }
        model.dismiss = { [weak self] in self?.close() }

        let rect = frame.insetBy(dx: 10, dy: 10)
        let panel = KeyPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let hosting = NSHostingView(rootView: WindowFillView(model: model, title: title)
            .environment(\.colorScheme, .dark))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(rect, display: false)
        panel.alphaValue = 0
        // Ключевой — ради стрелок, Enter и Esc; приложение под ней
        // активность не теряет: панель не активирующая.
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchMotion.reduced ? 0.08 : 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKey(event) ?? event
        }) {
            monitors.append(local)
        }
        // Глобальный монитор ловит только нажатия, ушедшие в чужие
        // приложения, — то есть ровно «мимо».
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.close()
        }) {
            monitors.append(global)
        }
        DebugLog.write("окна: предложено \(candidates.count) окон на остаток \(NSStringFromRect(frame))")
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: close()
        case 36, 76:
            if let candidate = model.candidates.first(where: { $0.id == model.highlighted }) { model.pick(candidate) }
        case 123, 126: model.move(-1)
        case 124, 125: model.move(1)
        default: return event
        }
        return nil
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        guard let panel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    func snapshot() {
        WindowSnapshot.write(panel, named: "window-fill")
    }
}

struct WindowFillView: View {
    @ObservedObject var model: WindowFillModel
    /// Название остатка: «Правая половина».
    let title: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Что поставить рядом?"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button(action: model.dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Закрыть"))
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 10)], spacing: 10) {
                    ForEach(model.candidates) { card($0) }
                }
            }
            .scrollIndicators(.never)

            Text(t("Esc — оставить как есть"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            shape.fill(.black.opacity(0.6))
                .background(.ultraThinMaterial, in: shape)
        )
        .overlay(shape.strokeBorder(Palette.cyan.opacity(0.35), lineWidth: 1))
    }

    private func card(_ candidate: WindowCandidate) -> some View {
        let active = candidate.id == model.highlighted
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 6) {
            if let icon = candidate.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 44, height: 44)
            }
            Text(candidate.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if candidate.title != candidate.appName {
                Text(candidate.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(shape.fill(active ? Palette.cyan.opacity(0.2) : .white.opacity(0.07)))
        .overlay(shape.strokeBorder(Palette.cyan.opacity(active ? 0.8 : 0), lineWidth: 1))
        .contentShape(shape)
        .onHover { inside in
            if inside { model.highlighted = candidate.id }
        }
        .onTapGesture { model.pick(candidate) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
