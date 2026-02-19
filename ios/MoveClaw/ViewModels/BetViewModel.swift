import Foundation
import SwiftUI
import Combine

enum BetState: Equatable {
    case idle
    case chatting
    case monitoring(question: String, deadline: Date)
    case resolved(outcome: Bool)

    static func == (lhs: BetState, rhs: BetState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.chatting, .chatting): return true
        case (.monitoring(let q1, let d1), .monitoring(let q2, let d2)): return q1 == q2 && d1 == d2
        case (.resolved(let o1), .resolved(let o2)): return o1 == o2
        default: return false
        }
    }
}

@MainActor
class BetViewModel: ObservableObject {
    // MARK: - Published State

    @Published var state: BetState = .idle
    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false
    @Published var monitoringStatus = "Waiting..."
    @Published var timeRemaining: TimeInterval = 60
    @Published var activeMarketId: UInt64?

    // MARK: - Services

    let openClawService = OpenClawService()
    let cameraService = CameraService()
    let voiceService = VoiceService()
    let visionService = VisionService()

    // MARK: - Private

    private var streamBuffer = ""
    private var countdownTimer: Timer?
    private var monitorTimer: Timer?
    private var isCheckingWithClaude = false
    private var betQuestion = ""

    // MARK: - Init

    init() {
        openClawService.onMessage = { [weak self] text, done in
            Task { @MainActor in
                self?.handleAgentResponse(text: text, done: done)
            }
        }

        voiceService.onTranscriptFinalized = { [weak self] text in
            Task { @MainActor in
                self?.sendTextMessage(text)
            }
        }
    }

    // MARK: - Connection

    func connect() {
        openClawService.connect()
        state = .chatting
    }

    func updateSettings(_ settings: GatewaySettings) {
        openClawService.updateSettings(settings)
    }

    // MARK: - Messaging

    func sendTextMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        openClawService.sendMessage(trimmed)
        isStreaming = true
        streamBuffer = ""
    }

    // MARK: - Agent Response Handling

    private func handleAgentResponse(text: String, done: Bool) {
        streamBuffer += text

        if done {
            let response = streamBuffer
            messages.append(ChatMessage(role: .assistant, content: response))
            streamBuffer = ""
            isStreaming = false

            // Speak the response
            voiceService.speak(response)

            // Check for market creation
            if let (marketId, question) = parseMarketCreation(response) {
                activeMarketId = marketId
                startMonitoring(question: question)
            }

            // Check for YES/NO resolution during monitoring
            if case .monitoring = state {
                checkForResolution(response)
            }
        }
    }

    // MARK: - Market Detection

    private func parseMarketCreation(_ text: String) -> (UInt64, String)? {
        // Look for market ID
        let idPatterns = [
            #"[Mm]arket\s+(?:created|ID)[!:]?\s*(?:ID[:\s]*)?\s*(\d+)"#,
            #"market_id[:\s]+(\d+)"#,
            #"Market #(\d+)"#,
        ]

        var marketId: UInt64?
        for pattern in idPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                marketId = UInt64(text[range])
                break
            }
        }

        guard let id = marketId else { return nil }

        // Try to extract the question from the response
        let questionPatterns = [
            #"[\"']([^\"']+\?)[\"']"#,  // Quoted question
            #"question[:\s]+(.+\?)"#,    // "question: ..."
        ]

        var question = "Will the condition be met?"
        for pattern in questionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                question = String(text[range])
                break
            }
        }

        return (id, question)
    }

    // MARK: - Monitoring

    func startMonitoring(question: String) {
        betQuestion = question
        let deadline = Date().addingTimeInterval(60)
        state = .monitoring(question: question, deadline: deadline)
        timeRemaining = 60
        monitoringStatus = "Monitoring..."

        // Start camera
        cameraService.startCapture { [weak self] _ in
            // Frames are being captured; we'll grab them on our timer
        }

        // Countdown timer — every 1 second
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.timeRemaining = max(0, deadline.timeIntervalSinceNow)
                if self.timeRemaining <= 0 {
                    self.resolveMarket(outcome: false)
                }
            }
        }

        // Monitor timer — every 3 seconds, send frame to Claude
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkFrameWithClaude()
            }
        }
    }

    private func checkFrameWithClaude() {
        guard !isCheckingWithClaude else { return }
        guard case .monitoring = state else { return }
        guard let frame = cameraService.lastFrame else { return }

        // Run on-device vision first
        Task {
            let classifications = await visionService.classify(frame)
            await MainActor.run {
                visionService.topClassifications = classifications
            }

            // Optionally skip if nothing relevant is detected (but still send every ~3rd check)
            let relevant = visionService.isRelevant(classifications: classifications, toBetCondition: betQuestion)
            let classStr = classifications.prefix(3).joined(separator: ", ")
            monitoringStatus = "Detected: \(classStr.isEmpty ? "analyzing..." : classStr)"

            // Send frame to Claude for bet condition check
            guard let base64 = CameraService.imageToBase64(frame, maxWidth: 512, quality: 0.4) else { return }

            isCheckingWithClaude = true
            let prompt = "The bet is: '\(betQuestion)'. Based on this image, has the condition been met? Reply ONLY 'YES' or 'NO'."
            openClawService.sendMessage(prompt, imageBase64: base64)
            isStreaming = true
            streamBuffer = ""
        }
    }

    private func checkForResolution(_ response: String) {
        isCheckingWithClaude = false
        let upper = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if upper.contains("YES") && !upper.contains("NO") {
            resolveMarket(outcome: true)
        }
        // If it's "NO" or ambiguous, keep monitoring — timer handles final NO
    }

    func resolveMarket(outcome: Bool) {
        // Stop timers and camera
        countdownTimer?.invalidate()
        countdownTimer = nil
        monitorTimer?.invalidate()
        monitorTimer = nil
        cameraService.stopCapture()
        isCheckingWithClaude = false

        state = .resolved(outcome: outcome)

        // Tell the agent to resolve on-chain
        if let marketId = activeMarketId {
            let resolveMsg = "Resolve market \(marketId) as \(outcome ? "YES" : "NO")"
            openClawService.sendMessage(resolveMsg)
        }

        // Speak result
        voiceService.speak("Bet resolved: \(outcome ? "YES" : "NO")")
    }

    // MARK: - Reset

    func resetToChat() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        monitorTimer?.invalidate()
        monitorTimer = nil
        cameraService.stopCapture()
        isCheckingWithClaude = false
        activeMarketId = nil
        betQuestion = ""
        state = .chatting
    }
}
