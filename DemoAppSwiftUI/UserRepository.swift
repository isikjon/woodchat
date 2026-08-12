//
// WoodChat — внутренний мессенджер Woodstream.
// Хранение сессии пользователя (токены Stream и REST API) в Keychain.
//

import Foundation
import StreamChat

protocol UserRepository {
    func save(user: UserCredentials)

    func loadCurrentUser() -> UserCredentials?

    func removeCurrentUser()
}

/// Keychain-хранилище учётных данных. Токены и профиль лежат в защищённом
/// хранилище с доступом только после первой разблокировки и только на этом
/// устройстве (не попадает в резервные копии iCloud/iTunes).
final class SecureUserRepository: UserRepository {
    private let service = "online.woodstream.woodchat"
    private let account = "current-user"

    // Однократная миграция со старого небезопасного хранилища (UserDefaults).
    private let legacyDefaultsKey = "stream.chat.user"

    @MainActor static let shared = SecureUserRepository()

    private init() {
        migrateFromDefaultsIfNeeded()
    }

    func save(user: UserCredentials) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        writeToKeychain(data)
    }

    func loadCurrentUser() -> UserCredentials? {
        guard let data = readFromKeychain() else { return nil }
        return try? JSONDecoder().decode(UserCredentials.self, from: data)
    }

    func removeCurrentUser() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain

    private func writeToKeychain(_ data: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Обновляем, если запись уже есть, иначе создаём.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private func readFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func migrateFromDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.data(forKey: legacyDefaultsKey) else { return }
        // Переносим в Keychain и стираем открытую копию.
        if readFromKeychain() == nil {
            writeToKeychain(legacy)
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
