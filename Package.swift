// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Тесты собираются и без Xcode. У Command Line Tools макросы swift-testing
// лежат на уровень глубже, чем компилятор ищет по умолчанию: в
// `plugins/testing`, а не в `plugins`. Без этого пути `@Test` не
// раскрывается — «plugin for module 'TestingMacros' not found».
//
// Пути добавляются, только если эта раскладка на машине действительно есть:
// у того, кто собирает с Xcode, макросы и фреймворк лежат внутри Xcode.app,
// и жёстко прописанный путь ломал бы ему сборку тестов.
let toolsRoot = "/Library/Developer/CommandLineTools"
let usesCommandLineTools = FileManager.default.fileExists(
    atPath: "\(toolsRoot)/usr/lib/swift/host/plugins/testing"
)

let testingSwiftSettings: [SwiftSetting] = usesCommandLineTools
    ? [.unsafeFlags([
        "-plugin-path", "\(toolsRoot)/usr/lib/swift/host/plugins/testing",
        "-F", "\(toolsRoot)/Library/Developer/Frameworks",
      ])]
    : []

let testingLinkerSettings: [LinkerSetting] = usesCommandLineTools
    ? [.unsafeFlags([
        "-F", "\(toolsRoot)/Library/Developer/Frameworks",
        // `-F` — чтобы слинковалось, `-rpath` — чтобы нашлось при запуске.
        "-Xlinker", "-rpath",
        "-Xlinker", "\(toolsRoot)/Library/Developer/Frameworks",
        // Testing.framework тянет ещё одну библиотеку из третьего места.
        "-Xlinker", "-rpath",
        "-Xlinker", "\(toolsRoot)/Library/Developer/usr/lib",
      ])]
    : []

let package = Package(
    name: "Trunook",
    platforms: [.macOS(.v14)],
    targets: [
        // Общий слой между приложением и XPC-хелпером: протокол и модель трека.
        .target(
            name: "TrunookXPC",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // XPC-сервис. Bundle id подменён на com.apple.controlcenter.* — это
        // условие доступа к приватному MediaRemote начиная с macOS 15.4.
        .executableTarget(
            name: "TrunookHelper",
            dependencies: ["TrunookXPC"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Trunook",
            dependencies: ["TrunookXPC"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Проверяется чистая логика: таблица размеров, расчёт состояния,
        // приоритеты плашек, разбор сочетаний. Всё, что требует окна,
        // экрана или чужого приложения, тестами не покрывается — там
        // проверка стоит дороже ошибки.
        .testTarget(
            name: "TrunookTests",
            dependencies: ["Trunook", "TrunookXPC"],
            swiftSettings: [.swiftLanguageMode(.v5)] + testingSwiftSettings,
            linkerSettings: testingLinkerSettings
        ),
    ]
)
