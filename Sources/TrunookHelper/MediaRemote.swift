import Foundation
import AppKit
import TrunookXPC

/// Тонкая обёртка над приватным MediaRemote.framework.
///
/// Начиная с macOS 15.4 Apple ограничила `MRMediaRemoteGetNowPlayingInfo`:
/// обычный процесс получает пустой словарь. Доступ остаётся у процессов,
/// чей bundle id начинается с `com.apple.controlcenter.`, поэтому весь этот
/// код живёт в отдельном XPC-сервисе с таким идентификатором — так же,
/// приложениями того же рода.
///
/// Всё связывание позднее, через dlsym: если Apple уберёт символ,
/// отвалится ровно одна функция, а не всё приложение.
final class MediaRemote {
    static let shared = MediaRemote()

    private let handle: UnsafeMutableRawPointer?

    // Сигнатуры приватных функций.
    private typealias GetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias SetElapsed = @convention(c) (Double) -> Void
    private typealias RegisterNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias UnregisterNotifications = @convention(c) () -> Void

    private let getNowPlayingInfo: GetNowPlayingInfo?
    private let getIsPlaying: GetIsPlaying?
    private let getPID: GetPID?
    private let sendCommandFn: SendCommand?
    private let setElapsedFn: SetElapsed?
    private let registerFn: RegisterNotifications?
    private let unregisterFn: UnregisterNotifications?

    private init() {
        let library = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        )
        handle = library
        func sym<T>(_ name: String, as type: T.Type) -> T? {
            guard let library, let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        getNowPlayingInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfo.self)
        getIsPlaying = sym("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlaying.self)
        getPID = sym("MRMediaRemoteGetNowPlayingApplicationPID", as: GetPID.self)
        sendCommandFn = sym("MRMediaRemoteSendCommand", as: SendCommand.self)
        setElapsedFn = sym("MRMediaRemoteSetElapsedTime", as: SetElapsed.self)
        registerFn = sym("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterNotifications.self)
        unregisterFn = sym("MRMediaRemoteUnregisterForNowPlayingNotifications", as: UnregisterNotifications.self)
    }

    var isAvailable: Bool { handle != nil && getNowPlayingInfo != nil }

    /// Диагностика для спайка: какие символы разрешились.
    var diagnostics: String {
        let pairs: [(String, Bool)] = [
            ("dlopen", handle != nil),
            ("GetNowPlayingInfo", getNowPlayingInfo != nil),
            ("GetIsPlaying", getIsPlaying != nil),
            ("GetPID", getPID != nil),
            ("SendCommand", sendCommandFn != nil),
            ("SetElapsedTime", setElapsedFn != nil),
            ("RegisterForNotifications", registerFn != nil),
        ]
        return pairs.map { "\($0.0)=\($0.1 ? "ok" : "MISSING")" }.joined(separator: " ")
    }

    // MARK: - Чтение

    /// Собирает полный снимок: словарь трека, флаг воспроизведения и владельца.
    func fetchNowPlaying(completion: @escaping (NowPlaying?) -> Void) {
        guard let getNowPlayingInfo else {
            completion(nil)
            return
        }
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        var info: [String: Any] = [:]
        var playing = false
        var pid: Int32 = -1

        group.enter()
        getNowPlayingInfo(queue) { dictionary in
            info = dictionary
            group.leave()
        }

        if let getIsPlaying {
            group.enter()
            getIsPlaying(queue) { value in
                playing = value
                group.leave()
            }
        }

        if let getPID {
            group.enter()
            getPID(queue) { value in
                pid = value
                group.leave()
            }
        }

        // MediaRemote иногда не вызывает колбэк вовсе — например, когда
        // ни один плеер не зарегистрирован. Не подвешиваем вызывающую сторону.
        let timedOut = DispatchWorkItem { completion(nil) }
        queue.asyncAfter(deadline: .now() + 2, execute: timedOut)

        group.notify(queue: queue) {
            timedOut.cancel()
            guard !info.isEmpty else {
                completion(nil)
                return
            }
            completion(Self.makeNowPlaying(info: info, isPlaying: playing, pid: pid))
        }
    }

    private static func makeNowPlaying(info: [String: Any], isPlaying: Bool, pid: Int32) -> NowPlaying {
        func string(_ key: String) -> String? { info[key] as? String }
        func double(_ key: String) -> Double? { (info[key] as? NSNumber)?.doubleValue }

        var bundleIdentifier: String?
        if pid > 0 {
            bundleIdentifier = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        }

        let rate = double(Keys.playbackRate)
        return NowPlaying(
            title: string(Keys.title),
            artist: string(Keys.artist),
            album: string(Keys.album),
            bundleIdentifier: bundleIdentifier,
            trackID: (info[Keys.uniqueIdentifier] as? NSNumber)?.stringValue
                ?? info[Keys.uniqueIdentifier] as? String,
            // Флаг из MediaRemote иногда отстаёт, playbackRate точнее.
            isPlaying: rate.map { $0 > 0 } ?? isPlaying,
            duration: double(Keys.duration),
            elapsed: double(Keys.elapsedTime),
            playbackRate: rate,
            timestamp: info[Keys.timestamp] as? Date,
            artwork: info[Keys.artworkData] as? Data
        )
    }

    // MARK: - Управление

    func send(command: UInt32) -> Bool {
        guard let sendCommandFn else { return false }
        return sendCommandFn(command, nil)
    }

    func setElapsed(_ elapsed: Double) -> Bool {
        guard let setElapsedFn else { return false }
        setElapsedFn(elapsed)
        return true
    }

    // MARK: - Уведомления

    /// Подписывает процесс на распределённые уведомления MediaRemote.
    /// Без этого вызова система их не рассылает.
    func registerForNotifications() {
        registerFn?(DispatchQueue.main)
    }

    func unregisterFromNotifications() {
        unregisterFn?()
    }

    /// Имена уведомлений лежат в фреймворке как CFString. Читаем их через
    /// dlsym, а если символа нет — падаем на литерал: значение константы
    /// совпадает с её именем.
    func notificationName(_ symbol: String) -> Notification.Name {
        guard let handle, let pointer = dlsym(handle, symbol) else {
            return Notification.Name(symbol)
        }
        let value = pointer.assumingMemoryBound(to: CFString?.self).pointee
        guard let value else { return Notification.Name(symbol) }
        return Notification.Name(value as String)
    }

    enum Keys {
        static let title = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let duration = "kMRMediaRemoteNowPlayingInfoDuration"
        static let elapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        static let timestamp = "kMRMediaRemoteNowPlayingInfoTimestamp"
        static let artworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let uniqueIdentifier = "kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
    }

    enum Notifications {
        static let infoDidChange = "kMRMediaRemoteNowPlayingInfoDidChangeNotification"
        static let isPlayingDidChange = "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
    }
}
