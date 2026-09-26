import AppKit

/// Пространство над экраном блокировки: окно, перенесённое сюда, видно
/// поверх него.
///
/// Обычный уровень окна тут не помогает — экран блокировки перекрывает
/// любой, включая `.screenSaver` выреза. Видно окно, лежащее в своём
/// пространстве SkyLight с абсолютным уровнем выше экрана блокировки.
/// Уровни (CGSSpace.h): 100 — ассистент настройки, 200 — окно пароля,
/// 300 — экран блокировки, 400 — уведомления на нём. Проба на 100
/// не показала ничего, на 400 окно видно (`scripts/lockscreen-probe.swift`).
///
/// Функции закрытые и достаются через `dlsym`: не нашлось — `isAvailable`
/// ложно, и вырез на время блокировки просто убирается, как раньше.
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private let connection: Int32
    private let create: SpaceCreate?
    private let setLevel: SpaceSetLevel?
    private let show: ShowSpaces?
    private let add: AddWindows?
    private var space: UInt64?

    /// Выше экрана блокировки (300), на уровне его уведомлений.
    private static let level: Int32 = 400

    private init() {
        let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        func load<T>(_ name: String, _: T.Type) -> T? {
            dlsym(sky, name).map { unsafeBitCast($0, to: T.self) }
        }
        connection = load("SLSMainConnectionID", MainConnection.self)?() ?? 0
        create = load("SLSSpaceCreate", SpaceCreate.self)
        setLevel = load("SLSSpaceSetAbsoluteLevel", SpaceSetLevel.self)
        show = load("SLSShowSpaces", ShowSpaces.self)
        add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", AddWindows.self)
    }

    var isAvailable: Bool {
        connection != 0 && create != nil && setLevel != nil && show != nil && add != nil
    }

    /// Перенести окно над экраном блокировки. Обратной дороги нет —
    /// после разблокировки окно пересоздают (`NotchWindowHost.hide`).
    @discardableResult
    func attach(_ window: NSWindow) -> Bool {
        guard isAvailable, let create, let setLevel, let show, let add else { return false }
        let space = self.space ?? create(connection, 1, 0)
        self.space = space
        // Уровень и показ — на каждом переносе: экран блокировки мог
        // перестроить пространства с прошлого раза.
        _ = setLevel(connection, space, Self.level)
        _ = show(connection, [NSNumber(value: space)] as CFArray)
        _ = add(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
        window.orderFrontRegardless()
        return true
    }
}
