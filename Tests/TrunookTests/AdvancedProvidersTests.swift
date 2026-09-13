import Foundation
import Testing
@testable import Trunook

/// Разовое решение: раскрывать ли «Дополнительно» с адресами и ключами.
///
/// Проверяется на своём наборе настроек, а не на общем: миграция пишет
/// в `UserDefaults`, и прогон, задевший настоящие настройки человека,
/// был бы хуже любой ошибки, которую он ловит.
@Suite("Раскрытие «Дополнительно»")
struct AdvancedProvidersTests {
    /// Свой набор настроек на один тест — и уборка за собой.
    private func проба(_ дело: (Settings) -> Void) {
        let имя = "trunook.tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: имя) else {
            Issue.record("не завёлся набор настроек")
            return
        }
        дело(Settings(defaults: defaults))
        defaults.removePersistentDomain(forName: имя)
    }

    /// Тому, кто ничего не настраивал, раздел прятать можно и нужно:
    /// ради него всё и затевалось.
    @Test("Чистой установке раздел свёрнут")
    func чистаяУстановка() {
        проба { settings in
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders == false)
        }
    }

    /// Поймано на живой машине. `migrateProviderSettings` переписывает
    /// адрес по умолчанию в поле провайдера прямым текстом, и «непустой
    /// адрес» оказывается у всех. По прежнему правилу раздел раскрылся бы
    /// каждому — то есть не спрятался бы ни у кого.
    @Test("Адрес по умолчанию своим не считается")
    func адресПоУмолчаниюНеСвой() {
        проба { settings in
            settings.setAPIURL(Settings.defaultOllamaURL, for: .ollama)
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders == false)
        }
    }

    @Test("Свой адрес раздел раскрывает")
    func свойАдресРаскрывает() {
        проба { settings in
            settings.setAPIURL("http://192.168.1.40:11434", for: .ollama)
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders)
        }
    }

    /// Свёрнутый раздел у того, кто прописал ключ, читался бы как «ключ
    /// пропал после обновления» — а он на месте.
    @Test("Прописанный ключ раздел раскрывает")
    func ключРаскрывает() {
        проба { settings in
            settings.setAPIKey("sk-выдуманный", for: .openAI)
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders)
        }
    }

    @Test("Второй провайдер раздел раскрывает")
    func второйПровайдерРаскрывает() {
        проба { settings in
            settings.setProvider(.lmStudio, enabled: true)
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders)
        }
    }

    /// Решение принимается один раз: иначе человек, свернувший раздел
    /// руками, находил бы его раскрытым после каждого запуска.
    @Test("Решение принимается только однажды")
    func решениеОдноразовое() {
        проба { settings in
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders == false)

            // Человек свернул, а потом появился второй провайдер —
            // миграция больше не вмешивается.
            settings.setProvider(.lmStudio, enabled: true)
            settings.migrateAdvancedProviders()
            #expect(settings.showsAdvancedProviders == false)
        }
    }
}
