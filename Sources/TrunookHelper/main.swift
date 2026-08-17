import Foundation
import TrunookXPC

// MARK: - Реализация сервиса

final class HelperService: NSObject, TrunookHelperProtocol {
    private weak var connection: NSXPCConnection?
    private var observing = false

    init(connection: NSXPCConnection) {
        self.connection = connection
    }

    private var client: TrunookHelperClientProtocol? {
        connection?.remoteObjectProxy as? TrunookHelperClientProtocol
    }

    func fetchNowPlaying(withReply reply: @escaping (Data?) -> Void) {
        MediaRemote.shared.fetchNowPlaying { snapshot in
            reply(Self.encode(snapshot))
        }
    }

    func send(command: UInt32, withReply reply: @escaping (Bool) -> Void) {
        reply(MediaRemote.shared.send(command: command))
    }

    func setElapsed(_ elapsed: Double, withReply reply: @escaping (Bool) -> Void) {
        reply(MediaRemote.shared.setElapsed(elapsed))
    }

    func startObserving() {
        guard !observing else { return }
        observing = true

        let remote = MediaRemote.shared
        remote.registerForNotifications()

        // Слушаем оба центра. MediaRemote не документирован, и в какой
        // из них он рассылает — неизвестно; подписка на оба стоит копейки
        // и снимает вопрос. Журнал ниже покажет, какой канал сработал.
        for symbol in [MediaRemote.Notifications.infoDidChange,
                       MediaRemote.Notifications.isPlayingDidChange] {
            let name = remote.notificationName(symbol)
            NotificationCenter.default.addObserver(
                self, selector: #selector(mediaDidChange), name: name, object: nil
            )
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(mediaDidChange), name: name, object: nil
            )
            DebugLog.write("хелпер: подписка на \(name.rawValue)")
        }
    }

    func stopObserving() {
        guard observing else { return }
        observing = false
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        MediaRemote.shared.unregisterFromNotifications()
    }

    @objc private func mediaDidChange(_ notification: Notification) {
        DebugLog.write("хелпер: уведомление \(notification.name.rawValue)")
        MediaRemote.shared.fetchNowPlaying { [weak self] snapshot in
            self?.client?.nowPlayingDidChange(Self.encode(snapshot))
        }
    }

    private static func encode(_ snapshot: NowPlaying?) -> Data? {
        guard let snapshot else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(snapshot)
    }
}

// MARK: - Слушатель XPC

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: TrunookHelperProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: TrunookHelperClientProtocol.self)

        let service = HelperService(connection: connection)
        connection.exportedObject = service
        connection.invalidationHandler = { service.stopObserving() }
        connection.interruptionHandler = { service.stopObserving() }
        connection.resume()
        return true
    }
}

// MARK: - Точка входа

// Режим спайка: запуск бинарника напрямую из бандла .xpc печатает диагностику.
// Это и есть проверка обхода ограничения MediaRemote — процесс получает
// bundle id из Info.plist рядом с исполняемым файлом.
if CommandLine.arguments.contains("--probe") {
    let bundleID = Bundle.main.bundleIdentifier ?? "<нет>"
    print("bundle id: \(bundleID)")
    print("символы:   \(MediaRemote.shared.diagnostics)")

    let done = DispatchSemaphore(value: 0)
    MediaRemote.shared.fetchNowPlaying { snapshot in
        if let snapshot {
            print("---")
            print("трек:      \(snapshot.title ?? "—")")
            print("артист:    \(snapshot.artist ?? "—")")
            print("альбом:    \(snapshot.album ?? "—")")
            print("источник:  \(snapshot.bundleIdentifier ?? "—")")
            print("играет:    \(snapshot.isPlaying)")
            let position = snapshot.position().map { String(format: "%.1f", $0) } ?? "—"
            let duration = snapshot.duration.map { String(format: "%.1f", $0) } ?? "—"
            print("позиция:   \(position) / \(duration)")
            print("обложка:   \(snapshot.artwork.map { "\($0.count) байт" } ?? "—")")
            print("---")
            print(snapshot.isEmpty ? "РЕЗУЛЬТАТ: пусто — данных нет" : "РЕЗУЛЬТАТ: данные получены")
        } else {
            print("РЕЗУЛЬТАТ: пусто — MediaRemote ничего не вернул")
        }
        done.signal()
    }
    _ = done.wait(timeout: .now() + 5)
    exit(0)
}

let delegate = ListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
