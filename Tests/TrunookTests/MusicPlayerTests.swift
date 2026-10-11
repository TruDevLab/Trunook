import Foundation
import Testing
@testable import Trunook
import TrunookXPC

@Suite("Плеер для плитки «Музыка»")
struct MusicPlayerTests {
    @Test("В выборе только установленные известные, по порядку списка")
    func толькоУстановленные() {
        let installed: Set = ["ru.yandex.desktop.music", MusicPlayer.fallback]
        let choices = MusicPlayer.choices(selected: MusicPlayer.fallback) { installed.contains($0) }
        #expect(choices == [MusicPlayer.fallback, "ru.yandex.desktop.music"])
    }

    @Test("Выбранный через «Другое…» остаётся в списке, даже если его нет среди известных")
    func своёПриложение() {
        let choices = MusicPlayer.choices(selected: "com.example.player") { $0 == MusicPlayer.fallback }
        #expect(choices == [MusicPlayer.fallback, "com.example.player"])
    }

    @Test("«Играть» — кнопка следом за «назад», а не на обложке ленты")
    func кнопкаИграть() {
        // Ряд кнопок окна Яндекс Музыки, снятый событием `musicDump`.
        let window = [["Свернуть сайдбар"], ["Воспроизведение"], ["Воспроизведение"],
                      ["Встряхнуть Мою волну"], ["Выключить звук"], ["Не нравится"], ["Нравится"],
                      ["Предыдущая песня"], ["Воспроизведение"], ["Следующая песня"]]
        #expect(MusicPlayer.playButton(in: window) == 8)
        // Без панели управления (страница ещё грузится) — ничего не жмём.
        #expect(MusicPlayer.playButton(in: [["Воспроизведение"], ["Воспроизведение"]]) == nil)
        // Уже играет: рядом с «назад» стоит «Пауза» — не трогаем.
        #expect(MusicPlayer.playButton(in: [["Предыдущая песня"], ["Пауза"], ["Следующая песня"]]) == nil)
    }

    @Test("Лайк: флажок «Нравится» панели управления, способ — по плееру")
    func лайк() {
        // Ряд кнопок окна Яндекс Музыки, снятый событием `musicDump`.
        let window = [["Воспроизведение"], ["Выключить звук"], ["Не нравится"], ["Нравится"],
                      ["Предыдущая песня"], ["Воспроизведение"], ["Следующая песня"]]
        #expect(TrackLike.likeButton(in: window) == 3)
        // Без панели управления — ничего.
        #expect(TrackLike.likeButton(in: [["Нравится"], ["Воспроизведение"]]) == nil)
        #expect(TrackLike.way(for: "com.apple.Music") == .appleScript)
        #expect(TrackLike.way(for: "ru.yandex.desktop.music") == .button)
        // Системная команда «Нравится» будит «Музыку» Apple — у прочих
        // плееров сердечка нет вовсе.
        #expect(TrackLike.way(for: "com.spotify.client") == .unsupported)
        #expect(TrackLike.way(for: nil) == .unsupported)
        #expect(!TrackLike.supports(NowPlaying(title: "Песня", artist: "Группа", isPlaying: true)))
    }

    @Test("По умолчанию — «Музыка» Apple, пустое значение тоже к ней")
    func поУмолчанию() {
        let suite = "trunook-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        #expect(settings.musicPlayer == MusicPlayer.fallback)
        settings.musicPlayer = ""
        #expect(settings.musicPlayer == MusicPlayer.fallback)
        settings.musicPlayer = "ru.yandex.desktop.music"
        #expect(settings.musicPlayer == "ru.yandex.desktop.music")
    }
}
