import AppKit

/// Где именно на экране находится аппаратный вырез.
struct NotchGeometry {
    /// Экран, на котором работаем.
    let screen: NSScreen
    /// Прямоугольник выреза в координатах экрана.
    let notchRect: CGRect
    /// Есть ли у экрана настоящий вырез.
    let isHardware: Bool

    /// Встроенный дисплей ноутбука. Именно на нём живёт приложение —
    /// на внешних мониторах вырезать нечего.
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }

    /// Номер экрана в CoreGraphics. Сравнивать экраны надо по нему:
    /// `NSScreen` система пересоздаёт при каждой перестройке экранов.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(number?.uint32Value ?? 0)
    }

    /// Экран в простых значениях — для выбора, на каком жить.
    static func slot(of screen: NSScreen) -> ScreenSlot {
        let geometry = NotchGeometry(screen: screen)
        return ScreenSlot(
            id: geometry.displayID,
            frame: screen.frame,
            hasNotch: geometry.isHardware,
            trigger: geometry.openTrigger
        )
    }

    /// Зона раскрытия по наведению: вырез с запасом по бокам.
    var openTrigger: CGRect { notchRect.insetBy(dx: -4, dy: 0) }

    var displayID: CGDirectDisplayID { Self.displayID(of: screen) }

    static func current() -> NotchGeometry? {
        guard let screen = builtInScreen() ?? NSScreen.main else { return nil }
        return NotchGeometry(screen: screen)
    }

    init(screen: NSScreen) {
        self.screen = screen
        let frame = screen.frame
        let inset = screen.safeAreaInsets.top

        // На технике с вырезом система отдаёт две области по бокам от него.
        // Всё, что между ними, и есть вырез.
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            notchRect = CGRect(
                x: frame.minX + left.width,
                y: frame.maxY - inset,
                width: width,
                height: inset
            )
            isHardware = true
        } else {
            // Экран без выреза: условная чёлка по центру верхней кромки.
            // В покое она не рисуется (`NotchMetrics.resting`), но от неё
            // отмеряются наведение и полоски. Высота — по полосе меню этого
            // экрана, чтобы полоски вставали ровно в неё; полосы нет —
            // скрыта или экран без своей — системная толщина.
            let width: CGFloat = 200
            let menuBar = frame.maxY - screen.visibleFrame.maxY
            let height = menuBar > 0 ? menuBar : NSStatusBar.system.thickness
            notchRect = CGRect(
                x: frame.midX - width / 2,
                y: frame.maxY - height,
                width: width,
                height: height
            )
            isHardware = false
        }
    }

    /// Кадр окна для заданного размера содержимого: приклеен к верхней кромке
    /// и отцентрован по вырезу.
    func windowFrame(contentSize: CGSize) -> CGRect {
        CGRect(
            x: notchRect.midX - contentSize.width / 2,
            y: screen.frame.maxY - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
    }

    var description: String {
        let kind = isHardware ? "аппаратный" : "синтетический"
        return String(
            format: "экран %.0f×%.0f, вырез %@ %.0f×%.0f в x=%.0f",
            screen.frame.width, screen.frame.height,
            kind, notchRect.width, notchRect.height, notchRect.minX
        )
    }
}
