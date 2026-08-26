import AppKit
import CryptoKit
import Foundation

/// Одна запись истории буфера обмена.
struct ClipboardEntry: Identifiable, Equatable {
    enum Kind: String {
        case text
        case image
        case files

        var symbol: String {
            switch self {
            case .text: return "text.alignleft"
            case .image: return "photo"
            case .files: return "doc"
            }
        }
    }

    var id: Int64
    var kind: Kind
    /// Текст записи, имена файлов или подпись изображения. Хранится всегда:
    /// по нему запись показывается в списке и ищется.
    var text: String
    /// Содержимое для изображений. У текста и файлов пусто.
    var data: Data?
    /// Приложение, из которого скопировали.
    var source: String?
    var copiedAt: Date

    /// Однострочное представление: переносы в списке всё равно не видны,
    /// а из-за них строка выглядит обрезанной на полуслове.
    ///
    /// У файлов показываются только имена с расширением. Полный путь в узкой
    /// строке нечитаем — от него видно начало вроде «/Users/…», одинаковое
    /// у всех записей, а опознают файл как раз по имени. Сам путь при этом
    /// хранится целиком: без него файл потом не отдать обратно.
    var oneLine: String {
        guard kind != .files else {
            return fileNames.joined(separator: ", ")
        }
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Текст записи для заметки. `nil` — записывать нечего.
    ///
    /// Только у текстовых записей. Изображение в заметку не положить так,
    /// чтобы оно пережило выгрузку в Markdown, а список путей к файлам —
    /// не заметка: файлы откладывают на полку, она для этого и заведена.
    ///
    /// Текст берётся целиком, а не `oneLine`: та выжимка — для узкой строки
    /// списка, в ней склеены переносы и табуляции. В заметке абзацы нужны
    /// такими, какими их скопировали.
    var notesText: String? {
        guard kind == .text else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    var fileNames: [String] {
        fileURLs.map(\.lastPathComponent)
    }

    /// Файлы хранятся построчно — так их и разбираем обратно.
    var fileURLs: [URL] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var image: NSImage? {
        guard kind == .image, let data else { return nil }
        return NSImage(data: data)
    }

    /// Отпечаток содержимого — по нему ловятся повторы.
    ///
    /// Считается от содержимого, а не от текста подписи: два разных
    /// изображения с одинаковым размером дали бы одну подпись.
    var fingerprint: String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        if let data {
            hasher.update(data: data)
        } else {
            hasher.update(data: Data(text.utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Сколько времени назад скопировано — коротко, для правого края строки.
    func age(from now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(copiedAt))
        switch seconds {
        case ..<60: return t("только что")
        case ..<3600: return tf("%d мин", seconds / 60)
        case ..<86_400: return tf("%d ч", seconds / 3600)
        default: return tf("%d дн", seconds / 86_400)
        }
    }
}
