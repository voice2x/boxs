import Foundation
import Security

/// JWT Token 管理器（Keychain 安全存储）
final class TokenManager: Sendable {
    static nonisolated(unsafe) let shared = TokenManager()

    private let service = "com.boxs.app.tokens"

    private init() {}

    // MARK: - Access Token

    func saveAccessToken(_ token: String) throws {
        try save(key: "access_token", value: token)
    }

    func getAccessToken() throws -> String {
        try load(key: "access_token")
    }

    // MARK: - Refresh Token

    func saveRefreshToken(_ token: String) throws {
        try save(key: "refresh_token", value: token)
    }

    func getRefreshToken() throws -> String {
        try load(key: "refresh_token")
    }

    // MARK: - 清除

    func clearTokens() {
        delete(key: "access_token")
        delete(key: "refresh_token")
    }

    var isLoggedIn: Bool {
        (try? getAccessToken()) != nil
    }

    // MARK: - Keychain 操作

    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw TokenError.encodingFailed
        }

        // 先删除旧值
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw TokenError.saveFailed(status)
        }
    }

    private func load(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw TokenError.notFound
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw TokenError.encodingFailed
        }
        return string
    }

    @discardableResult
    private func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

// MARK: - 错误

enum TokenError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Token 编码失败"
        case .saveFailed(let status): return "Keychain 保存失败: \(status)"
        case .notFound: return "Token 未找到"
        }
    }
}
