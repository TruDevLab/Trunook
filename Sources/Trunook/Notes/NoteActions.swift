import Foundation

/// Что можно сделать с одной заметкой — из списка, из открытой заметки
/// и с плитки главного экрана.
///
/// Одной структурой, а не замыканием на каждое действие: `NotchView`
/// и так принимает их больше тридцати, и каждое новое действие с заметкой
/// добавляло бы параметр в три вида сразу.
struct NoteActions {
    /// Открыть заметку: свою — на правку, заметку хранилища — в Obsidian.
    let open: (Note) -> Void
    let togglePin: (Note) -> Void
    /// Снять или поставить флаг «не удалять запись».
    let toggleKeepAudio: (Note) -> Void
    /// Удалить запись заметки. Текст остаётся.
    let deleteAudio: (Note) -> Void
    let play: (Note) -> Void
    let openInObsidian: (Note) -> Void
    /// Есть ли у заметки файл в хранилище Obsidian.
    let isInVault: (Note) -> Bool
}
