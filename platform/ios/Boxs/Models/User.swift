import Foundation

/// 用户领域模型
struct User: Codable, Sendable {
    let id: String
    let email: String
    let displayName: String?
    let avatarUrl: String?
    let subscriptionTier: String
    let emailVerified: Bool
}
