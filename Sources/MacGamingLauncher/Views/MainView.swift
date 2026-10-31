import SwiftUI

public struct MainView: View {
    @State private var state = AppState()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            if let selectedGame = state.selectedGame {
                GameDetailView(state: state, game: selectedGame)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.selectedGame = nil
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Bibliothek")
                                }
                            }
                        }
                    }
            } else {
                GameGridView(state: state)
            }
        }
        .searchable(text: $state.searchQuery, prompt: "Spiele durchsuchen...")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let engine = state.selectedEngine {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text(engine.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button(action: { state.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Bibliothek neu scannen")
            }
        }
    }
}
