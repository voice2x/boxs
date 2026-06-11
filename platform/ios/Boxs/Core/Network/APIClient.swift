import Foundation
import os.log

/// API 客户端（URLSession + async/await）
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let logger = Logger(subsystem: "com.boxs.app", category: "Network")
    private let tokenManager = TokenManager.shared

    private let baseURL: String

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.baseURL = AppConfiguration.apiBaseURL
    }

    // MARK: - 公开方法

    func request<T: Decodable>(
        _ endpoint: Endpoint,
        body: Encodable? = nil
    ) async throws -> T {
        var urlRequest = try buildRequest(endpoint, body: body)

        // 注入 Bearer Token（除公开接口外）
        if endpoint.requiresAuth {
            let token = try tokenManager.getAccessToken()
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        logger.debug("\(urlRequest.httpMethod ?? "GET") \(urlRequest.url?.absoluteString ?? "")")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Token 过期自动刷新
        if httpResponse.statusCode == 401 && endpoint.requiresAuth {
            try await refreshToken()
            var retryRequest = try buildRequest(endpoint, body: body)
            let newToken = try tokenManager.getAccessToken()
            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            if retryHTTP.statusCode >= 400 {
                throw try parseError(retryData, statusCode: retryHTTP.statusCode)
            }
            return try JSONDecoder.boxs.decode(T.self, from: retryData)
        }

        if httpResponse.statusCode >= 400 {
            throw try parseError(data, statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder.boxs.decode(T.self, from: data)
    }

    // MARK: - 私有方法

    private func buildRequest(_ endpoint: Endpoint, body: Encodable? = nil) throws -> URLRequest {
        var components = URLComponents(string: baseURL + endpoint.path)
        if let queryItems = endpoint.queryItems {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder.boxs.encode(body)
        }

        return request
    }

    private func refreshToken() async throws {
        let refreshToken = try tokenManager.getRefreshToken()
        let url = URL(string: baseURL + "/api/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.boxs.encode(["refresh_token": refreshToken])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            tokenManager.clearTokens()
            throw APIError.unauthorized
        }

        let tokenResponse = try JSONDecoder.boxs.decode(TokenResponse.self, from: data)
        try tokenManager.saveAccessToken(tokenResponse.access_token)
        try tokenManager.saveRefreshToken(tokenResponse.refresh_token)
    }

    private func parseError(_ data: Data, statusCode: Int) -> APIError {
        guard let errorResponse = try? JSONDecoder.boxs.decode(ErrorResponse.self, from: data) else {
            return APIError.httpError(statusCode: statusCode, message: "未知错误")
        }
        return APIError.httpError(statusCode: statusCode, message: errorResponse.message)
    }
}

// MARK: - 辅助类型

struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
}

struct ErrorResponse: Decodable {
    let message: String
}

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE, PATCH
}

struct Endpoint {
    let method: HTTPMethod
    let path: String
    let queryItems: [URLQueryItem]?
    let requiresAuth: Bool

    init(
        method: HTTPMethod = .GET,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.requiresAuth = requiresAuth
    }
}

// MARK: - API 错误

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, message: String)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .invalidResponse: return "无效的服务器响应"
        case .unauthorized: return "登录已过期，请重新登录"
        case .httpError(_, let message): return message
        case .decoding(let error): return "数据解析失败: \(error.localizedDescription)"
        case .network(let error): return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - JSON 编解码配置

extension JSONEncoder {
    static let boxs: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let boxs: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
