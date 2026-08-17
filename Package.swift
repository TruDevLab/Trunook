// swift-tools-version: 6.0
import PackageDescription

// Xcode на этой машине нет, только Command Line Tools, и у них макросы
// swift-testing лежат на уровень глубже, чем компилятор ищет по умолчанию:
// в `plugins/testing`, а не в `plugins`. Без этого пути `@Test`
// не раскрывается — «plugin for module 'TestingMacros' not found».
let toolsRoot = "/Library/Developer/CommandLineTools"
let testingFlags: [String] = [
    "-plugin-path", "\(toolsRoot)/usr/lib/swift/host/plugins/testing",
    "-F", "\(toolsRoot)/Library/Developer/Frameworks",
]

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
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(testingFlags)],
            // `-F` — чтобы слинковалось, `-rpath` — чтобы нашлось при запуске:
            // Testing.framework лежит внутри Command Line Tools, а не в системе.
            linkerSettings: [.unsafeFlags([
                "-F", "\(toolsRoot)/Library/Developer/Frameworks",
                "-Xlinker", "-rpath",
                "-Xlinker", "\(toolsRoot)/Library/Developer/Frameworks",
                // Сам Testing.framework тянет ещё одну библиотеку, и лежит
                // она в третьем месте — путей нужно два.
                "-Xlinker", "-rpath",
                "-Xlinker", "\(toolsRoot)/Library/Developer/usr/lib",
            ])]
        ),
    ]
)
