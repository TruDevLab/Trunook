import Foundation

/// Срок хранения записей в заметках.
///
/// Час разговора — десятки мегабайт, и записи, которые никто не слушает,
/// копятся годами. Текст заметки остаётся всегда: уходит только звук.
enum AudioRetention {
    /// Выбор в настройках, в днях. Ноль — бессрочно.
    static let choices = [0, 60, 30, 14, 7, 1]

    static func title(days: Int) -> String {
        days == 0 ? t("Бессрочно") : tf("%d дн.", days)
    }

    /// Когда запись этой заметки уйдёт. `nil` — не уйдёт: срока нет,
    /// записи нет или её велено не удалять.
    ///
    /// От даты заметки, а не от последней правки: запись сделана тогда,
    /// и правка текста её не молодит.
    static func expiry(of note: Note, days: Int) -> Date? {
        guard days > 0, note.hasAudio, !note.keepAudio else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: note.createdAt)
    }

    static func expired(_ notes: [Note], days: Int, now: Date) -> [Note] {
        notes.filter { note in expiry(of: note, days: days).map { $0 <= now } ?? false }
    }
}
