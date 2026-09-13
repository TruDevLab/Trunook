import Foundation
import Testing
@testable import Trunook

/// Движок Ollama: что мы о нём говорим и чем опознаём.
///
/// Живьём эти случаи не собрать: чтобы увидеть Homebrew, нужна вторая
/// машина, а чтобы увидеть отказ подписи — подменённый образ. Зато все
/// решения здесь приняты чистыми функциями, и они проверяются целиком.
@Suite("Движок Ollama")
struct OllamaEngineTests {
    private func line(_ state: OllamaState, weInstalled: Bool = false) -> OllamaStatusLine {
        OllamaStatusText.line(for: state, weInstalled: weInstalled)
    }

    // MARK: - Слова и кнопки

    @Test("У каждого состояния есть своя строка")
    func строкаЕстьВсегда() {
        let состояния: [OllamaState] = [
            .unknown, .checking, .remote("ollama.example.com"), .absent,
            .stopped(.app(URL(fileURLWithPath: "/Applications/Ollama.app"))),
            .stopped(.brew(URL(fileURLWithPath: "/opt/homebrew/bin/ollama"))),
            .stopped(.foreign),
            .downloading(0.5), .verifying, .copying,
            .starting(waited: 0), .starting(waited: 12),
            .running(version: "0.33.1", from: .foreign),
            .failed(.network), .failed(.noSpace), .failed(.damaged),
            .failed(.unsigned), .failed(.wrongIdentity), .failed(.notWritable),
            .failed(.didNotStart),
        ]
        for состояние in состояния {
            #expect(!line(состояние).text.isEmpty)
        }
    }

    @Test("Кнопка соответствует состоянию")
    func кнопкиПоСостояниям() {
        let бандл = URL(fileURLWithPath: "/Applications/Ollama.app")
        #expect(line(.absent).action == .install)
        #expect(line(.stopped(.app(бандл))).action == .start)
        #expect(line(.remote("ollama.example.com")).action == .none)
        #expect(line(.downloading(0.1)).action == .cancel)
        #expect(line(.failed(.notWritable)).action == .reveal)
        #expect(line(.failed(.didNotStart)).action == .start)
        #expect(line(.running(version: nil, from: .foreign)).action == .check)
    }

    /// Самая дорогая ошибка, какую здесь можно сделать: предложить
    /// установку тому, у кого Ollama уже работает через Homebrew. Он
    /// получил бы вторую копию поверх рабочей.
    @Test("Homebrew никогда не предлагает установку")
    func homebrewНеПредлагаетУстановку() {
        let состояние = OllamaState.stopped(.brew(URL(fileURLWithPath: "/opt/homebrew/bin/ollama")))
        #expect(line(состояние).action == .copyCommand)
        #expect(line(состояние).action != .install)
    }

    /// Ollama остаётся на машине и после удаления Trunook, и человек имеет
    /// право знать, что её поставили мы.
    @Test("О своей установке говорится прямо")
    func своюУстановкуНазываем() {
        let своя = line(.running(version: "0.33.1", from: .foreign), weInstalled: true)
        let чужая = line(.running(version: "0.33.1", from: .foreign), weInstalled: false)
        #expect(своя.text != чужая.text)
        #expect(чужая.text.contains("0.33.1"))
    }

    /// Подпись, не сошедшаяся с нашим требованием, повторной попыткой
    /// не лечится: скачается то же самое и не сойдётся так же.
    @Test("Отказ подписи ведёт к установке руками, а не к повтору")
    func отказПодписиНеПовторяем() {
        #expect(line(.failed(.unsigned)).action == .reveal)
        #expect(line(.failed(.wrongIdentity)).action == .reveal)
    }

    /// Через десять секунд причина почти всегда одна — Ollama открыла своё
    /// окно и ждёт человека. Об этом надо сказать, иначе ожидание выглядит
    /// зависанием.
    @Test("Долгое ожидание объясняется её собственным окном")
    func долгоеОжиданиеОбъясняется() {
        #expect(line(.starting(waited: 0)).text != line(.starting(waited: 12)).text)
    }

    // MARK: - Адрес

    @Test("Местный адрес узнаётся, чужой — нет")
    func местныйАдрес() {
        #expect(OllamaApp.isLocalAddress("http://localhost:11434"))
        #expect(OllamaApp.isLocalAddress("http://127.0.0.1:11434"))
        #expect(OllamaApp.isLocalAddress("http://[::1]:11434"))
        // Пустой адрес — это `defaultOllamaURL`, то есть местный.
        #expect(OllamaApp.isLocalAddress(""))
        #expect(OllamaApp.isLocalAddress("   "))

        #expect(!OllamaApp.isLocalAddress("http://192.168.1.40:11434"))
        #expect(!OllamaApp.isLocalAddress("https://ollama.example.com"))
        #expect(!OllamaApp.isLocalAddress("http://host.docker.internal:11434"))
    }

    // MARK: - Опознание найденного

    /// На машине разработчика `/usr/local/bin/ollama` — симлинк внутрь
    /// бандла, который Ollama делает сама. Считать это Homebrew значило бы
    /// советовать `ollama serve` там, где надо открыть приложение.
    @Test("Симлинк внутрь бандла — это приложение, а не Homebrew")
    func симлинкВнутрьБандла() {
        let install = OllamaApp.classify(
            cli: URL(fileURLWithPath: "/usr/local/bin/ollama"),
            resolved: URL(fileURLWithPath: "/Applications/Ollama.app/Contents/Resources/ollama")
        )
        #expect(install == .app(URL(fileURLWithPath: "/Applications/Ollama.app")))
    }

    @Test("Утилита из Cellar — это Homebrew")
    func утилитаИзCellar() {
        let cli = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        let install = OllamaApp.classify(
            cli: cli,
            resolved: URL(fileURLWithPath: "/opt/homebrew/Cellar/ollama/0.33.1/bin/ollama")
        )
        #expect(install == .brew(cli))
    }

    // MARK: - Ожидание порта

    @Test("Первые попытки частые, дальше реже")
    func расписаниеОпроса() {
        for попытка in 0..<10 {
            #expect(OllamaApp.waitStep(attempt: попытка) == 0.5)
        }
        #expect(OllamaApp.waitStep(attempt: 10) == 1)
        #expect(OllamaApp.waitStep(attempt: 30) == 1)
    }

    @Test("Ожидание кончается на потолке и не идёт дальше")
    func потолокОжидания() {
        var прошло: TimeInterval = 0
        var попытка = 0
        while let шаг = OllamaApp.waitStep(attempt: попытка), попытка < 200 {
            прошло += шаг
            попытка += 1
        }
        #expect(попытка < 200, "расписание не кончается")
        #expect(прошло <= OllamaApp.ceiling)
        #expect(прошло > OllamaApp.ceiling - 2)
        #expect(OllamaApp.waitStep(attempt: попытка) == nil)
    }

    // MARK: - Требование к подписи

    /// Тест ловит случайную правку константы: скопировать в «Программы»
    /// что-то, подписанное не Ollama, — худшее, что может сделать эта работа.
    @Test("Требование к подписи называет Ollama и нотаризацию")
    func требованиеКПодписи() {
        #expect(OllamaApp.requirement.contains("3MU9H2V9Y9"))
        #expect(OllamaApp.requirement.contains("com.electron.ollama"))
        #expect(OllamaApp.requirement.contains("notarized"))
        #expect(OllamaApp.requirement.contains("anchor apple generic"))
    }
}
