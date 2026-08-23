import Foundation
import Combine
import SwiftUI
import TrunookXPC

/// Клиент XPC-хелпера. Вся работа с приватным MediaRemote вынесена в отдельный
/// процесс, поэтому если Apple закроет обход — падать будет только он.
final class MusicClient: NSObject, ObservableObject, TrunookHelperClientProtocol {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var status: String = "не подключён"

    /// Преобладающий цвет обложки — им красится полоса воспроизведения.
    /// `nil` — обложки нет или она серая.
    ///
    /// Считается здесь, а не в теле полосы, и причина не в скорости самой
    /// по себе. Полоса перерисовывается тридцать раз в секунду, потому что
    /// движется; обложка за это время не меняется ни разу. Разбор картинки
    /// в теле вида означал бы двести пятьдесят шесть пикселей на каждый кадр
    /// ради ответа, известного с начала трека.
    @Published private(set) var artworkTint: Color?

    /// Обложка, по которой посчитан `artworkTint`. Хранится, чтобы не разбирать
    /// одну и ту же картинку дважды.
    private var tintSource: Data?

    /// Срабатывает при смене трека, но не при первом чтении: показывать
    /// плашку о «новом» треке сразу после запуска приложения незачем.
    var onTrackChanged: ((NowPlaying) -> Void)?
    private var hasLoadedOnce = false
    /// Когда последний раз приходили непустые сведения.
    private var lastNonEmptyAt = Date.distantPast
    /// Номер запроса. Ответы XPC приходят не по порядку, и без нумерации
    /// поздний ответ на ранний запрос затирает более свежие сведения.
    private var issuedRequests: UInt64 = 0
    private var appliedRequest: UInt64 = 0

    private var connection: NSXPCConnection?
    private var pollTimer: Timer?
    private var burstTimers: [Timer] = []

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func start() {
        connect()
        refresh()
        // Уведомления MediaRemote приходят не про всё — например, движение
        // ползунка внутри трека молчит. Подстраховываемся редким опросом.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        burstTimers.forEach { $0.invalidate() }
        burstTimers.removeAll()
        proxy()?.stopObserving()
        connection?.invalidate()
        connection = nil
    }

