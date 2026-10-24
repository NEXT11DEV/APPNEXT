import Foundation
import Combine
import CryptoKit
import Security

/// Offline, installation-bound subscriptions. Only the separate owner tool has
/// the signing key. The distributed app contains a verification key only.
@MainActor
final class NextLicenseStore: ObservableObject {
    struct License: Decodable {
        let app: String
        let subject: String
        let name: String
        let issued: Int64
        let expires: Int64
    }

    static let publicKeyBase64 = "HfxDxlZl9XEqrN86xR2A4kGyoop8k36ItekNw9WEhpA="
    @Published private(set) var license: License?
    @Published var message = ""
    let installationID: String
    private let vault = "app.idkplus.activation.v1"

    init() {
        if let saved = Self.read("installation", service: "app.idkplus.activation.v1") {
            installationID = saved
        } else {
            installationID = UUID().uuidString.uppercased()
            if !Self.write(installationID, account: "installation", service: "app.idkplus.activation.v1") {
                message = "تعذر حفظ معرّف التطبيق. لا تطلب كودًا حتى تعيد فتح التطبيق ويثبت المعرّف."
            }
        }
        refresh()
    }

    func refresh() {
        guard let token = Self.read("license", service: vault) else {
            license = nil
            return
        }
        license = verify(token)
    }

    func activate(_ input: String) {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = verify(token) else {
            message = "الكود غير صالح، منتهي الصلاحية، أو مخصص لمعرّف مشترك آخر."
            return
        }
        guard Self.write(token, account: "license", service: vault) else {
            message = "تعذر حفظ كود الاشتراك في سلسلة مفاتيح الجهاز."
            return
        }
        message = ""
        license = parsed
    }

    private func verify(_ token: String) -> License? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "IDK1",
              let publicData = Data(base64Encoded: Self.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData),
              let signature = Self.decodeURLBase64(String(parts[2])),
              publicKey.isValidSignature(signature, for: Data(parts[1].utf8)),
              let payload = Self.decodeURLBase64(String(parts[1])),
              let value = try? JSONDecoder().decode(License.self, from: payload),
              value.app == "app.idkplus.store", value.subject == installationID,
              value.issued <= Int64(Date().timeIntervalSince1970) + 300,
              value.expires > Int64(Date().timeIntervalSince1970), value.expires > value.issued
        else { return nil }
        return value
    }

    private static func decodeURLBase64(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }

    private static func read(_ account: String, service: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String, service: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var added = query
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(added as CFDictionary, nil) == errSecSuccess
    }
}

