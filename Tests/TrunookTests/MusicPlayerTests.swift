import Foundation
import Testing
@testable import Trunook

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
