import TrunookXPC
import AVFoundation
import AppKit
import Speech

/// Доступы, без которых голосовой ассистент не работает: микрофон
/// и распознавание речи.
///
/// Два разных доступа, а не один, хотя просят их вместе: система разводит
/// их по разным разделам настроек и спрашивает порознь. Человек может выдать
/// микрофон и отказать распознаванию — и тогда вырез будет слышать звук,
/// но не понимать слов. Отличать эти два случая нужно, чтобы объяснить,
/// куда идти.
///
/// Оба запрашиваются программно — в отличие от Универсального доступа,
/// который система отдаёт только руками (см. `AccessibilityAccess`).
enum VoiceAccess {
    enum State {
        case granted
        case notAsked
        case denied
    }

    // MARK: - Микрофон

    static var microphone: State {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            // Ответ приходит на чужой очереди, а звать его будут из вёрстки
            // и из служб, живущих в главном потоке.
            DispatchQueue.main.async {
                DebugLog.write("микрофон: доступ \(granted ? "выдан" : "закрыт")")
                completion(granted)
            }
        }
    }

    // MARK: - Распознавание речи

    static var recognition: State {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    static func requestRecognition(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                let granted = status == .authorized
                DebugLog.write("распознавание речи: доступ \(granted ? "выдан" : "закрыт")")
                completion(granted)
            }
        }
    }

    // MARK: - Оба разом

    /// Всё ли выдано, чтобы слушать.
    static var isReady: Bool {
        microphone == .granted && recognition == .granted
    }

    /// Просит недостающее — сперва микрофон, следом распознавание.
    ///
    /// По очереди, а не разом: два системных диалога, показанных
    /// одновременно, накрывают друг друга, и второй человек просто
    /// не увидит.
    static func request(_ completion: @escaping (Bool) -> Void) {
        requestMicrophone { granted in
            guard granted else {
                completion(false)
                return
            }
            requestRecognition(completion)
        }
    }

    // MARK: - Настройки

    static func openMicrophoneSettings() {
        open("Privacy_Microphone")
    }

    static func openRecognitionSettings() {
        open("Privacy_SpeechRecognition")
    }

    private static func open(_ anchor: String) {
        let address = "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
