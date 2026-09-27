import TrunookXPC
import Foundation

/// Отвечает Trudaybook моделью: пересказ письма, метки для разбора,
/// повестка дня и итоги недели или месяца по заметкам.
///
/// Просьба — файл в `~/Library/Application Support/Trunook/mail-requests`,
/// ответ — в `…/Trudaybook/trunook-answers/<номер>.json`. Путь ответа
/// из просьбы не берём: пишем только в эту папку, под номером-UUID.
///
/// Только местная модель (`MailModelProtocol.choose`): письма — не то,
/// что уходит в облако без спроса, и Trudaybook обещает это своим людям.
/// Облачной основной модели отвечаем отказом `cloud`.
///
/// Просьбы — по одной: модель на машине одна, и две сразу только
/// замедлили бы обе.
final class MailModelService {
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trunook/mail-requests", isDirectory: true)
    }

    static var answers: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trudaybook/trunook-answers", isDirectory: true)
    }

    /// Очередь не длиннее: застрявший Trudaybook не должен занять модель
    /// на час вперёд.
    static let maxQueue = 12

    private let settings: Settings
    private let client: ModelClient
    private var source: DispatchSourceFileSystemObject?
    private var queue: [MailModelProtocol.Request] = []
    private var busy = false

    init(settings: Settings = .shared, client: ModelClient = ModelClient()) {
        self.settings = settings
        self.client = client
    }

    func start() {
        guard source == nil else { return }
        let folder = Self.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            DebugLog.write("почта для модели: папка не создана — \(error.localizedDescription)")
            return
        }
        writeKinds()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        drain()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// Что мы умеем — скрытым файлом в папке просьб: Trudaybook не шлёт
    /// просьбу, на которую мы не ответим. Скрытые файлы `drain` не читает.
    private func writeKinds() {
        let file = Self.folder.appendingPathComponent(".kinds.json")
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["version": MailModelProtocol.version, "kinds": MailModelProtocol.kinds], options: [.sortedKeys])
        else { return }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// Забрать всё, что лежит. Скрытые — недописанные, их не трогаем.
    private func drain() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            let data = try? Data(contentsOf: file)
            try? FileManager.default.removeItem(at: file)
            guard let data, let request = MailModelProtocol.parse(data) else {
                if let data, let id = MailModelProtocol.unsupportedID(data) {
                    DebugLog.write("почта для модели: вид просьбы незнаком — отказ")
                    answer(id, ["ok": false, "code": "unsupported", "error": t("Этот Trunook не умеет такую просьбу — обновите Trunook.")])
                } else {
                    DebugLog.write("почта для модели: просьба не разобрана — пропущена")
                }
                continue
            }
            guard queue.count < Self.maxQueue else {
                answer(request.id, ["ok": false, "code": "busy", "error": t("Trunook занят другими письмами — попробуйте позже.")])
                continue
            }
            queue.append(request)
        }
        next()
    }

    private func next() {
        guard !busy, !queue.isEmpty else { return }
        let request = queue.removeFirst()

        let choice = MailModelProtocol.choose(
            primary: settings.defaultModel,
            enabled: settings.enabledProviders,
            address: { self.settings.apiURL(for: $0) },
            model: { self.settings.apiModel(for: $0) })
        let model: ModelRef
        switch choice {
        case .local(let ref):
            model = ref
        case .cloudOnly:
            DebugLog.write("почта для модели: модель облачная — отказ")
            answer(request.id, ["ok": false, "code": "cloud",
                                "error": t("Модель Trunook работает в облаке — письма туда не отправляются.")])
            return next()
        case .none:
            answer(request.id, ["ok": false, "code": "noModel", "error": t("В Trunook не выбрана модель.")])
            return next()
        }

        let prompt: String
        var keys: Set<String> = []
        var names: [String: String] = [:]
        let what: String
        switch request.kind {
        case let .summary(subject, from, _, text):
            prompt = MailModelProtocol.summaryPrompt(subject: subject, from: from, text: text, language: request.language)
            what = "пересказ"
        case .labels(let letters):
            prompt = MailModelProtocol.labelsPrompt(letters, language: request.language)
            keys = Set(letters.map(\.key))
            what = "метки \(keys.count)"
        case .agenda(let agenda):
            prompt = MailModelProtocol.agendaPrompt(agenda, language: request.language)
            keys = Set(agenda.meetings.map(\.key))
            for meeting in agenda.meetings { names[meeting.key] = meeting.title }
            for letter in agenda.letters { names[letter.key] = letter.subject }
            what = "повестка, встреч \(agenda.meetings.count)"
        case let .digest(period, title, notes):
            prompt = MailModelProtocol.digestPrompt(period: period, title: title, notes: notes, language: request.language)
            what = "итоги \(period == "month" ? "месяца" : "недели"), заметок \(notes.count)"
        }

        busy = true
        let started = Date()
        // Текст писем и заметок в журнал не пишется — только вид просьбы и время.
        DebugLog.write("почта для модели: \(what) — \(model.name)")
        client.stream(
            messages: [.user(prompt)],
            contextWindow: ModelClient.contextWindow(forCharacters: prompt.count),
            model: model.stored,
            onToken: { _ in },
            onFinish: { [weak self] result in
                guard let self else { return }
                self.busy = false
                let seconds = Int(Date().timeIntervalSince(started))
                switch result {
                case .success(let text):
                    switch request.kind {
                    case .summary:
                        let summary = MailModelProtocol.withoutThinking(text)
                        DebugLog.write("почта для модели: пересказ готов за \(seconds) с")
                        self.answer(request.id, summary.isEmpty
                            ? ["ok": false, "code": "empty", "error": t("Модель вернула пустой ответ.")]
                            : ["ok": true, "summary": summary, "model": model.name])
                    case .labels:
                        let labels = MailModelProtocol.labels(in: text, keys: keys)
                        DebugLog.write("почта для модели: меток \(labels.count) из \(keys.count) за \(seconds) с")
                        self.answer(request.id, ["ok": true, "labels": labels, "model": model.name])
                    case .agenda:
                        let agenda = MailModelProtocol.agenda(in: text, keys: keys, names: names)
                        DebugLog.write("почта для модели: повестка — главного \(agenda.focus.count), к встречам \(agenda.meetings.count) за \(seconds) с")
                        self.answer(request.id, agenda.focus.isEmpty && agenda.meetings.isEmpty
                            ? ["ok": false, "code": "empty", "error": t("Модель вернула пустой ответ.")]
                            : ["ok": true, "agenda": ["focus": agenda.focus, "meetings": agenda.meetings], "model": model.name])
                    case .digest:
                        let digest = MailModelProtocol.withoutThinking(text)
                        DebugLog.write("почта для модели: итоги готовы за \(seconds) с")
                        self.answer(request.id, digest.isEmpty
                            ? ["ok": false, "code": "empty", "error": t("Модель вернула пустой ответ.")]
                            : ["ok": true, "text": digest, "model": model.name])
                    }
                case .failure(let error):
                    DebugLog.write("почта для модели: модель не ответила — \(error.localizedDescription)")
                    self.answer(request.id, ["ok": false, "code": "failed",
                                             "error": tf("Модель не ответила: %@", error.localizedDescription)])
                }
                self.next()
            }
        )
    }

    private func answer(_ id: String, _ payload: [String: Any]) {
        guard MailModelProtocol.isValidID(id) else { return }
        var body = payload
        body["version"] = MailModelProtocol.version
        body["id"] = id
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: Self.answers, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            let temporary = Self.answers.appendingPathComponent(".\(id).tmp")
            try data.write(to: temporary, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let target = Self.answers.appendingPathComponent("\(id).json")
            try? manager.removeItem(at: target)
            try manager.moveItem(at: temporary, to: target)
        } catch {
            DebugLog.write("почта для модели: ответ не записан — \(error.localizedDescription)")
        }
    }
}
