import Foundation

/// Shared validation used before any network transfer or native signing work.
enum NextSigningPolicy {
    static func credentials(certificateExpiry: Date?, profileExpiry: Date?,
                            certificateTeam: String?, profileTeam: String?, now: Date = .now) -> String? {
        guard let certificateExpiry else { return "أضف شهادة P12 صالحة من الإعدادات أولًا." }
        guard let profileExpiry else { return "أضف ملف provisioning صالحًا من الإعدادات أولًا." }
        guard certificateExpiry > now else { return "شهادة التوقيع منتهية الصلاحية." }
        guard profileExpiry > now else { return "ملف provisioning منتهي الصلاحية." }
        if let certificateTeam, let profileTeam, !certificateTeam.isEmpty,
           !profileTeam.isEmpty, certificateTeam != profileTeam {
            return "الشهادة وملف provisioning تابعان لفريقين مختلفين. اختر الملفات المتطابقة."
        }
        return nil
    }

    static func applicationPattern(_ applicationIdentifier: String?) -> String? {
        guard let value = applicationIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              let dot = value.firstIndex(of: ".") else { return nil }
        let pattern = String(value[value.index(after: dot)...])
        return pattern.isEmpty ? nil : pattern
    }

    static func identifierMatches(bundleID: String, applicationIdentifier: String?) -> Bool {
        guard let pattern = applicationPattern(applicationIdentifier) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        return bundleID.range(of: "^" + escaped + "$", options: .regularExpression) != nil
    }

    /// Informational only. The profile's signing identity and the app bundle
    /// identifier are separate inputs to zsign; their textual mismatch alone
    /// must not block an otherwise valid signing attempt.
    static func profileNotice(bundleID: String, applicationIdentifier: String?) -> String? {
        guard applicationPattern(applicationIdentifier) != nil else {
            return "تعذر عرض معرّف ملف التوقيع. سيتحقق محرك التوقيع من الملف نفسه."
        }
        guard !identifierMatches(bundleID: bundleID, applicationIdentifier: applicationIdentifier) else { return nil }
        return "معرّف التطبيق: \(bundleID)\nمعرّف ملف التوقيع: \(applicationIdentifier ?? "")\nسيُستخدم ملف التوقيع كما هو مع الحفاظ على معرّف التطبيق. اختلاف المعرّفين وحده لا يمنع محاولة التوقيع؛ قبول التثبيت يحدده iOS."
    }

    static func byteRange(_ value: String?, size: UInt64) -> (start: UInt64, end: UInt64)? {
        guard size > 0 else { return nil }
        guard let value else { return (0, size - 1) }
        guard value.hasPrefix("bytes="), !value.contains(",") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {
            guard let suffix = UInt64(parts[1]), suffix > 0 else { return nil }
            return (size - min(suffix, size), size - 1)
        }
        guard let start = UInt64(parts[0]), start < size else { return nil }
        let end = parts[1].isEmpty ? size - 1 : min(UInt64(parts[1]) ?? UInt64.max, size - 1)
        guard end >= start, parts[1].isEmpty || UInt64(parts[1]) != nil else { return nil }
        return (start, end)
    }
}
