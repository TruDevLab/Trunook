import TrunookXPC
import AVFoundation
import AppKit
import Foundation

/// Запись разговора и всё, что происходит с ней дальше.
///
/// Один заход — четыре разные работы подряд: пишем звук, сводим дорожки,
/// расшифровываем, просим модель о пересказе. Держать их порознь не выйдет:
/// у них общее состояние, общий отказ на середине и одна плашка на всё
/// время. Отсюда и служба.
///
/// **Ничего не делает при выключенной настройке.** Ни отвода, ни доступа
/// к звуку системы, ни временных файлов — то же правило, что
/// у синхронизации с Obsidian.
final class RecorderService: ObservableObject {
    /// Чем занята запись прямо сейчас.
    ///
    /// Одним перечислением, а не набором признаков: состояния сменяют друг
    /// друга по очереди и никогда не совпадают, а два независимых признака
    /// рано или поздно разъезжаются.
    enum Phase: Equatable {
        case idle
        case recording
        /// Дорожки сводятся в один файл.
        case mixing
        case transcribing
        /// Модель придумывает название, пересказ и задачи.
        case thinking

        var isBusy: Bool { self != .idle }
        /// Идёт ли запись прямо сейчас — по этому признаку рисуется полоска.
        var isRecording: Bool { self == .recording }
    }

    @Published private(set) var phase: Phase = .idle
    /// Громкость микрофона, от нуля до единицы.
    @Published private(set) var level: Double = 0
    /// Когда началась запись. `nil` — не идёт.
    @Published private(set) var startedAt: Date?
    /// Сколько получилось у последней записи.
    ///
    /// Нужно после остановки: полоска в вырезе продолжает висеть, пока идут
    /// сведение и расшифровка, и показывает уже не растущее время, а длину
    /// готовой записи. Замершее число и объясняет, что запись кончилась,
    /// а работа — нет.
    @Published private(set) var lastDuration: TimeInterval = 0

    /// Заметка готова. Второе — предупреждение, если работа вышла неполной.
    ///
    /// Двумя значениями, а не двумя обработчиками: заметка **есть** в любом
    /// случае, и сообщать об отказе вместо неё было бы враньём. Первая версия
    /// молчала вовсе — запись без скачанного языка ложилась заметкой с одним
    /// аудиофайлом, и понять, почему нет текста, было неоткуда.
    var onNote: ((Note, String?) -> Void)?
    /// Что-то не вышло. Причина уже человеческая — её показывают плашкой.
    var onFailure: ((String) -> Void)?

    private let settings: Settings
    private let notes: NotesService
    private let obsidian: ObsidianService
    private let client: ModelClient

    private let microphone = MicrophoneCapture()
    /// Отвод звука системы. `Any`, потому что тип доступен только с macOS
    /// 14.2, а служба живёт и на более старых — там просто без него.
    private var tap: Any?
    private var tapFile: AVAudioFile?
    private var microphoneURL: URL?
    private var tapURL: URL?

    init(
        settings: Settings = .shared,
        notes: NotesService,
        obsidian: ObsidianService,
        client: ModelClient = ModelClient()
    ) {
        self.settings = settings
        self.notes = notes
        self.obsidian = obsidian
        self.client = client
    }

    // MARK: - Доступность

    /// Работает ли запись на этой системе вообще.
    ///
    /// Порог — macOS 26: расшифровка на устройстве появилась там. Запись без
    /// расшифровки завести можно, но она никому не нужна: смысл всей работы
    /// в тексте заметки, а не в файле, который потом некуда деть.
    static var isSupported: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    var isAvailable: Bool { Self.isSupported && settings.recordEnabled }

    /// Сколько уже пишем.
    ///
    /// По настенным часам, а не по кадрам: кадры знает только микрофон,
    /// а запись бывает и без него — с одним звуком системы.
    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    // MARK: - Пуск и остановка

