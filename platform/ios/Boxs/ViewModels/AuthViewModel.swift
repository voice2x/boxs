import Foundation
import Observation

/// 认证 ViewModel
@Observable
@MainActor
final class AuthViewModel {
    var email = ""
    var password = ""
    var isLoading = false
    var errorMessage: String?
    var isLoggedIn: Bool { TokenManager.shared.isLoggedIn }

    private let apiClient = APIClient.shared

    // MARK: - 注册

    func register() async {
        guard validateInput() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let body = AuthRequest(email: email, password: password)
            let response: AuthResponse = try await apiClient.request(
                .init(method: .POST, path: "/api/auth/register", requiresAuth: false),
                body: body
            )
            try TokenManager.shared.saveAccessToken(response.access_token)
            try TokenManager.shared.saveRefreshToken(response.refresh_token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 登录

    func login() async {
        guard validateInput() else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let body = AuthRequest(email: email, password: password)
            let response: AuthResponse = try await apiClient.request(
                .init(method: .POST, path: "/api/auth/login", requiresAuth: false),
                body: body
            )
            try TokenManager.shared.saveAccessToken(response.access_token)
            try TokenManager.shared.saveRefreshToken(response.refresh_token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 登出

    func logout() {
        TokenManager.shared.clearTokens()
        email = ""
        password = ""
    }

    // MARK: - 验证

    private func validateInput() -> Bool {
        errorMessage = nil
        guard !email.isEmpty, email.contains("@") else {
            errorMessage = "请输入有效的邮箱地址"
            return false
        }
        guard password.count >= 6 else {
            errorMessage = "密码至少 6 位"
            return false
        }
        return true
    }
}

// MARK: - 请求/响应类型

struct AuthRequest: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let user: UserResponse
}

struct UserResponse: Decodable {
    let id: String
    let email: String
    let display_name: String?
}
