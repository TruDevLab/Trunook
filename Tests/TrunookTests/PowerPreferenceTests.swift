import Foundation
import Testing
@testable import Trunook

/// Когда приложение переходит в режим энергосбережения.
///
/// Правило простое, но ошибка в нём молчаливая: режим, включившийся от сети,
/// тихо гасит сценки и откладывает сводки, и человек видит лишь, что
/// «что-то перестало работать».
@Suite("Энергосбережение")
struct PowerPreferenceTests {
    @Test("«Никогда» не включается ни от чего")
    func никогда() {
        for low in [false, true] {
            for battery in [false, true] {
                #expect(!PowerPreference.isSaving(mode: .never, lowPowerMode: low, onBattery: battery))
            }
        }
    }

    @Test("По умолчанию — только вслед за режимом macOS, от аккумулятора — нет")
    func режимMacOS() {
        #expect(PowerPreference.isSaving(mode: .lowPowerMode, lowPowerMode: true, onBattery: false))
        #expect(!PowerPreference.isSaving(mode: .lowPowerMode, lowPowerMode: false, onBattery: true))
        #expect(!PowerPreference.isSaving(mode: .lowPowerMode, lowPowerMode: false, onBattery: false))
    }

    @Test("«От аккумулятора» включается и от режима macOS")
    func аккумулятор() {
        #expect(PowerPreference.isSaving(mode: .battery, lowPowerMode: false, onBattery: true))
        #expect(PowerPreference.isSaving(mode: .battery, lowPowerMode: true, onBattery: false))
        #expect(!PowerPreference.isSaving(mode: .battery, lowPowerMode: false, onBattery: false))
    }

    @Test("Без записанной настройки — «В режиме энергосбережения macOS»")
    func поУмолчанию() {
        let settings = Trunook.Settings(defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!)
        #expect(settings.powerSavingMode == .lowPowerMode)
        settings.powerSavingMode = .battery
        #expect(settings.powerSavingMode == .battery)
    }
}
