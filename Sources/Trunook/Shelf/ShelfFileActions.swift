import AppKit
import TrunookXPC

/// Что полка делает с файлами, кроме того чтобы держать их: сжимает,
/// распаковывает и отправляет в Корзину.
///
/// Сжатие и распаковка — системным `ditto`, тем же, чем пользуется Finder:
/// он сохраняет расширенные атрибуты и ветви ресурсов, а архив открывается
/// двойным щелчком на любом Mac. Всё, кроме ZIP, распаковывает `tar` —
/// в macOS это libarchive, и gzip, bzip2 и xz он узнаёт сам.
///
/// Работа синхронная и может идти долго — звать не с главного потока.
/// Имена подбираются чистыми функциями: их проверяет тест.
enum ShelfFileActions {
    enum Failure: Error {
        case tool(String)
    }

    // MARK: - Чистые правила

    /// Расширения, которые полка распаковывает. Сравниваются хвостом имени:
    /// у `.tar.gz` расширение с точки зрения `URL` — одно `gz`.
    static let archiveSuffixes = [".zip", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tbz", ".tar.xz", ".txz"]

    static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return archiveSuffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    /// Держат одни архивы — раздел распаковывает. Хоть один не архив — сжимает
    /// всё вместе: распаковать «заодно» чужой документ нечем.
    static func unpacks(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy(isArchive)
    }

    /// Имя архива без хвоста: `отчёт.tar.gz` → `отчёт`.
    static func baseName(ofArchive url: URL) -> String {
        split(url.lastPathComponent).0
    }

    /// Как назвать архив: один файл — его именем, несколько — «Архив», как
    /// у Finder.
    static func archiveName(for urls: [URL]) -> String {
        if urls.count == 1, let only = urls.first {
            return only.lastPathComponent + ".zip"
        }
        return t("Архив") + ".zip"
    }

    /// Свободное имя в папке: `Архив.zip`, `Архив 2.zip`, `Архив 3.zip`.
    /// Чужой файл не перезаписывается никогда.
    static func freeURL(named name: String, in folder: URL, exists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path)
    }) -> URL {
        let first = folder.appendingPathComponent(name)
        guard exists(first) else { return first }
        let (stem, tail) = split(name)
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem) \(number)\(tail)")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// `Архив.zip` → (`Архив`, `.zip`); `отчёт.tar.gz` → (`отчёт`, `.tar.gz`);
    /// папка без точки — целиком в первой половине.
    static func split(_ name: String) -> (String, String) {
        let lower = name.lowercased()
        if let suffix = archiveSuffixes.filter({ lower.hasSuffix($0) && name.count > $0.count })
            .max(by: { $0.count < $1.count }) {
            return (String(name.dropLast(suffix.count)), String(name.suffix(suffix.count)))
        }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, name.count > ext.count + 1 else { return (name, "") }
        return (String(name.dropLast(ext.count + 1)), "." + ext)
    }

    // MARK: - Сжатие

    /// Сжимает файлы в ZIP рядом с первым из них. Возвращает архив.
    ///
    /// Несколько файлов сперва собираются в папку-сборку копиями — на APFS
    /// это клоны, ссылки на те же блоки, а не гигабайты заново, — и сжимается
    /// уже она: `ditto` берёт один источник, а файлы могли прийти из разных
    /// папок.
    static func archive(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw Failure.tool("нет файлов") }
        let folder = first.deletingLastPathComponent()
        let target = freeURL(named: archiveName(for: urls), in: folder)

        if urls.count == 1 {
            try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, target.path])
            return target
        }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for url in urls {
            let copy = freeURL(named: url.lastPathComponent, in: staging)
            try FileManager.default.copyItem(at: url, to: copy)
        }
        try run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, target.path])
        return target
    }

    // MARK: - Распаковка

    /// Распаковывает архив рядом с ним. Возвращает то, что получилось.
    ///
    /// Как у Finder: в архиве одна вещь — она и ложится рядом, несколько —
    /// в папку с именем архива. Распаковка идёт во временную папку в той же
    /// папке, а не в общую временную: перенос тогда — переименование,
    /// а не копирование гигабайтов между томами.
    static func unarchive(_ archive: URL) throws -> URL {
        let folder = archive.deletingLastPathComponent()
        let scratch = folder.appendingPathComponent(".trunook-unpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        if archive.lastPathComponent.lowercased().hasSuffix(".zip") {
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, scratch.path])
        } else {
            try run("/usr/bin/tar", ["-xf", archive.path, "-C", scratch.path])
        }

        // Служебная папка, которую кладут в ZIP архиваторы на Mac, — не содержимое.
        let items = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }

        if items.count == 1, let only = items.first {
            let target = freeURL(named: only.lastPathComponent, in: folder)
            try FileManager.default.moveItem(at: only, to: target)
            return target
        }
        let target = freeURL(named: baseName(ofArchive: archive), in: folder)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        for item in items {
            try FileManager.default.moveItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
        }
        return target
    }

    // MARK: - Корзина

    /// В Корзину, а не насовсем: вернуть оттуда можно из Finder.
    static func trash(_ urls: [URL], completion: @escaping (Int) -> Void) {
        NSWorkspace.shared.recycle(urls) { moved, error in
            if let error {
                DebugLog.write("полка: в Корзину не ушло — \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(moved.count) }
        }
    }

    // MARK: - Процесс

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Читать до ожидания: заполненная труба ошибок остановила бы процесс,
        // и ожидание не кончилось бы никогда.
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let tail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            DebugLog.write("полка: \((tool as NSString).lastPathComponent) вышел с \(process.terminationStatus) — \(tail)")
            throw Failure.tool(tail)
        }
    }
}