    /// Аудиозаметка: только микрофон.
    func toggleNote() {
        toggle(withSystemAudio: false)
    }

    /// Запись встречи: микрофон и звук системы.
    func toggleMeeting() {
        toggle(withSystemAudio: true)
    }

    func toggle(withSystemAudio: Bool) {
        if phase.isRecording {
            stop()
        } else if phase == .idle {
            start(withSystemAudio: withSystemAudio)
        }
        // Занята сведением или расшифровкой — нажатие проходит молча:
        // прервать на середине значило бы выбросить уже записанное.
    }

    func start(withSystemAudio: Bool) {
        guard phase == .idle else { return }
        guard Self.isSupported else {
            onFailure?(t("Запись разговора требует macOS 26"))
            return
        }
        guard settings.recordEnabled else { return }

        // Микрофон спрашиваем до всего остального: без него запись встречи
        // выйдет односторонней, а аудиозаметка — пустой.
        VoiceAccess.requestMicrophone { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.onFailure?(t("Нужен доступ к микрофону"))
                return
            }
            self.begin(withSystemAudio: withSystemAudio)
        }
    }

    private func begin(withSystemAudio: Bool) {
        let stamp = String(UUID().uuidString.prefix(8))
        let folder = FileManager.default.temporaryDirectory
        let target = folder.appendingPathComponent("trunook-mic-\(stamp).caf")
        microphoneURL = microphone.start(to: target) ? target : nil

        microphone.onLevel = { [weak self] value in
            guard let self, self.phase.isRecording else { return }
            self.level = value
        }

        startedAt = Date()
        phase = .recording

        guard withSystemAudio, #available(macOS 14.2, *) else {
            announceStart()
            return
        }
        openTap(at: folder.appendingPathComponent("trunook-sys-\(stamp).caf"))
    }

    @available(macOS 14.2, *)
    private func openTap(at url: URL) {
        SystemAudioTap.open { [weak self] session in
            guard let self else {
                session?.close()
                return
            }
            guard let session, self.phase.isRecording else {
                session?.close()
                self.announceStart()
                return
            }
            do {
                tapFile = try AVAudioFile(forWriting: url, settings: session.pcmFormat.settings)
            } catch {
                DebugLog.write("запись: файл звука системы не открылся — \(error.localizedDescription)")
                session.close()
                self.announceStart()
                return
            }
            // Пишем прямо на потоке звуковой подсистемы, как и микрофон:
            // перекладывать буфер на свою очередь значило бы копировать его
            // целиком — он живёт только до конца обработчика.
            session.onBuffer = { [weak self] buffer in
                try? self?.tapFile?.write(from: buffer)
            }
            session.start { started in
                if started {
                    self.tap = session
                    self.tapURL = url
                } else {
                    session.close()
                    self.tapFile = nil
                }
                self.announceStart()
            }
        }
    }

    /// Не записалось ни то ни другое — сказать сразу, а не показывать час
    /// идущую полоску, за которой пустой файл.
    private func announceStart() {
        guard phase.isRecording else { return }
        guard !sources.isEmpty else {
            DebugLog.write("запись: не пошла ни одна дорожка")
            reset()
            onFailure?(t("Записывать нечем"))
            return
        }
        DebugLog.write("запись: пошла, дорожек \(sources.count)")
    }

    private var sources: [URL] {
        [microphoneURL, tapURL].compactMap { $0 }
    }

    func stop() {
        guard phase.isRecording else { return }

        microphone.stop()
        if #available(macOS 14.2, *), let session = tap as? SystemAudioTap {
            session.close()
        }
        tap = nil
        tapFile = nil
        level = 0

        let recorded = sources
        let started = startedAt ?? Date()
        lastDuration = elapsed
        startedAt = nil
        guard !recorded.isEmpty else {
            reset()
            return
        }

        phase = .mixing
        DebugLog.write("запись: остановлена, обрабатываю")
        Task { await process(sources: recorded, startedAt: started) }
    }

    private func reset() {
        phase = .idle
        startedAt = nil
        level = 0
        microphoneURL = nil
        tapURL = nil
    }

    // MARK: - Обработка

    @MainActor
    private func process(sources: [URL], startedAt: Date) async {
        defer { removeTemporary(sources) }

        let mixed = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-\(UUID().uuidString.prefix(8)).m4a")
        do {
            // Сведение читает и пишет файлы целиком — главному потоку там
            // делать нечего, час записи он сводил бы у всех на виду.
            try await Task.detached { try AudioMixdown.mix(sources, to: mixed) }.value
        } catch {
            DebugLog.write("запись: сведение не вышло — \(error.localizedDescription)")
            reset()
            onFailure?(t("Запись не сохранилась"))
            return
        }

        phase = .transcribing
        var transcript = ""
        var warning: String?
        if #available(macOS 26, *) {
            do {
                transcript = try await Transcriber.text(of: mixed, locale: settings.transcribeLocale)
            } catch Transcriber.Failure.assetMissing {
                DebugLog.write("запись: язык расшифровки не скачан")
                warning = t("Заметка готова, но язык расшифровки не скачан")
            } catch Transcriber.Failure.unsupportedLanguage {
                DebugLog.write("запись: язык расшифровке неизвестен")
                warning = t("Заметка готова: этот язык расшифровка не знает")
            } catch {
                DebugLog.write("запись: расшифровка не вышла — \(error)")
                warning = t("Заметка готова, но расшифровать не вышло")
            }
        }

        phase = .thinking
        // Кто говорил, решает число дорожек, а не то, какую кнопку нажали:
        // нажать можно «записать встречу», а звук собеседников не записаться.
        // Тогда в расшифровке всё равно один голос, и обещать модели разговор
        // значило бы просить её выдумать второго участника.
        let kind: TranscriptSummary.Kind = sources.count > 1 ? .conversation : .dictation
        let summary = await summarize(transcript, kind: kind)

        // Заметка собирается и без расшифровки, и без пересказа: запись
        // сделана, и потерять её из-за молчащей модели нельзя.
        let placed = place(mixed, title: summary?.title, at: startedAt)
        let note = notes.save(
            RecordingNote.text(summary: summary, transcript: transcript),
            origin: .recording,
            title: summary?.title,
            audio: placed ?? ""
        )

        reset()
        if let note {
            DebugLog.write("запись: заметка \(note.id) готова")
            onNote?(note, warning)
        } else {
            onFailure?(t("Запись не сохранилась"))
        }
    }

    private func removeTemporary(_ urls: [URL]) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Пересказ

    /// Пересказ и задачи от модели. `nil` — модель выключена или промолчала.
    private func summarize(
        _ transcript: String,
        kind: TranscriptSummary.Kind
    ) async -> RecordingSummary? {
        guard settings.ollamaEnabled else { return nil }
        let chunks = TranscriptSummary.chunks(of: transcript)
        guard !chunks.isEmpty else { return nil }

        var parts: [String] = []
        for chunk in chunks {
            if let answer = await ask(TranscriptSummary.prompt(for: chunk, kind: kind)) {
                parts.append(answer)
            }
        }
        guard let first = parts.first else { return nil }
        guard parts.count > 1 else { return TranscriptSummary.parse(first) }

        // Сведение пересказов: пять отдельных — это не пересказ встречи,
        // а пять обрывков с повторяющимися задачами. Не вышло — отдаём
        // первый кусок: он всё-таки лучше пустоты.
        guard let merged = await ask(TranscriptSummary.mergePrompt(for: parts, kind: kind)) else {
            return TranscriptSummary.parse(first)
        }
        return TranscriptSummary.parse(merged) ?? TranscriptSummary.parse(first)
    }

    private func ask(_ prompt: String) async -> String? {
        await withCheckedContinuation { continuation in
            client.generate(prompt: prompt) { result in
                switch result {
                case let .success(answer):
                    continuation.resume(returning: answer)
                case let .failure(error):
                    DebugLog.write("запись: модель не ответила — \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Куда лечь записи

    /// Подпапка для записей.
    ///
    /// Имя постоянное и непереводимое нарочно: сменив язык интерфейса,
    /// человек получил бы вторую папку, а старые записи остались бы
    /// в первой — и заметки указывали бы в пустоту.
    static let folderName = "Recordings"

    /// Самая свежая запись — для отладочной расшифровки.
    ///
    /// Ищет в обоих местах: в хранилище и в папке приложения. Куда легла
    /// запись, зависит от того, была ли включена синхронизация в тот момент,
    /// а не от того, включена ли она сейчас.
    func newestRecording() -> URL? {
        var folders: [URL] = [
            NotesStore.defaultURL
                .deletingLastPathComponent()
                .appendingPathComponent(Self.folderName, isDirectory: true),
        ]
        if let vault = obsidian.vault, vault.isReachable {
            folders.insert(vault.ownFolder.appendingPathComponent(Self.folderName), at: 0)
        }

        let files = folders.flatMap { folder in
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
        }
        return files
            .filter { $0.pathExtension.lowercased() == "m4a" }
            .max { left, right in
                let a = (try? left.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let b = (try? right.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return a < b
            }
    }

    /// Куда легла запись. Возвращает путь, который ляжет в поле заметки:
    /// относительный внутри хранилища, полный вне его.
    private func place(_ temporary: URL, title: String?, at date: Date) -> String? {
        let name = fileName(title: title, at: date)

        // В хранилище — если синхронизация включена и папка на месте.
        // Проверка боем, как везде в работе с хранилищем: отключённый диск
        // отвечает тем же отказом, что и запрет.
        if settings.obsidianEnabled, let vault = obsidian.vault, vault.isReachable {
            let path = vault.folder + "/" + Self.folderName + "/" + name
            let free = freePath(path) { vault.fileURL(for: $0).path }
            if move(temporary, to: vault.fileURL(for: free)) { return free }
        }

        let folder = NotesStore.defaultURL
            .deletingLastPathComponent()
            .appendingPathComponent(Self.folderName, isDirectory: true)
        let free = freePath(folder.appendingPathComponent(name).path) { $0 }
        let url = URL(fileURLWithPath: free)
        guard move(temporary, to: url) else { return nil }
        return free
    }

    /// Имя файла: время впереди, чтобы папка сортировалась по нему,
    /// а не по первой букве названия. Тот же приём, что
    /// в `NoteMarkdown.fileName`.
    private func fileName(title: String?, at date: Date) -> String {
        let formatter = DateFormatter()
        // Локаль постоянная: имя файла — ключ сортировки, а не текст
        // для чтения, и месяц словом сортировался бы по букве.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let stamp = formatter.string(from: date)
        let name = NoteMarkdown.safe(title ?? "")
        return name.isEmpty ? "\(stamp).m4a" : "\(stamp) \(name).m4a"
    }

    /// Разводит совпадающие имена суффиксом.
    ///
    /// Две записи одной минуты дают одно имя. `VaultScanner.freePath` сюда
    /// не годится: он приписывает `.md` — он про заметки.
    private func freePath(_ path: String, resolve: (String) -> String) -> String {
        guard FileManager.default.fileExists(atPath: resolve(path)) else { return path }
        let base = (path as NSString).deletingPathExtension
        for index in 2..<1000 {
            let next = "\(base)-\(index).m4a"
            if !FileManager.default.fileExists(atPath: resolve(next)) { return next }
        }
        return path
    }

    private func move(_ from: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: from, to: destination)
            return true
        } catch {
            DebugLog.write("запись: файл не лёг на место — \(error.localizedDescription)")
            return false
        }
    }
}
