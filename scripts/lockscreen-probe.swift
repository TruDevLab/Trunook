// Проба: видно ли окно над экраном блокировки.
//
//   swift scripts/lockscreen-probe.swift        # уровень 400
//   swift scripts/lockscreen-probe.swift 500    # свой уровень
//
// Под чёлкой на 90 секунд появляется чёрная капсула с часами. Заблокируйте
// экран (⌃⌘Q) и посмотрите, осталась ли она поверх экрана блокировки
// и тикают ли секунды. Потом разблокируйте — проба закроется сама.
//
// Как: закрытый SkyLight. Окно переносится в своё «пространство» с высоким
// абсолютным уровнем — так делают приложения, которые рисуют поверх экрана
// блокировки. Обычный уровень окна (`.screenSaver`, как у выреза) экран
// блокировки перекрывает.
//
// Уровни пространств (CGSSpace.h): 100 — ассистент настройки, 200 — окно
// пароля, 300 — экран блокировки, 400 — уведомления на экране блокировки.
// Первая проба стояла на 100, то есть под экраном блокировки, и капсулы
// не было видно. Нужно выше 300.

import AppKit

setvbuf(stdout, nil, _IONBF, 0)

typealias MainConnection = @convention(c) () -> Int32
typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
typealias SpaceSetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
func symbol<T>(_ name: String, _: T.Type) -> T {
    guard let pointer = dlsym(sky, name) else { fatalError("нет \(name)") }
    return unsafeBitCast(pointer, to: T.self)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
let size = CGSize(width: 260, height: 70)
let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                   width: size.width, height: size.height)
let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
window.isOpaque = false
window.backgroundColor = .clear
window.level = .screenSaver
// Без `.canJoinAllSpaces`: такое окно система раскладывает по обычным
// рабочим столам и может увести из нашего пространства.
window.collectionBehavior = [.stationary, .ignoresCycle]

let body = NSView(frame: CGRect(origin: .zero, size: size))
body.wantsLayer = true
body.layer?.backgroundColor = NSColor.black.cgColor
body.layer?.cornerRadius = 18
body.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
let label = NSTextField(labelWithString: "")
label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
label.textColor = .white
label.alignment = .center
label.frame = CGRect(x: 0, y: 10, width: size.width, height: 22)
body.addSubview(label)
window.contentView = body
window.orderFrontRegardless()

let connection = symbol("SLSMainConnectionID", MainConnection.self)()
let space = symbol("SLSSpaceCreate", SpaceCreate.self)(connection, 1, 0)
let level = Int32(CommandLine.arguments.dropFirst().first.flatMap(Int32.init) ?? 400)
func attach() {
    let set = symbol("SLSSpaceSetAbsoluteLevel", SpaceSetLevel.self)(connection, space, level)
    let show = symbol("SLSShowSpaces", ShowSpaces.self)(connection, [NSNumber(value: space)] as CFArray)
    let add = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self)(
        connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7
    )
    print("уровень \(level): set \(set), show \(show), add \(add)")
}
attach()
print("пространство \(space), окно \(window.windowNumber); заблокируйте экран в ближайшие 90 секунд")

// На блокировке — ещё раз: экран блокировки может перестроить пространства.
DistributedNotificationCenter.default().addObserver(
    forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
) { _ in
    print("экран заблокирован")
    attach()
    window.orderFrontRegardless()
}

let formatter = DateFormatter()
formatter.dateFormat = "HH:mm:ss"
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    label.stringValue = "Trunook · \(formatter.string(from: Date()))"
}
DispatchQueue.main.asyncAfter(deadline: .now() + 90) { exit(0) }
app.run()
