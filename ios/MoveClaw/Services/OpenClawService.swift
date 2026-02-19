import Foundation

@MainActor
class OpenClawService: ObservableObject {
    @Published var isConnected = false
    @Published var lastError: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession
    private var settings: GatewaySettings
    var onMessage: ((String, Bool) -> Void)?

    init(settings: GatewaySettings = .default) {
        self.settings = settings
        self.session = URLSession(configuration: .default)
    }

    func updateSettings(_ newSettings: GatewaySettings) {
        settings = newSettings
        if isConnected {
            disconnect()
            connect()
        }
    }

    func connect() {
        guard let url = settings.wsURL else {
            lastError = "Invalid gateway URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        lastError = nil
        receiveMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func sendMessage(_ text: String, imageBase64: String? = nil, agentId: String = "main") {
        var media: [JSONRPCRequest.MediaAttachment]? = nil
        if let imageBase64 {
            media = [JSONRPCRequest.MediaAttachment(type: "image/jpeg", data: imageBase64)]
        }

        let request = JSONRPCRequest(
            method: "agent.send",
            params: .init(agentId: agentId, message: text, media: media)
        )

        guard let data = try? JSONEncoder().encode(request),
              let jsonString = String(data: data, encoding: .utf8) else {
            lastError = "Failed to encode message"
            return
        }

        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage()

                case .failure(let error):
                    self.isConnected = false
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) else {
            return
        }

        if response.method == "agent.response",
           let params = response.params,
           let responseText = params.text {
            let done = params.done ?? false
            onMessage?(responseText, done)
        }
    }
}
