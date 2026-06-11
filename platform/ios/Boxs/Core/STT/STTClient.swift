import Foundation
import Starscream
import os.log

/// STT 客户端 — Starscream WebSocket 连接后端 /ws/stt?token=xxx
final class STTClient: NSObject, WebSocketDelegate, ObservableObject {
    private var socket: WebSocket?
    private let logger = Logger(subsystem: "com.boxs.app", category: "STT")

    /// STT 识别结果回调
    var onResult: ((String) -> Void)?

    /// 连接状态变化回调
    var onConnectionChange: ((Bool) -> Void)?

    /// 是否已连接
    @Published private(set) var isConnected = false

    // MARK: - 公开方法

    /// 连接 STT WebSocket
    func connect(token: String) async throws {
        let urlString = "\(AppConfiguration.sttWebSocketURL)?token=\(token)"
        guard let url = URL(string: urlString) else {
            throw STTError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        socket = WebSocket(request: request)
        socket?.delegate = self
        socket?.connect()

        logger.info("STT WebSocket 连接中: \(urlString)")
    }

    /// 发送音频数据
    func sendAudioData(_ data: Data) {
        guard let socket, isConnected else { return }
        socket.write(data: data)
    }

    /// 断开连接
    func disconnect() {
        socket?.disconnect()
        socket = nil
        isConnected = false
        logger.info("STT WebSocket 断开")
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected:
            isConnected = true
            onConnectionChange?(true)
            logger.info("STT WebSocket 已连接")

        case .disconnected(let reason, let code):
            isConnected = false
            onConnectionChange?(false)
            logger.info("STT WebSocket 断开: \(code) - \(reason)")

        case .text(let text):
            // 解析 STT 识别结果
            parseResult(text)

        case .binary(let data):
            // 处理二进制响应（某些 STT 服务可能使用）
            if let text = String(data: data, encoding: .utf8) {
                parseResult(text)
            }

        case .error(let error):
            isConnected = false
            onConnectionChange?(false)
            logger.error("STT WebSocket 错误: \(error?.localizedDescription ?? "未知")")

        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break

        case .cancelled:
            isConnected = false
            onConnectionChange?(false)

        case .peerClosed:
            isConnected = false
            onConnectionChange?(false)
        }
    }

    // MARK: - 私有方法

    private func parseResult(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 非 JSON 格式，直接作为识别结果
            onResult?(text)
            return
        }

        // 解析标准响应格式
        if let result = json["text"] as? String {
            onResult?(result)
        } else if let result = json["result"] as? String {
            onResult?(result)
        } else if let result = json["data"] as? String {
            onResult?(result)
        }
    }
}

// MARK: - 错误

enum STTError: LocalizedError {
    case invalidURL
    case connectionFailed
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的 STT 服务地址"
        case .connectionFailed: return "STT 服务连接失败"
        case .notConnected: return "STT 服务未连接"
        }
    }
}
