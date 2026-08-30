import TrunookXPC
import Foundation
import Security

/// Проверка, что скачанное подписано тем же, чем подписаны мы сами.
///
/// Это **главная** проверка обновления, и она сильнее контрольной суммы.
/// Сумму пишет рукой человек и кладёт в тот же ответ того же API, откуда
/// приходит ссылка на образ: кто подменит образ — подменит и сумму. А закрытый
/// ключ `Trunook Dev Signing` лежит только на машине разработчика, и доступ
/// к учётной записи GitHub его не даёт.
///
/// Довод сильнее: требование к подписи — это ровно тот предикат, по которому
/// система решает, переносятся ли разрешения TCC на подменённый бандл. Хеша
/// кода в нём нет, поэтому доступы подмену переживают. Значит проверка
/// и польза здесь — одно и то же: прошла — календарь, микрофон и универсальный
/// доступ останутся выданными; не прошла — подмена всё равно обнулила бы их,
/// и отказ ничего не отнимает.
enum CodeSignatureCheck {
    enum Verdict: Equatable {
        case valid
        case rejected(UpdateFailure)
    }

    /// Проверяет бандл по пути против собственного требования к подписи.
    ///
    /// Требование берётся через `SecCodeCopySelf` — это взгляд ядра на код,
    /// исполняемый прямо сейчас, а не чтение файлов с диска. Разница тонкая,
    /// но существенная: читать с диска значило бы спрашивать у того же
    /// материала, который посторонний с правом записи мог бы подправить.
    /// Хеш сертификата в код не зашивается вовсе.
    ///
    /// Тестом это не покрыто и покрыто быть не может: нужен подписанный бандл
    /// и живая служба. Под тестом — только `verdict(for:)`.
    static func matchesSelf(_ bundle: URL) -> Verdict {
        guard let requirement = ownRequirement() else {
            DebugLog.write("обновление: своё требование к подписи не прочиталось")
            return .rejected(.damaged)
        }

        var candidate: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundle as CFURL, [], &candidate)
        guard created == errSecSuccess, let candidate else { return verdict(for: created) }

        // `kSecCSCheckNestedCode` обязателен: внутри бандла лежит
        // `XPCServices/TrunookHelper.xpc` — второй исполняемый файл, который
        // запустится отдельным процессом и получит наши права. Без флага
        // его не проверяют вовсе.
        let flags = SecCSFlags(rawValue: UInt32(
            kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        ))

        var failure: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(candidate, flags, requirement, &failure)
        if status != errSecSuccess {
            let reason = failure?.takeRetainedValue().localizedDescription ?? "\(status)"
            DebugLog.write("обновление: подпись отклонена — \(reason)")
        }
        return verdict(for: status)
    }

    /// Что означает код, вернувшийся из Security.framework.
    ///
    /// Вынесено отдельно и без побочных действий: это единственная часть
    /// проверки, которую можно закрыть тестом.
    static func verdict(for status: OSStatus) -> Verdict {
        switch status {
        case errSecSuccess:
            return .valid
        case errSecCSUnsigned:
            // Подписи нет вовсе — это случай «образ подменили».
            return .rejected(.unsigned)
        case errSecCSReqFailed:
            // Подписано, но другим сертификатом. Однажды случится законно:
            // `make cert` выпускает самоподписанный заново, и корень меняется.
            // Обновляться после этого придётся руками — и это правильная цена:
            // такая замена всё равно сбрасывает все разрешения.
            return .rejected(.wrongCertificate)
        default:
            return .rejected(.damaged)
        }
    }

    private static func ownRequirement() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }

        var still: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &still) == errSecSuccess, let still else { return nil }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(still, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}
