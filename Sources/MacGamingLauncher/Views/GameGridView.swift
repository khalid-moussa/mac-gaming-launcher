import SwiftUI

public struct GameGridView: View {
    @Bindable var state: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 20)
    ]

    public var body: some View {
        ScrollView {
            if state.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(state.statusMessage ?? "Lade Steam-Bibliothek...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else if state.filteredGames.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Keine Spiele gefunden")
                        .font(.title3.bold())
                    Text("Stelle sicher, dass in deiner Steam-Bottle Spiele installiert sind, oder passe deine Suche an.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(state.filteredGames) { game in
                        GameCardView(
                            game: game,
                            isRunning: state.runningGameIDs.contains(game.appId),
                            onPlay: {
                                state.launch(game: game)
                            },
                            onPlayWithHUD: {
                                state.launch(game: game, overrideHUD: true)
                            },
                            onSelect: {
                                state.selectedGame = game
                            },
                            onRevealInFinder: {
                                state.revealInFinder(game: game)
                            },
                            onOpenStore: {
                                state.openSteamStore(game: game)
                            }
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
