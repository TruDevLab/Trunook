import TrunookXPC
import AppKit

/// Снимок окна приложения в файл.
///
/// Разрешения на запись экрана у приложения нет, но собственный слой оно
/// нарисовать может. Отладочная возможность: без неё вёрстку окон нельзя
/// посмотреть иначе как попросив снимок у человека.
enum WindowSnapshot {
    /// Снимает подряд несколько кадров — иначе анимацию не поймать.
    ///
    /// Нужна для `docs/demo.gif`: демонстрация выреза в окне знакомства идёт
    /// петлёй на двадцать две секунды, и одним снимком её не показать.
    /// Кадры нумеруются с ведущими нулями, чтобы сборщик читал их по порядку
    /// обычной сортировкой имён.
    static func writeSequence(
        _ window: NSWindow?,
        named name: String,
        frames: Int,
        interval: TimeInterval
    ) {
        guard window != nil else {
            DebugLog.write("съёмка «\(name)»: окно не открыто")
            return
        }
        DebugLog.write("съёмка «\(name)»: \(frames) кадров с шагом \(interval) с")
        for index in 0..<frames {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * interval) {
                write(window, named: String(format: "%@-%03d", name, index))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(frames) * interval) {
            DebugLog.write("съёмка «\(name)»: готово")
        }
    }

    static func write(_ window: NSWindow?, named name: String) {
        guard let window, let view = window.contentView, let layer = view.layer else {
            DebugLog.write("снимок «\(name)»: окно не открыто")
            return
        }

        let scale = window.backingScaleFactor
        let size = view.bounds.size
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else {
            DebugLog.write("снимок «\(name)»: не удалось создать контекст")
            return
        }

        // У `CGContext` начало координат внизу, у слоя — вверху: без
        // переворота снимок выходит вверх ногами.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)

        guard let image = context.makeImage() else {
            DebugLog.write("снимок «\(name)»: пустой контекст")
            return
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }

        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/Trunook-\(name).png")
        do {
            try data.write(to: url)
            DebugLog.write("снимок «\(name)»: \(url.path), \(width)×\(height)")
        } catch {
            DebugLog.write("снимок «\(name)»: не записался — \(error.localizedDescription)")
        }
    }
}
