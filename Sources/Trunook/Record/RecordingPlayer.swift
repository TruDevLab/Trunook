import TrunookXPC
import AVFoundation
import Foundation

/// Проигрывает записи прямо в вырезе.
///
/// Один проигрыватель на всё приложение: две записи разом никто не слушает,
/// а нажатие по второй строке само останавливает первую — иначе они пошли бы
/// внахлёст, и остановить первую было бы нечем.
///
/// Отдельно от `RecorderService`: тот пишет и занят своим состоянием на всё
/// время обработки, а слушают записи потом и независимо от того, идёт ли
/// новая запись.
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// Какая заметка звучит прямо сейчас. `nil` — тишина.
    @Published private(set) var playing: Int64?

    private var player: AVAudioPlayer?

    /// Играет ли запись этой заметки.
    func isPlaying(_ id: Int64) -> Bool { playing == id }

    /// Пускает или останавливает запись заметки.
    ///
    /// Одной кнопкой на оба действия: пока запись играет, единственное, чего
    /// от неё хотят, — это её выключить.
    func toggle(note: Note, url: URL) {
        if playing == note.id {
            stop()
            return
        }
        stop()

        // Файл хранилища живёт в iCloud, и облако выгружает то, чем давно
        // не пользовались, оставляя на диске заглушку. Просим вернуть его
        // до открытия: иначе `play()` отвечает отказом без всякой причины —
        // так и выглядели три «не пустился» в журнале.
        download(url)

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            // Подготовка отдельно от пуска: она выделяет буферы и открывает
            // устройство вывода заранее, и её отказ говорит о причине больше,
            // чем молчаливое `false` у `play()`.
            guard player.prepareToPlay() else {
                DebugLog.write("запись: не готовится — \(describe(url))")
                return
            }
            guard player.play() else {
                DebugLog.write("запись: не пустился — \(describe(url))")
                return
            }
            self.player = player
            playing = note.id
            DebugLog.write("запись: играю \(url.lastPathComponent)")
        } catch {
            DebugLog.write("запись: файл не открылся — \(error.localizedDescription), "
                + describe(url))
        }
    }

    /// Просит облако вернуть выгруженный файл.
    ///
    /// Без ожидания: заглушка возвращается не мгновенно, а держать вырез
    /// в это время нельзя. Не вышло сейчас — выйдет со второго нажатия,
    /// и это честнее, чем замереть на неизвестное время.
    private func download(_ url: URL) {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values?.ubiquitousItemDownloadingStatus, status != .current else {
            return
        }
        DebugLog.write("запись: файл выгружен в облако, прошу вернуть")
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Что известно о файле — для журнала. Размер отвечает на главный
    /// вопрос: файл на месте целиком или от него осталась заглушка.
    private func describe(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "\(url.lastPathComponent), \(size) б"
    }

    func stop() {
        player?.stop()
        player = nil
        playing = nil
    }

    /// Запись доиграла сама. Приходит на главном потоке — так обещает
    /// `AVAudioPlayer`, и вёрстку отсюда трогать можно.
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}
