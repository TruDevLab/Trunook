import TrunookXPC
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Миниатюры окон для переключателя.
///
/// Снимаются ScreenCaptureKit'ом — `CGWindowListCreateImage` в новых SDK
/// убран. Для этого нужна «Запись экрана»: миниатюры — настройка,
/// выключенная по умолчанию, и разрешение спрашивается в момент её
/// включения. Без разрешения переключатель показывает значки приложений.
///
/// Снимаются только когда панель действительно показана: быстрое ⌘Tab
/// без панели не стоит ни одного снимка. Снимок маленький — под размер
/// карточки, а не окна.
enum WindowThumbnails {
    /// Есть ли «Запись экрана». Ответ система держит до перезапуска
    /// приложения: выданное разрешение заработает после него.
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Миниатюры включили — спросить «Запись экрана».
    ///
    /// Системный вопрос появляется только однажды: после отказа
    /// `CGRequestScreenCaptureAccess` молчит. Поэтому первый раз — вопрос,
    /// дальше — раздел Системных настроек, где галочку ставят руками.
    /// Возвращает его без ответа и в первый раз: ответ человека система
    /// сообщает приложению только после перезапуска.
    static func requestAccess(defaults: UserDefaults = .standard) {
        guard !isAllowed else { return }
        let key = "screenCaptureAsked"
        guard defaults.bool(forKey: key) else {
            defaults.set(true, forKey: key)
            DebugLog.write("миниатюры: спрашиваем «Запись экрана»")
            _ = CGRequestScreenCaptureAccess()
            return
        }
        DebugLog.write("миниатюры: вопрос уже был — открываем Системные настройки")
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    /// Наибольший размер миниатюры в пикселях.
    static let maxPixels = CGSize(width: 288, height: 180)

    /// Размер снимка: окно вписано в `bounds`, пропорции сохранены.
    static func fit(_ window: CGSize, in bounds: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0 else { return .zero }
        let scale = min(bounds.width / window.width, bounds.height / window.height, 1)
        return CGSize(width: max(1, (window.width * scale).rounded()), height: max(1, (window.height * scale).rounded()))
    }

    /// Снять окна с этими номерами. Каждый снимок отдаётся на главный поток,
    /// как только готов, — карточки оживают по одной, а не все разом
    /// после самого медленного окна.
    static func capture(_ ids: [CGWindowID], each: @escaping (CGWindowID, NSImage) -> Void) {
        guard !ids.isEmpty, isAllowed else { return }
        Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            } catch {
                DebugLog.write("миниатюры: окна не получены — \(error.localizedDescription)")
                return
            }
            let wanted = Set(ids)
            let windows = content.windows.filter { wanted.contains($0.windowID) }
            var made = 0
            await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
                for window in windows {
                    group.addTask {
                        let size = fit(window.frame.size, in: maxPixels)
                        guard size.width >= 2, size.height >= 2 else { return (window.windowID, nil) }
                        let config = SCStreamConfiguration()
                        config.width = Int(size.width)
                        config.height = Int(size.height)
                        config.showsCursor = false
                        config.ignoreShadowsSingleWindow = true
                        let filter = SCContentFilter(desktopIndependentWindow: window)
                        let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        return (window.windowID, image)
                    }
                }
                for await (id, image) in group {
                    guard let image else { continue }
                    made += 1
                    let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    DispatchQueue.main.async { each(id, picture) }
                }
            }
            DebugLog.write(String(format: "миниатюры: %d из %d за %.0f мс", made, ids.count,
                                  (CFAbsoluteTimeGetCurrent() - start) * 1000))
        }
    }
}
