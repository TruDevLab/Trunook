import TrunookXPC
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import Speech

/// Проба: что из захвата звука и расшифровки доступно **этому** приложению.
///
/// Отдельным заходом, а не проверкой по ходу работы, и на то есть прямая
/// причина из `DEVELOPMENT.md` («Голоса Siri третьим приложениям не отдают»):
/// доступность служб `AVFoundation` и `Speech` зависит от того, кто
/// спрашивает. Скрипт под интерпретатором подписан Apple и отвечает не то,
/// что ответит собранный бинарник со своей подписью. Поэтому проба живёт
/// внутри приложения и вызывается отладочным событием.
///
/// Пишет в журнал и ничего не меняет: ни устройства, ни настроек.
enum AudioProbe {
    static func run() {
        DebugLog.write("проба звука: начали")
        listDevices()
        probeTap()
        probeSpeech()
    }

    // MARK: - Устройства

    private static func listDevices() {
        let outputs = AudioDevices.outputs()
        let inputs = AudioDevices.inputs()
        DebugLog.write("проба звука: вывод — \(names(outputs))")
        DebugLog.write("проба звука: ввод — \(names(inputs))")
        DebugLog.write("проба звука: сейчас вывод \(AudioDevices.defaultOutput?.name ?? "—"), "
            + "ввод \(AudioDevices.defaultInput?.name ?? "—")")
    }

    private static func names(_ devices: [AudioDevice]) -> String {
        devices.isEmpty ? "ничего" : devices.map(\.name).joined(separator: ", ")
    }

    /// Счётчик, который можно трогать с двух потоков сразу.
    private final class Counter {
        private let lock = NSLock()
        private var total = 0

        func add(_ count: Int) {
            lock.lock()
            total += count
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return total
        }
    }

    // MARK: - Захват звука системы

    /// Поднимает отвод звука системы, слушает секунду и разбирает всё обратно.
    ///
    /// Секунда — не про качество, а про единственный вопрос: доходят ли
    /// кадры вообще. Отвод, созданный без разрешения, создаётся успешно
    /// и молча отдаёт тишину — по коду возврата этого не видно, видно
    /// только по счётчику кадров.
    private static func probeTap() {
        guard #available(macOS 14.2, *) else {
            DebugLog.write("проба звука: отводы появились в macOS 14.2, здесь старее")
            return
        }
        SystemAudioTap.open { session in
            guard let session else {
                DebugLog.write("проба звука: отвод не поднялся — захват встречи недоступен")
                return
            }
            DebugLog.write("проба звука: отвод поднят, формат "
                + "\(Int(session.format.mSampleRate)) Гц, \(session.format.mChannelsPerFrame) кан.")

            // Счётчик растёт на потоке звуковой подсистемы, а читается
            // на главном: замок, а не просто переменная.
            let frames = Counter()
            session.onFrames = { frames.add($0) }
            session.start { started in
                guard started else {
                    DebugLog.write("проба звука: отвод не запустился")
                    session.close()
                    return
                }
                // Ждём не блокируя главный поток: приложение живёт событиями,
                // и сон здесь подвесил бы вырез на всё время прослушивания.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    session.close()
                    let count = frames.value
                    if count > 0 {
                        DebugLog.write("проба звука: кадров за секунду — \(count), захват работает")
                    } else {
                        DebugLog.write("проба звука: кадров нет. Либо не выдан доступ "
                            + "«Запись экрана и звука системы», либо в системе сейчас тишина")
                    }
                }
            }
        }
    }

    // MARK: - Расшифровка

    private static func probeSpeech() {
        guard #available(macOS 26, *) else {
            DebugLog.write("проба звука: расшифровка требует macOS 26, здесь "
                + "\(ProcessInfo.processInfo.operatingSystemVersionString)")
            return
        }
        Task {
            DebugLog.write("проба звука: SpeechTranscriber доступен — \(SpeechTranscriber.isAvailable)")
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            DebugLog.write("проба звука: языков поддержано \(supported.count), "
                + "установлено \(installed.count) — \(codes(installed))")
            DebugLog.write("проба звука: поддержаны — \(codes(supported))")

            // Второй модуль расшифровки: у него свой список языков, и он
            // бывает шире. Если чат-модель проекта говорит по-русски,
            // а расшифровка нет — это надо знать до, а не после.
            let dictation = await DictationTranscriber.supportedLocales
            DebugLog.write("проба звука: диктовка поддерживает \(dictation.count) — \(codes(dictation))")

            for code in ["ru-RU", "en-US"] {
                let locale = Locale(identifier: code)
                let match = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
                guard let match else {
                    DebugLog.write("проба звука: \(code) не поддержан вовсе")
                    continue
                }
                let module = SpeechTranscriber(locale: match, preset: .transcription)
                let status = await AssetInventory.status(forModules: [module])
                DebugLog.write("проба звука: \(code) → \(match.identifier), набор \(name(of: status))")
            }

            for code in ["ru-RU", "en-US"] {
                let locale = Locale(identifier: code)
                guard let match = await DictationTranscriber.supportedLocale(equivalentTo: locale)
                else {
                    DebugLog.write("проба звука: диктовка \(code) не поддержана")
                    continue
                }
                let module = DictationTranscriber(locale: match, preset: .longDictation)
                let status = await AssetInventory.status(forModules: [module])
                DebugLog.write("проба звука: диктовка \(code) → \(match.identifier), "
                    + "набор \(name(of: status))")
            }
        }
    }

    @available(macOS 26, *)
    private static func codes(_ locales: [Locale]) -> String {
        locales.isEmpty ? "ничего" : locales.map(\.identifier).joined(separator: ", ")
    }

    /// Состояние набора по-русски: в журнал смотрит человек, а не машина.
    @available(macOS 26, *)
    private static func name(of status: AssetInventory.Status) -> String {
        switch status {
        case .installed: return "установлен"
        case .downloading: return "качается"
        case .supported: return "есть, но не скачан"
        case .unsupported: return "недоступен"
        @unknown default: return "неизвестно"
        }
    }
}
