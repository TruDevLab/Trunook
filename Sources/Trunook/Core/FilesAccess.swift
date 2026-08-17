import AppKit

/// Доступ к файлам в защищённых папках: рабочий стол, документы, загрузки.
///
/// Нужен полке. Ссылку на файл перетаскивание отдаёт всегда, но всё, что
/// с этим файлом делают дальше — читают размер, просят у QuickLook миниатюру,
/// проверяют, на месте ли он ещё, — упирается в TCC, если файл лежит
/// в защищённой папке. Без доступа полка покажет запись с общим значком
/// и без размера.
///
/// Состояние опросом не отдаётся: у TCC нет запроса «выдан ли доступ».
/// Остаётся проверка боем — попытка прочитать папку. Она же и вызывает
/// системный диалог, если решения ещё не было, поэтому отдельного
/// «запросить» здесь нет: первая же проверка и есть запрос.
enum FilesAccess {
    /// Рабочий стол: оттуда файлы кладут на полку чаще всего.
    private static var probeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static var isGranted: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: probeDirectory.path)) != nil
    }

    static func openSettings() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
