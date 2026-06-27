import Foundation

/// 同步层网络抽象(便于注入 mock 做单测)。Sendable 约束保证跨 actor 安全。
protocol SyncNetworking: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, body: (any Encodable & Sendable)?) async throws -> T
}

extension APIClient: SyncNetworking {
    /// 包装现有 request,使 APIClient 遵循 SyncNetworking(Sendable 约束版)
    func send<T: Decodable & Sendable>(_ endpoint: Endpoint, body: (any Encodable & Sendable)?) async throws -> T {
        try await request(endpoint, body: body)
    }
}
