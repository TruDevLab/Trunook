import CoreServices
import Foundation
import TrunookXPC

/// Слежение за папкой хранилища.
///
/// Первое в проекте: до сих пор приложению нечего было ждать от чужих папок.
/// Опрос по таймеру здесь не годится — правку в Obsidian человек делает
/// и тут же переключается на вырез, а ждать четверть часа, пока заметка
/// доедет, значит не иметь синхронизации вовсе.
///
/// Таймер сверки при этом остаётся: событий можно и не дождаться — папка
/// на сетевом диске, машина спала, поток сорвался. Слежение делает сверку
/// быстрой, а не единственной.
final class VaultWatcher {
    /// Папка изменилась. Зовётся на главном потоке, уже собранным пачками.
    var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.trunook.obsidian.watch")
    private var pending: DispatchWorkItem?

    /// Сколько ждать тишины, прежде чем сверяться.
    ///
    /// Одна правка в Obsidian — это не одно событие: редактор пишет файл,
    /// переписывает свой указатель, трогает служебные файлы. Сверка на каждое
    /// из них перечитывала бы хранилище по пять раз подряд.
    private static let quiet: TimeInterval = 1

    deinit { stop() }

    // MARK: - Пуск и остановка

    func start(url: URL) {
        stop()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            Self.callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.quiet,
            flags
        ) else {
            DebugLog.write("Obsidian: слежение за папкой не завелось")
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        DebugLog.write("Obsidian: слежу за \(url.path)")
    }

    func stop() {
        pending?.cancel()
        pending = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - События

    /// Обратный вызов приходит из C, и `self` в него передаётся указателем.
    /// Ссылка не удерживается: поток живёт ровно столько же, сколько объект,
    /// и `stop()` в `deinit` гасит его до того, как объект исчезнет.
    private static let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
    }

    private func schedule() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onChange?() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.quiet, execute: work)
        }
    }
}
