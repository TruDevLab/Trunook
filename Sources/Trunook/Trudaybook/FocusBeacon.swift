import TrunookXPC
import Combine
import Foundation

/// Сообщает соседним программам, что человек сосредоточен: пока идёт
/// рабочая фаза таймера, в `focus.json` лежит «фокус до такого-то времени».
/// Trudaybook на это время придерживает уведомления о письмах и присылает
/// одно общее, когда таймер кончится.
///
/// Срок в файле обязателен: упавший или закрытый Trunook не должен оставить
/// почту немой — фокус с прошедшим сроком читающий считает законченным.
final class FocusBeacon {
    private let timer: TimerService
    private let file: URL
    private var subscription: AnyCancellable?
    private var last: Data?

    init(timer: TimerService, file: URL? = nil) {
        self.timer = timer
        self.file = file ?? Self.defaultFile
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trunook/focus.json")
    }

    func start() {
        // `objectWillChange` приходит до правки: значения читаются на
        // следующем такте, когда они уже новые.
        subscription = timer.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.write() }
        }
        write()
    }

    /// Фокус ли сейчас и до какого времени. Отдельной чистой функцией —
    /// ради проверки без таймера и без диска.
    static func deadline(mode: TimerService.Mode, phase: TimerService.Phase, running: Bool,
                         remaining: TimeInterval, now: Date) -> Date? {
        guard mode == .timer, phase == .work, running, remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining)
    }

    private func write() {
        let until = Self.deadline(mode: timer.mode, phase: timer.phase, running: timer.isRunning,
                                  remaining: timer.remaining, now: Date())
        var json: [String: Any] = ["focus": until != nil]
        if let until { json["until"] = ISO8601DateFormatter().string(from: until) }
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
              data != last else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            last = data
        } catch {
            DebugLog.write("фокус: файл не записан — \(error.localizedDescription)")
        }
    }
}
