import Foundation
import Security

enum KeychainStore {
    private static let service = "dev.ubai.Plyph.APIKeys"

    private static var accessGroup: String? {
        Bundle.main.object(
            forInfoDictionaryKey: "KeychainAccessGroup"
        ) as? String
    }

    static func value(for provider: Provider) -> String {
        guard provider.requiresAPIKey else { return "" }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: CFTypeRef?

        guard SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess,
        let data = result as? Data else {
            return ""
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    static func set(_ value: String, for provider: Provider) throws {
        guard provider.requiresAPIKey else { return }

        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.id
        ]

        if let accessGroup {
            base[kSecAttrAccessGroup as String] = accessGroup
        }

        SecItemDelete(base as CFDictionary)

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmed.isEmpty else { return }

        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(item as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case storeFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Could not save the API key (Keychain error \(status))."
        }
    }
}
