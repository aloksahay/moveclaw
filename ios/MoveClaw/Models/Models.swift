import Foundation

// MARK: - Chat Models

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let imageBase64: String?
    let timestamp: Date

    enum MessageRole {
        case user
        case assistant
    }

    init(role: MessageRole, content: String, imageBase64: String? = nil, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.imageBase64 = imageBase64
        self.timestamp = timestamp
    }
}

// MARK: - WebSocket JSON-RPC Models

struct JSONRPCRequest: Codable {
    let method: String
    let params: RequestParams

    struct RequestParams: Codable {
        let agentId: String
        let message: String
        let media: [MediaAttachment]?
    }

    struct MediaAttachment: Codable {
        let type: String    // "image/jpeg"
        let data: String    // base64-encoded
    }
}

struct JSONRPCResponse: Codable {
    let method: String?
    let params: ResponseParams?

    struct ResponseParams: Codable {
        let text: String?
        let done: Bool?
    }
}

// MARK: - Settings

struct GatewaySettings: Codable {
    var host: String
    var port: Int
    var token: String

    var wsURL: URL? {
        URL(string: "ws://\(host):\(port)")
    }

    static let `default` = GatewaySettings(
        host: "192.168.1.100",
        port: 18789,
        token: "moveclaw-hackathon"
    )
}
