import SwiftUI

@main
struct MoveClawApp: App {
    @StateObject private var viewModel = BetViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: BetViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .chatting:
                    VoiceChatView()
                case .monitoring, .resolved:
                    LiveBetView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
