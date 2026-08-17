import Foundation

/// Имя XPC-сервиса. Должно совпадать с CFBundleIdentifier хелпера.
public let trunookHelperServiceName = "com.apple.controlcenter.TrunookHelper"

/// Снимок текущего трека. Гоняем между процессами как JSON, а не как
/// NSSecureCoding-объект — так не нужно белым списком перечислять классы.
public struct NowPlaying: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var bundleIdentifier: String?
    /// Идентификатор трека от самого плеера, если он его сообщает.
    public var trackID: String?
    public var isPlaying: Bool
    public var duration: Double?
    /// Позиция на момент `timestamp`. Текущую считаем сами с учётом playbackRate.
    public var elapsed: Double?
    public var playbackRate: Double?
    public var timestamp: Date?
    public var artwork: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        bundleIdentifier: String? = nil,
        trackID: String? = nil,
        isPlaying: Bool = false,
        duration: Double? = nil,
        elapsed: Double? = nil,
        playbackRate: Double? = nil,
        timestamp: Date? = nil,
        artwork: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.bundleIdentifier = bundleIdentifier
        self.trackID = trackID
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsed = elapsed
        self.playbackRate = playbackRate
        self.timestamp = timestamp
        self.artwork = artwork
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil
    }

    /// Позиция воспроизведения на указанный момент.
    public func position(at date: Date = Date()) -> Double? {
        guard let elapsed else { return nil }
        guard let timestamp, isPlaying else { return elapsed }
        let rate = playbackRate ?? 1
        let projected = elapsed + date.timeIntervalSince(timestamp) * rate
        guard let duration else { return max(0, projected) }
        return min(max(0, projected), duration)
    }
}

/// Команды транспорта. Значения — сырые коды MediaRemote.
public enum MediaCommand: UInt32, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

/// Интерфейс хелпера со стороны приложения.
@objc public protocol TrunookHelperProtocol {
    /// Возвращает JSON-кодированный `NowPlaying` либо nil, если ничего не играет.
    func fetchNowPlaying(withReply reply: @escaping (Data?) -> Void)
    func send(command: UInt32, withReply reply: @escaping (Bool) -> Void)
    func setElapsed(_ elapsed: Double, withReply reply: @escaping (Bool) -> Void)
    /// Включает push-уведомления об изменении трека в сторону приложения.
    func startObserving()
    func stopObserving()
}

/// Интерфейс приложения со стороны хелпера — обратный канал.
@objc public protocol TrunookHelperClientProtocol {
    func nowPlayingDidChange(_ payload: Data?)
}
