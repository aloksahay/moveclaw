import SwiftUI

struct LiveBetView: View {
    @EnvironmentObject var viewModel: BetViewModel

    var body: some View {
        ZStack {
            // Full-screen camera preview
            CameraPreview(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Dark gradient overlays for readability
            VStack {
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()

            // Content overlays
            VStack {
                // Top: Question + Timer
                topOverlay
                    .padding(.top, 60)

                Spacer()

                // Resolution overlay
                if case .resolved(let outcome) = viewModel.state {
                    resolutionOverlay(outcome: outcome)
                }

                Spacer()

                // Bottom: Monitoring status + voice
                bottomOverlay
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Top Overlay

    private var topOverlay: some View {
        VStack(spacing: 12) {
            if case .monitoring(let question, _) = viewModel.state {
                Text(question)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Countdown timer
            Text(timerText)
                .font(.system(size: 48, weight: .bold, design: .monospaced))
                .foregroundStyle(viewModel.timeRemaining < 10 ? .red : .white)

            // On-device vision classifications
            if !viewModel.visionService.topClassifications.isEmpty {
                Text(viewModel.visionService.topClassifications.prefix(3).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(spacing: 12) {
            // Monitoring status
            HStack(spacing: 8) {
                if case .monitoring = viewModel.state {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                }
                Text(viewModel.monitoringStatus)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // Voice controls
            HStack(spacing: 16) {
                // Mic button (smaller than voice chat screen)
                Button {
                    toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.voiceService.isListening ? Color.red : Color.white.opacity(0.3))
                            .frame(width: 48, height: 48)

                        Image(systemName: viewModel.voiceService.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                }

                // Live transcript
                if viewModel.voiceService.isListening && !viewModel.voiceService.transcript.isEmpty {
                    Text(viewModel.voiceService.transcript)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: 200, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Resolution Overlay

    private func resolutionOverlay(outcome: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: outcome ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(outcome ? .green : .red)

            Text("BET RESOLVED")
                .font(.title.bold())
                .foregroundStyle(.white)

            Text(outcome ? "YES" : "NO")
                .font(.system(size: 56, weight: .heavy))
                .foregroundStyle(outcome ? .green : .red)

            Button("New Bet") {
                viewModel.resetToChat()
            }
            .font(.headline)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.white)
            .foregroundStyle(.black)
            .clipShape(Capsule())
            .padding(.top, 8)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
    }

    // MARK: - Helpers

    private var timerText: String {
        let seconds = Int(viewModel.timeRemaining)
        return String(format: "%d", max(0, seconds))
    }

    private func toggleListening() {
        if viewModel.voiceService.isListening {
            viewModel.voiceService.stopListening()
        } else {
            viewModel.voiceService.stopSpeaking()
            viewModel.voiceService.startListening()
        }
    }
}
