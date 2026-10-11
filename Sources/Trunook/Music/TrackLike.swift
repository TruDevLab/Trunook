import AppKit
import Combine
import SwiftUI
import TrunookXPC

/// Лайк текущему треку — из мини-вида, плашки новой песни и плитки «Музыка».
///
/// Общего способа у системы нет: команду «Нравится» MediaRemote плееры
/// понимают через одного, и узнать по ней, стоит ли лайк, нельзя. Поэтому
/// способ — по играющему плееру (`Way`):
///
/// - «Музыка» Apple — AppleScript, свойство `favorited` текущего трека:
///   и поставить, и прочитать.
/// - Яндекс Музыка — флажок «Нравится» в панели управления окна, рядом
///   с «Предыдущая песня» (тем же путём, каким `MusicPlayer` нажимает
///   «Воспроизведение»). Состояние — значение флажка.
/// - Остальным сердечка нет. Команду MediaRemote «Нравится» (106) пробовали:
///   Яндекс Музыка её не слышит, а без плеера, который её понимает, система
///   будит «Музыку» Apple (проверено, 11 октября).
///
/// Окно Яндекс Музыки бывает закрыто — музыка играет в фоне. Тогда нажатие
/// открывает окно, не выводя вперёд, ждёт панель управления и жмёт флажок.
final class TrackLike: ObservableObject {
    static let shared = TrackLike()

    enum Way: Equatable {
        case appleScript
        case button
        case unsupported
    }

    /// Стоит ли лайк у текущего трека. `nil` — неизвестно.
    @Published private(set) var liked: Bool?

    private var trackKey: String?
    private var observation: AnyCancellable?
    private weak var music: MusicClient?
    private let queue = DispatchQueue(label: "com.trunook.track-like")

    /// Подписи флажка «Нравится» в окне веб-плеера.
    static let likeLabels = ["Нравится", "Мне нравится", "Like", "喜欢"]

    /// Способ для плеера.
    static func way(for bundleID: String?) -> Way {
        switch bundleID {
        case "com.apple.Music": return .appleScript
        case "ru.yandex.desktop.music": return .button
        default: return .unsupported
        }
    }

    /// Есть ли у играющего плеера лайк — от этого зависят и кнопка,
    /// и место под неё в расчёте ширины.
    static func supports(_ track: NowPlaying?) -> Bool {
        guard let track, !(track.title ?? "").isEmpty else { return false }
        return way(for: track.bundleIdentifier) != .unsupported
    }

    /// Какая из кнопок окна — «Нравится» панели управления: ближайшая
    /// перед «назад». Флажки «Нравится» на обложках ленты стоят раньше.
    static func likeButton(in buttons: [[String]]) -> Int? {
        func matches(_ labels: [String], _ list: [String]) -> Bool {
            labels.contains { label in list.contains { label.localizedCaseInsensitiveCompare($0) == .orderedSame } }
        }
        guard let previous = buttons.firstIndex(where: { matches($0, MusicPlayer.previousLabels) }),
              previous > 0
        else { return nil }
        for index in stride(from: previous - 1, through: max(0, previous - 3), by: -1)
        where matches(buttons[index], likeLabels) {
            return index
        }
        return nil
    }

    func start(music: MusicClient) {
        self.music = music
        observation = music.$nowPlaying
            .map { $0?.title }
            .removeDuplicates()
            .sink { [weak self] _ in
                // Сведения о треке приходят порциями — читаем чуть погодя.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.refresh() }
            }
    }

    /// Перечитать состояние лайка у текущего трека.
    func refresh() {
        guard let track = music?.nowPlaying, let title = track.title, !title.isEmpty else {
            trackKey = nil
            if liked != nil { liked = nil }
            return
        }
        let key = title + "|" + (track.artist ?? "")
        if key != trackKey {
            trackKey = key
            if liked != nil { liked = nil }
        }
        let bundleID = track.bundleIdentifier
        queue.async { [weak self] in
            let state = Self.read(bundleID: bundleID)
            DebugLog.write("музыка: лайк у «\(title)» — \(state.map { $0 ? "стоит" : "нет" } ?? "неизвестно") (\(Self.way(for: bundleID)))")
            DispatchQueue.main.async {
                guard let self, self.trackKey == key, let state, state != self.liked else { return }
                self.liked = state
            }
        }
    }

