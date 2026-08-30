import TrunookXPC
import Foundation

/// Смонтированный образ: где он лежит и каким устройством отдан.
struct MountedImage: Equatable {
    let mountPoint: URL
    /// `/dev/disk4s1` — нужен, чтобы отмонтировать, когда по точке не вышло.
    let device: String
}

/// Монтирование образа с обновлением.
///
/// Разбор ответа `hdiutil` отделён от запуска процесса: только так его
/// проверяет тест — на записанном выводе, а не на живом образе.
enum DiskImage {
    /// Монтирует образ только на чтение, не показывая том в Finder.
    ///
    /// `-mountrandom /private/tmp` вместо `/Volumes/Trunook 0.12.0`: имя тома
    /// предсказуемо, и занять его заранее может кто угодно. Заодно не столкнёмся
    /// с томом, который на время сборки оставляет `make dmg`, — имя у него ровно
    /// такое же.
    static func attach(_ image: URL) -> MountedImage? {
        guard let output = run(["attach", "-nobrowse", "-readonly", "-noverify",
                                "-noautoopen", "-mountrandom", "/private/tmp",
                                "-plist", image.path])
        else { return nil }
        return mounted(fromPlist: output)
    }

    /// Отмонтирует. Оставленный том — это не просто мусор: следующая попытка
    /// обновиться налетит на него.
    static func detach(_ image: MountedImage) {
        if run(["detach", "-quiet", image.mountPoint.path]) != nil { return }
        guard !image.device.isEmpty else { return }
        DebugLog.write("обновление: том не отмонтировался по точке, пробуем силой")
        _ = run(["detach", "-force", "-quiet", image.device])
    }

    /// Где на образе лежит приложение.
    ///
    /// Ровно одно, а не первое попавшееся: рядом лежат симлинк `Applications`
    /// и текстовая инструкция, а однажды ляжет что-то ещё. Двух приложений
    /// в корне быть не должно, и гадать между ними нельзя.
    static func application(in mountPoint: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        let applications = contents.filter { $0.pathExtension == "app" }
        guard applications.count == 1 else {
            DebugLog.write("обновление: на образе приложений — \(applications.count), ждали одно")
            return nil
        }
        return applications[0]
    }

    /// Достаёт точку монтирования из ответа `hdiutil attach -plist`.
    ///
    /// Берётся первая запись, у которой она есть: в списке лежит ещё и схема
    /// разделов, у неё точки нет вовсе, а порядок записей не обещан.
    static func mounted(fromPlist data: Data) -> MountedImage? {
        guard let root = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]]
        else { return nil }

        for entity in entities {
            guard let point = entity["mount-point"] as? String, !point.isEmpty else { continue }
            return MountedImage(
                mountPoint: URL(fileURLWithPath: point),
                device: entity["dev-entry"] as? String ?? ""
            )
        }
        return nil
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        // На macOS 27 `hdiutil attach` пишет в поток ошибок, что команда
        // устарела. Это не ошибка, и в разбор оно попадать не должно.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            DebugLog.write("обновление: hdiutil не запустился — \(error.localizedDescription)")
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            DebugLog.write("обновление: hdiutil \(arguments.first ?? "") ответил \(process.terminationStatus)")
            return nil
        }
        return data
    }
}
