import Foundation
import Security
import os.log

/// Manages a shared auth token in iCloud Keychain for session server authentication.
final class KeychainSync {

    static let shared = KeychainSync()

    private let logger = Logger(subsystem: "app.tinker", category: "KeychainSync")
    private let service = "com.familiar.session-auth"
    private let account = "session-token"

    private init() {}

    // MARK: - Public

    /// Returns the current token, generating one if none exists.
    func token() -> String {
        if let existing = read() { return existing }
        let newToken = generateToken()
        save(newToken)
        return newToken
    }

    /// Regenerates the token and returns the new value.
    @discardableResult
    func regenerate() -> String {
        let newToken = generateToken()
        delete()
        save(newToken)
        return newToken
    }

    // MARK: - Private

    private func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!
        ]
    }

    private func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue!
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.warning("Keychain read failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func save(_ token: String) {
        var query = baseQuery()
        query[kSecValueData as String] = token.data(using: .utf8)!
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save failed: \(status)")
        }
    }

    private func delete() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning("Keychain delete failed: \(status)")
        }
    }
}
