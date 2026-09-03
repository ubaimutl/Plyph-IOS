import Foundation
import Security

struct SharedStore {
    static let appGroup = "group.dev.ubai.plyph2"

    private static let settingsKey = "plyph.settings.v1"
    private static let actionsKey = "plyph.actions.v1"

    private static let keychainService =
        "dev.ubai.Plyph.SharedData"

    private let legacyDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        legacyDefaults =
            UserDefaults(suiteName: Self.appGroup)
            ?? .standard
    }

    // MARK: - Settings

    func loadSettings() -> AppSettings {
        if let data = keychainData(for: Self.settingsKey),
           let value = try? decoder.decode(
               AppSettings.self,
               from: data
           ) {
            return value
        }

        if let data = legacyDefaults.data(
            forKey: Self.settingsKey
        ),
        let value = try? decoder.decode(
            AppSettings.self,
            from: data
        ) {
            if !Self.isAppExtension {
                save(settings: value)
            }

            return value
        }

        return AppSettings()
    }

    func save(settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        setKeychainData(
            data,
            for: Self.settingsKey
        )

        legacyDefaults.set(
            data,
            forKey: Self.settingsKey
        )
    }

    // MARK: - Custom Actions

    func loadActions() -> [CustomAction] {
        if let data = keychainData(for: Self.actionsKey),
           let value = try? decoder.decode(
               [CustomAction].self,
               from: data
           ) {
            return value
        }

        if let data = legacyDefaults.data(
            forKey: Self.actionsKey
        ),
        let value = try? decoder.decode(
            [CustomAction].self,
            from: data
        ) {
            if !Self.isAppExtension {
                save(actions: value)
            }

            return value
        }

        return []
    }

    func save(actions: [CustomAction]) {
        guard let data = try? encoder.encode(actions) else {
            return
        }

        setKeychainData(
            data,
            for: Self.actionsKey
        )

        legacyDefaults.set(
            data,
            forKey: Self.actionsKey
        )
    }

    // MARK: - Shared Keychain

    private static var accessGroup: String? {
        Bundle.main.object(
            forInfoDictionaryKey: "KeychainAccessGroup"
        ) as? String
    }

    private static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    private func keychainData(
        for account: String
    ) -> Data? {
        var query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrService as String:
                Self.keychainService,

            kSecAttrAccount as String:
                account,

            kSecReturnData as String:
                true,

            kSecMatchLimit as String:
                kSecMatchLimitOne
        ]

        if let accessGroup = Self.accessGroup {
            query[kSecAttrAccessGroup as String] =
                accessGroup
        }

        var result: CFTypeRef?

        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return data
    }

    private func setKeychainData(
        _ data: Data,
        for account: String
    ) {
        var base: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,

            kSecAttrService as String:
                Self.keychainService,

            kSecAttrAccount as String:
                account
        ]

        if let accessGroup = Self.accessGroup {
            base[kSecAttrAccessGroup as String] =
                accessGroup
        ]

        SecItemDelete(base as CFDictionary)

        var item = base

        item[kSecValueData as String] = data

        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(
            item as CFDictionary,
            nil
        )
    }
}
