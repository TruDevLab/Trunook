import AppKit
import TrunookXPC

/// Приложение музыки, которое запускается из плитки, когда ничего не играет.
///
/// Без него «играть» при тишине отдаётся MediaRemote наугад: система будит
/// последний игравший плеер или «Музыку» Apple, даже если слушают в другом.
enum MusicPlayer {
    /// «Музыка» Apple — есть на любом Mac, поэтому и по умолчанию.
    static let fallback = "com.apple.Music"

    /// Известные плееры. В выбор попадают только установленные; чего нет
    /// в списке — выбирается через «Другое…».
    static let known = [
        fallback,
        "ru.yandex.desktop.music",
        "com.spotify.client",
        "com.tidal.desktop",
        "com.deezer.deezer-desktop",
        "com.coppertino.Vox",
        "com.swinsian.Swinsian",
        "com.apple.podcasts",
    ]

    static func url(for bundleID: String) -> URL? {
        guard !bundleID.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Имя для подписи: локализованное, без «.app».
    static func name(for bundleID: String) -> String? {
        url(for: bundleID).map(name(of:))
    }

    static func name(of url: URL) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }

    /// Что показать в выборе: известные установленные по порядку списка
    /// и выбранный, если его в списке нет, — иначе меню показало бы пустоту.
    static func choices(selected: String, isInstalled: (String) -> Bool) -> [String] {
        var result = known.filter(isInstalled)
        if !selected.isEmpty, !result.contains(selected) { result.append(selected) }
        return result
    }

    /// Плееры со словарём AppleScript: им «play» говорится прямо.
    static let scriptable: Set<String> = [fallback, "com.spotify.client"]

    /// Подписи кнопки «играть» и соседней «назад» в окне плеера — по ним
    /// кнопка ищется у тех, кто AppleScript не знает (Яндекс Музыка).
    static let playLabels = ["Воспроизведение", "Играть", "Слушать", "Play", "播放"]
    static let previousLabels = ["Предыдущая песня", "Предыдущий трек", "Previous song", "Previous track", "上一首"]

    /// Сколько ждать окна плеера после запуска: Electron грузит страницу
    /// несколько секунд.
    static let launchTimeout: TimeInterval = 15

    private static let scriptQueue = DispatchQueue(label: "com.trunook.music-player")

    /// Запустить выбранный плеер и включить музыку.
    ///
    /// Одного запуска мало: плеер открывается молча, MediaRemote пуст,
    /// и вырез так и пишет «Ничего не играет». Общая команда «играть»
    /// MediaRemote тут не годится — без играющего система будит «Музыку»
    /// Apple, а адресная команда молчащему плееру отвечает «нечего играть»
    /// (проверено на Яндекс Музыке). Поэтому — AppleScript, где он есть,
    /// и кнопка «играть» в окне плеера, где его нет.
    /// Пропавший плеер заменяется «Музыкой» Apple, а не молчанием.
    static func start(_ bundleID: String) {
        guard let url = url(for: bundleID) ?? url(for: fallback) else {
            DebugLog.write("музыка: плеер \(bundleID) не найден")
            return
        }
        let target = Bundle(url: url)?.bundleIdentifier ?? bundleID
        DebugLog.write("музыка: запуск \(name(of: url))")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                if let error {
                    DebugLog.write("музыка: не запустился — \(error.localizedDescription)")
                } else if scriptable.contains(target) {
                    playByScript(target)
                } else if let app {
                    pressPlay(pid: app.processIdentifier, deadline: Date().addingTimeInterval(launchTimeout))
                }
            }
        }
    }

    private static func playByScript(_ bundleID: String) {
        scriptQueue.async {
            var error: NSDictionary?
            _ = NSAppleScript(source: "tell application id \"\(bundleID)\" to play")?.executeAndReturnError(&error)
            if let error {
                DebugLog.write("музыка: play не прошёл — \(error[NSAppleScript.errorMessage] ?? error)")
            }
        }
    }

    /// Ждёт окна плеера и нажимает «играть» в его панели управления.
    ///
    /// Нажатие — фокусом и пробелом (`AXTree.focusAndKey`): страница
    /// Electron, как и страница встречи, `AXPress` не слышит.
    private static func pressPlay(pid: pid_t, deadline: Date) {
        guard AXTree.isTrusted else {
            DebugLog.write("музыка: нет Универсального доступа — плеер открыт, но не включён")
            return
        }
        let app = AXTree.application(pid: pid)
        for window in AXTree.windows(of: app) {
            let labels = AXTree.buttons(of: window).map { (element: $0.element, labels: $0.labels) }
            if let index = playButton(in: labels.map(\.labels)) {
                let pressed = AXTree.focusAndKey(labels[index].element, pid: pid, keyCode: 49)
                DebugLog.write("музыка: нажата «\(labels[index].labels.first ?? "")», фокус \(pressed)")
                return
            }
        }
        guard Date() < deadline else {
            DebugLog.write("музыка: кнопка «играть» не найдена — плеер открыт, но не включён")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pressPlay(pid: pid, deadline: deadline)
        }
    }

    /// Какая из кнопок окна — «играть» панели управления: та, что идёт
    /// следом за «назад». Кнопки «Воспроизведение» на обложках ленты стоят
    /// раньше и рядом с «назад» не бывают.
    static func playButton(in buttons: [[String]]) -> Int? {
        func matches(_ labels: [String], _ list: [String]) -> Bool {
            labels.contains { label in list.contains { label.localizedCaseInsensitiveCompare($0) == .orderedSame } }
        }
        guard let previous = buttons.firstIndex(where: { matches($0, previousLabels) }) else { return nil }
        let next = previous + 1
        guard next < buttons.count, matches(buttons[next], playLabels) else { return nil }
        return next
    }
}

/// Установленные плееры для выбора в настройках.
///
/// Отдельным объектом по той же причине, что и `BrowserList`: перебор идёт
/// в Launch Services, а тело SwiftUI пересчитывается сколько угодно раз.
/// Обновляется при открытии настроек и после «Другое…».
final class MusicPlayerList: ObservableObject {
    struct Player: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    @Published private(set) var items: [Player] = []

    func refresh(selected: String) {
        let found = MusicPlayer.choices(selected: selected) { MusicPlayer.url(for: $0) != nil }
        items = found.map { Player(bundleID: $0, name: MusicPlayer.name(for: $0) ?? tf("%@ — не найден", $0)) }
    }
}