    private func connect() {
        let connection = NSXPCConnection(serviceName: trunookHelperServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: TrunookHelperProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: TrunookHelperClientProtocol.self)
        connection.exportedObject = self
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.status = "хелпер недоступен" }
        }
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.status = "хелпер перезапускается" }
        }
        connection.resume()
        self.connection = connection
        proxy()?.startObserving()
    }

    private func proxy() -> TrunookHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                self?.status = "ошибка XPC: \(error.localizedDescription)"
            }
        } as? TrunookHelperProtocol
    }

    func refresh() {
        guard let proxy = proxy() else {
            status = "хелпер не отвечает"
            return
        }
        issuedRequests += 1
        let sequence = issuedRequests
        proxy.fetchNowPlaying { [weak self] data in
            self?.apply(data, sequence: sequence)
        }
    }

    func send(_ command: MediaCommand) {
        proxy()?.send(command: command.rawValue) { [weak self] ok in
            guard ok else { return }
            DispatchQueue.main.async { self?.refreshBurst() }
        }
    }

    func seek(to seconds: Double) {
        proxy()?.setElapsed(seconds) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshBurst() }
        }
    }

    /// Серия чтений после команды вместо одного через фиксированную паузу.
    ///
    /// MediaRemote обновляет сведения не мгновенно и не за один шаг: сперва
    /// меняются название и исполнитель, обложка приезжает отдельно и позже.
    /// Единственное чтение через 0.3 с успевало застать промежуточное
    /// состояние — старую обложку рядом с новым названием — и держало его
    /// до следующего планового опроса через пять секунд.
    private func refreshBurst() {
        burstTimers.forEach { $0.invalidate() }
        burstTimers.removeAll()

        // Короткая серия: основной канал — уведомления от системы, это лишь
        // подстраховка на случай, если конкретный плеер их не рассылает.
        for delay in [0.3, 1.0, 2.0] {
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            burstTimers.append(timer)
        }
    }

    // MARK: - Обратный канал от хелпера

    /// Пересчитать цвет обложки.
    ///
    /// Только когда обложка действительно другая. Сравнение по самим байтам,
    /// а не по признаку «сменился трек»: у альбома обложка одна на все треки,
    /// и разбирать её заново на каждой песне незачем. Обратный случай тоже
    /// бывает — плеер присылает обложку не сразу, а через секунду после
    /// названия, и тогда трек тот же, а картинка новая.
    private func updateTint(for track: NowPlaying?, isNewTrack: Bool) {
        let artwork = track?.artwork
        guard artwork != tintSource || (isNewTrack && artwork == nil) else { return }
        tintSource = artwork
        artworkTint = ArtworkTint.color(from: artwork)
    }

    func nowPlayingDidChange(_ payload: Data?) {
        // Хелпер прислал свежие сведения по собственному почину — считаем их
        // новее всех запросов, отправленных до этого момента.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.issuedRequests += 1
            self.apply(payload, sequence: self.issuedRequests)
        }
    }

    private func apply(_ data: Data?, sequence: UInt64) {
        let snapshot = data.flatMap { try? decoder.decode(NowPlaying.self, from: $0) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard sequence >= self.appliedRequest else { return }
            self.appliedRequest = sequence
            guard self.isFresh(snapshot) else { return }
            guard self.accept(snapshot) else { return }

            let previous = self.nowPlaying
            let isNewTrack = !Self.isSameTrack(snapshot, previous)

            var merged = snapshot
            if !isNewTrack, let previous {
                Self.carryOver(from: previous, into: &merged)
            }

            self.nowPlaying = merged
            self.status = merged == nil ? "ничего не играет" : "подключён"
            self.updateTint(for: merged, isNewTrack: isNewTrack)

            if let merged, isNewTrack, self.hasLoadedOnce, !merged.isEmpty {
                DebugLog.write(
                    "музыка: «\(previous?.title ?? "—")» / \(previous?.artist ?? "—")"
                    + " → «\(merged.title ?? "?")» / \(merged.artist ?? "—")"
                )
                self.onTrackChanged?(merged)
            } else if !isNewTrack, previous?.artist != merged?.artist {
                DebugLog.write("музыка: исполнитель уточнён "
                               + "\(previous?.artist ?? "—") → \(merged?.artist ?? "—")")
            }
            self.hasLoadedOnce = true
        }
    }

    /// Отсеивает пустые ответы, приходящие в момент смены трека.
    ///
    /// MediaRemote отдаёт пустоту между старыми и новыми сведениями. Принимая
    /// её как есть, трек на мгновение «пропадает», а вернувшись, считается
    /// новым — и плашка о смене выскакивает дважды подряд.
    ///
    /// Считать пустые ответы подряд не годится: в момент переключения их
    /// прилетает сразу несколько, потому что в полёте одновременно несколько
    /// запросов. Поэтому решает не счётчик, а время: пустота признаётся
    /// настоящей, только если длится дольше окна переключения.
    private func accept(_ snapshot: NowPlaying?) -> Bool {
        let isEmpty = snapshot == nil || snapshot?.isEmpty == true
        guard isEmpty else {
            lastNonEmptyAt = Date()
            return true
        }
        guard nowPlaying != nil else { return true }

        guard Date().timeIntervalSince(lastNonEmptyAt) >= Self.emptyGracePeriod else {
            return false
        }
        DebugLog.write("музыка: воспроизведение остановлено")
        return true
    }

    /// Сколько терпим пустоту, прежде чем признать её остановкой.
    private static let emptyGracePeriod: TimeInterval = 2

    /// Тот же самый трек или уже другой.
    ///
    /// Исполнителя в сравнении нет намеренно. MediaRemote отдаёт сведения
    /// порциями и в момент переключения успевает сообщить новое название
    /// со старым исполнителем — проверено в журнале: «мы с тобой как будто»
    /// приезжало с исполнителем предыдущего трека и лишь через полсекунды
    /// исправлялось. Сравнение по исполнителю считало бы это второй сменой
    /// трека, и плашка выскакивала бы дважды.
    ///
    /// Когда плеер сообщает собственный идентификатор, полагаемся на него:
    /// он единственный различает одноимённые треки подряд.
    private static func isSameTrack(_ lhs: NowPlaying?, _ rhs: NowPlaying?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        if let left = lhs.trackID, let right = rhs.trackID {
            return left == right
        }
        return lhs.title == rhs.title
    }

    /// Переносит поля, которых в новом ответе ещё нет.
    ///
    /// Часть ответов по тому же треку возвращается без обложки, исполнителя
    /// или длительности. Принимая их как есть, мы бы гасили уже показанное.
    private static func carryOver(from previous: NowPlaying, into snapshot: inout NowPlaying?) {
        guard snapshot != nil else { return }
        if snapshot?.artwork == nil { snapshot?.artwork = previous.artwork }
        if snapshot?.artist?.isEmpty ?? true { snapshot?.artist = previous.artist }
        if snapshot?.album?.isEmpty ?? true { snapshot?.album = previous.album }
        if snapshot?.duration == nil { snapshot?.duration = previous.duration }
    }

    /// Отбрасывает устаревшие сведения по отметке времени самого MediaRemote.
    ///
    /// Порядок отправки запросов — лишь косвенный признак свежести: ответ
    /// может прийти позже, но содержать более раннее состояние. У сведений
    /// есть собственная отметка, и она надёжнее любых наших догадок.
    private func isFresh(_ snapshot: NowPlaying?) -> Bool {
        guard let incoming = snapshot?.timestamp,
              let current = nowPlaying?.timestamp
        else { return true }

        guard incoming >= current else {
            DebugLog.write("музыка: устаревший ответ отброшен")
            return false
        }
        return true
    }
}
