import Foundation
import LocalAuthentication
import Security

// There is deliberately no UI/API for exporting or revealing a saved credential.
// Runtime reads are necessary to authenticate TDLib and decrypt its database.
struct StoredCredentials: Codable, Sendable {
    let apiID: Int32
    let apiHash: String
    let databaseKey: Data
}

struct CredentialVault {
    private let service = (Bundle.main.bundleIdentifier ?? "QRBot") + ".telegram"
    private let account = "credentials.v1"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func save(apiID: String, apiHash: String) throws {
        guard let id = Int32(apiID), id > 0, apiHash.utf8.count == 32,
              apiHash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw VaultError.invalidCredentials
        }
        // Refuse replacement: overwriting the encryption key would orphan an existing session.
        guard !containsItem() else { throw VaultError.alreadySaved }
        var key = Data(count: 32)
        let status = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        defer { key.resetBytes(in: 0..<key.count) }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
            throw VaultError.passcodeRequired
        }
        var data = try JSONEncoder().encode(StoredCredentials(apiID: id, apiHash: apiHash, databaseKey: key))
        defer { data.resetBytes(in: 0..<data.count) }
        var item = query
        item[kSecAttrAccessControl as String] = access
        item[kSecValueData as String] = data
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else { throw VaultError.keychain(result) }
    }

    func containsItem() -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        defer { context.invalidate() }
        var item = query
        item[kSecReturnAttributes as String] = true
        item[kSecUseAuthenticationContext as String] = context
        let result = SecItemCopyMatching(item as CFDictionary, nil)
        return result == errSecSuccess || result == errSecInteractionNotAllowed || result == errSecAuthFailed
    }

    func unlock() async throws -> StoredCredentials {
        // Keychain can block during user authentication; keep it away from the main thread.
        try await Task.detached(priority: .userInitiated) {
            let context = LAContext()
            context.localizedReason = "Unlock your Telegram session."
            defer { context.invalidate() }
            var item = query
            item[kSecUseAuthenticationContext as String] = context
            item[kSecReturnData as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(item as CFDictionary, &result)
            guard status == errSecSuccess, var data = result as? Data else {
                throw VaultError.keychain(status)
            }
            defer { data.resetBytes(in: 0..<data.count) }
            return try JSONDecoder().decode(StoredCredentials.self, from: data)
        }.value
    }

    func delete() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw VaultError.keychain(result) }
    }
}

enum VaultError: LocalizedError {
    case invalidCredentials, alreadySaved, passcodeRequired, keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Enter a positive API ID and the 32-character API hash from my.telegram.org."
        case .alreadySaved: "Credentials are already saved. Remove this account before replacing them."
        case .passcodeRequired: "Set an iPhone passcode before saving credentials."
        case .keychain(let code):
            switch code {
            case errSecUserCanceled: "Authentication was cancelled."
            case errSecItemNotFound: "No saved credentials. Set up this device again."
            case errSecAuthFailed, errSecInteractionNotAllowed, errSecNotAvailable:
                "Keychain is unavailable. Unlock the device and ensure a passcode is set."
            default: "Keychain could not complete the operation (\(code))."
            }
        }
    }
}

