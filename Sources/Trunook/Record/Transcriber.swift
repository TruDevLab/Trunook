import TrunookXPC
import AVFoundation
import Foundation
import Speech

/// Переводит записанный разговор в текст — на самом компьютере.
///
/// **Два модуля, а не один, и это не запас впрок.** Проба живьём показала:
/// `SpeechTranscriber` знает 45 языков, и русского среди них нет вовсе.
/// `DictationTranscriber` знает 54, и русский с украинским там есть. Поэтому
/// модуль выбирается по языку: где есть первый — берём его, он рассчитан
/// на связную речь; где нет — второй с пресетом долгой диктовки.
///
/// **Не `SFSpeechRecognizer`**, на котором стоит голосовой заход: тот
/// рассчитан на реплику, а не на час разговора, и режет длинное по кускам.
/// `SpeechAnalyzer` умеет взять файл целиком.
///
/// Речь наружу не уходит — то же правило, на котором стоит вся остальная
/// работа с моделью.
@available(macOS 26, *)
enum Transcriber {
    /// Чем расшифровывать этот язык.
    enum Engine {
        case speech(Locale)
        case dictation(Locale)

        var locale: Locale {
            switch self {
            case let .speech(locale), let .dictation(locale): return locale
            }
        }
    }

    enum Failure: Error {
        /// Язык не знает ни один из модулей.
        case unsupportedLanguage
        /// Языковой набор не скачан.
        case assetMissing
    }

    // MARK: - Выбор модуля

    /// Подбирает модуль под язык. `nil` — язык не знает никто.
    ///
    /// Порядок важен: `SpeechTranscriber` рассчитан на связную речь целыми
    /// кусками, диктовка — на короткие фразы. Там, где есть первый, он даёт
    /// более гладкий текст, поэтому и спрашивается первым.
    static func engine(for locale: Locale) async -> Engine? {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(match)
        }
        if let match = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(match)
        }
        return nil
    }

    /// Языки, которые знает хоть один модуль, — для списка в настройках.
    static func supportedLocales() async -> [Locale] {
        let speech = await SpeechTranscriber.supportedLocales
        let dictation = await DictationTranscriber.supportedLocales
        var seen = Set<String>()
        return (speech + dictation)
            .filter { seen.insert($0.identifier).inserted }
            .sorted { $0.identifier < $1.identifier }
    }

    private static func module(for engine: Engine) -> any SpeechModule {
        switch engine {
        case let .speech(locale):
            return SpeechTranscriber(locale: locale, preset: .transcription)
        case let .dictation(locale):
            return dictation(locale)
        }
    }

    /// Долгая диктовка со знаками препинания: без них час разговора
    /// превращается в сплошную строку, которую не прочитать ни человеку,
    /// ни модели.
    private static func dictation(_ locale: Locale) -> DictationTranscriber {
        DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: [.punctuation],
            reportingOptions: [],
            attributeOptions: []
        )
    }

    // MARK: - Языковой набор

    /// Скачан ли набор для этого языка.
    static func status(for locale: Locale) async -> AssetInventory.Status {
        guard let engine = await engine(for: locale) else { return .unsupported }
        return await AssetInventory.status(forModules: [module(for: engine)])
    }

    /// Качает языковой набор. Доля выполненного идёт наружу для полосы.
    ///
    /// Качает система к себе, а не приложение в свою папку: набор общий
    /// на всю машину, и второй раз он уже не понадобится.
    static func install(for locale: Locale, onProgress: @escaping (Double) -> Void) async throws {
        guard let engine = await engine(for: locale) else { throw Failure.unsupportedLanguage }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [module(for: engine)]
        ) else {
            // Запроса нет — значит ставить нечего: набор уже на месте.
            onProgress(1)
            return
        }

        // Доля опрашивается, а не подписывается: `Progress` отдаёт её через
        // KVO, а ради одной полосы заводить наблюдателя со своим временем
        // жизни — больше кода, чем опрос раз в треть секунды.
        let watcher = Task {
            while !Task.isCancelled {
                onProgress(request.progress.fractionCompleted)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { watcher.cancel() }

        DebugLog.write("расшифровка: качаю набор \(engine.locale.identifier)")
        try await request.downloadAndInstall()
        onProgress(1)
        DebugLog.write("расшифровка: набор \(engine.locale.identifier) поставлен")
    }

    // MARK: - Расшифровка

    /// Переводит файл в текст целиком.
    ///
    /// Файл, а не поток: расшифровка идёт после записи, и торопиться некуда.
    /// Живая расшифровка по ходу встречи стоила бы батареи весь разговор,
    /// а результат нужен один раз, в конце.
    static func text(of url: URL, locale: Locale) async throws -> String {
        guard let engine = await engine(for: locale) else { throw Failure.unsupportedLanguage }

        let status = await AssetInventory.status(forModules: [module(for: engine)])
        guard status == .installed else {
            DebugLog.write("расшифровка: набор \(engine.locale.identifier) не установлен")
            throw Failure.assetMissing
        }

        // Язык резервируется за приложением: система держит наборы
        // ограниченным числом, и без брони установленный могут вытеснить.
        // Отказ не смертелен — набор всё равно на месте.
        _ = try? await AssetInventory.reserve(locale: engine.locale)

        let audio = try AVAudioFile(forReading: url)
        switch engine {
        case let .speech(locale):
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return try await run(module: module, over: audio) { $0.text }
        case let .dictation(locale):
            return try await run(module: dictation(locale), over: audio) { $0.text }
        }
    }

    /// Общий ход для обоих модулей: пустить разбор и собрать сказанное.
    ///
    /// Дженерик, потому что у модулей нет общего типа результата: `text`
    /// лежит на своей структуре у каждого, и достать её можно только
    /// снаружи — тем замыканием, что передаёт вызывающий.
    ///
    /// **Порядок здесь не произвольный, и первая попытка на нём и встала.**
    /// Было так: анализатор создавался сразу с файлом (`inputAudioFile:`
    /// и `finishAfterFile: true`), а следом звался `analyzeSequence`. Это
    /// два разных способа скормить один файл, и вместе они не работают:
    /// конструктор уже прочёл файл и закрыл поток, а второй заход повисал
    /// молча — ни текста, ни ошибки, ни конца.
    ///
    /// Правильный порядок один: пустой анализатор, сбор результатов своей
    /// задачей, потом чтение файла, потом явное завершение. Сбор именно
    /// **до** чтения: `analyzeSequence` не вернётся, пока файл не кончится,
    /// а результаты идут по ходу, и подписавшись после, первые куски
    /// уже не застать.
    private static func run<Module: SpeechModule>(
        module: Module,
        over audio: AVAudioFile,
        text: @escaping (Module.Result) -> AttributedString
    ) async throws -> String {
        let analyzer = SpeechAnalyzer(modules: [module])

        let collected = Task {
            var pieces: [String] = []
            for try await result in module.results {
                let piece = String(text(result).characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { pieces.append(piece) }
            }
            return pieces.joined(separator: " ")
        }

        do {
            _ = try await analyzer.analyzeSequence(from: audio)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Бросить сбор обязательно: иначе задача останется висеть
            // на потоке результатов, который уже никто не закроет.
            collected.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let result = try await collected.value
        DebugLog.write("расшифровка: \(result.count) симв.")
        return result
    }
}
