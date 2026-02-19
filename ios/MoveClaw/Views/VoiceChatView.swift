import SwiftUI

struct VoiceChatView: View {
    @EnvironmentObject var viewModel: BetViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("MoveClaw")
                .font(.largeTitle.bold())
                .padding(.top, 20)

            Text("Voice-powered prediction markets")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            // Connection status
            if !viewModel.openClawService.isConnected {
                HStack(spacing: 6) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Disconnected")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.bottom, 8)
            }

            // Message transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming indicator
                        if viewModel.isStreaming {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Agent thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Live transcript while listening
            if viewModel.voiceService.isListening && !viewModel.voiceService.transcript.isEmpty {
                Text(viewModel.voiceService.transcript)
                    .font(.body)
                    .foregroundStyle(.blue)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.1))
            }

            Divider()

            // Voice controls
            HStack(spacing: 20) {
                // Mic button
                Button {
                    toggleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.voiceService.isListening ? Color.red : Color.blue)
                            .frame(width: 72, height: 72)

                        Image(systemName: viewModel.voiceService.isListening ? "mic.fill" : "mic")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                }

                // Speaking indicator
                if viewModel.voiceService.isSpeaking {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.green)
                        Text("Speaking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 16)

            // Text input fallback
            HStack {
                TextField("Or type a message...", text: $textInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendTextInput() }

                Button {
                    sendTextInput()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(textInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .onAppear {
            Task {
                await viewModel.voiceService.requestPermissions()
                viewModel.connect()
            }
        }
    }

    @State private var textInput = ""

    private func toggleListening() {
        if viewModel.voiceService.isListening {
            viewModel.voiceService.stopListening()
        } else {
            viewModel.voiceService.stopSpeaking()
            viewModel.voiceService.startListening()
        }
    }

    private func sendTextInput() {
        let text = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.sendTextMessage(text)
        textInput = ""
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