    /// Поставить или снять лайк.
    func toggle() {
        guard let track = music?.nowPlaying, let title = track.title, !title.isEmpty else { return }
        let bundleID = track.bundleIdentifier
        let target = !(liked ?? false)
        DebugLog.write("музыка: лайк \(target ? "ставим" : "снимаем") — \(Self.way(for: bundleID))")
        // Сразу на экране: ответ плеера приходит позже, а кнопка без отклика
        // кажется не нажатой.
        liked = target
        switch Self.way(for: bundleID) {
        case .unsupported:
            break
        case .appleScript:
            queue.async { [weak self] in
                Self.write(target, bundleID: bundleID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
            }
        case .button:
            pressInWindow(target, bundleID: bundleID, deadline: Date().addingTimeInterval(10), reopened: false)
        }
    }

    // MARK: - Плееры

    private static func read(bundleID: String?) -> Bool? {
        switch way(for: bundleID) {
        case .appleScript:
            let result = script("""
            tell application id "com.apple.Music"
                if player state is stopped then return "none"
                return (favorited of current track) as string
            end tell
            """)
            return result.map { $0 == "true" }
        case .button:
            guard let found = windowLikeButton(bundleID: bundleID) else { return nil }
            return value(of: found.element)
        case .unsupported:
            return nil
        }
    }

    private static func write(_ liked: Bool, bundleID: String?) {
        switch way(for: bundleID) {
        case .appleScript:
            _ = script("tell application id \"com.apple.Music\" to set favorited of current track to \(liked)")
        case .button:
            guard let found = windowLikeButton(bundleID: bundleID) else {
                DebugLog.write("музыка: флажок «Нравится» в окне плеера не найден")
                return
            }
            // Флажок переключается нажатием — жмём, только если он не там,
            // где должен оказаться.
            guard value(of: found.element) != liked else { return }
            // `AXPress` Chromium превращает в щелчок по элементу — работает
            // и в фоновом окне (проверено на Яндекс Музыке). Пробел с фокусом,
            // как у «Воспроизведения», здесь не годится: в фоновое окно
            // Chromium клавиши не пропускает. Запасным путём его не держим:
            // флажок отдаёт новое значение не сразу, и пробел вдогонку,
            // дойди он, вернул бы лайк обратно.
            let pressed = AXTree.press(found.element)
            DebugLog.write("музыка: флажок «Нравится» — AXPress \(pressed)")
        case .unsupported:
            break
        }
    }

    /// Флажок в окне; окна нет — открыть его в фоне и подождать.
    private func pressInWindow(_ target: Bool, bundleID: String?, deadline: Date, reopened: Bool) {
        queue.async { [weak self] in
            if Self.windowLikeButton(bundleID: bundleID) != nil {
                Self.write(target, bundleID: bundleID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
                return
            }
            DispatchQueue.main.async {
                guard Date() < deadline else {
                    DebugLog.write("музыка: окно плеера так и не открылось — лайк не поставлен")
                    self?.refresh()
                    return
                }
                if !reopened, let bundleID, let url = MusicPlayer.url(for: bundleID) {
                    DebugLog.write("музыка: окна плеера нет — открываю в фоне")
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.pressInWindow(target, bundleID: bundleID, deadline: deadline, reopened: true)
                }
            }
        }
    }

    private static func value(of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func windowLikeButton(bundleID: String?) -> (element: AXUIElement, pid: pid_t)? {
        guard AXTree.isTrusted, let bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        let pid = app.processIdentifier
        for window in AXTree.windows(of: AXTree.application(pid: pid)) {
            let buttons = AXTree.buttons(of: window)
            if let index = likeButton(in: buttons.map(\.labels)) {
                return (buttons[index].element, pid)
            }
        }
        return nil
    }

    private static func script(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DebugLog.write("музыка: лайк, AppleScript — \(error[NSAppleScript.errorMessage] ?? error)")
            return nil
        }
        return result?.stringValue
    }
}

/// Круглая кнопка-сердечко — в мини-виде, на плашке новой песни и на плитке.
struct TrackLikeButton: View {
    @ObservedObject var like = TrackLike.shared
    var diameter: CGFloat = ActivityView.answerDiameter

    var body: some View {
        let liked = like.liked == true
        Button { like.toggle() } label: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: NotchStyle.font(11), weight: .bold))
                .foregroundStyle(liked ? Palette.rose : .white.opacity(NotchStyle.primaryOpacity))
                .symbolSwap(liked)
                .symbolEffect(.bounce, value: liked)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(liked ? Palette.rose.opacity(0.2) : .white.opacity(0.14)))
        }
        .buttonStyle(NotchButtonStyle(diameter: diameter))
        .notchHint(liked ? t("Убрать лайк") : t("Нравится"))
    }
}
