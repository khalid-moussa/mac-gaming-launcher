import SwiftUI

public struct GameCardView: View {
    public let game: SteamGame
    public let isRunning: Bool
    public let onPlay: () -> Void
    public let onSelect: () -> Void

    @State private var isHovered: Bool = false

    public init(
        game: SteamGame,
        isRunning: Bool,
        onPlay: @escaping () -> Void,
        onSelect: @escaping () -> Void
    ) {
        self.game = game
        self.isRunning = isRunning
        self.onPlay = onPlay
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    // Poster Image
                    AsyncImage(url: game.posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(2/3, contentMode: .fill)
                        case .failure:
                            fallbackCard
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.15))
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            .aspectRatio(2/3, contentMode: .fit)
                        @unknown default:
                            fallbackCard
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isHovered ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isHovered ? 2 : 1)
                    )
                    .shadow(color: isHovered ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.2), radius: isHovered ? 12 : 6, y: 4)

                    // Running indicator or Quick Play button on hover
                    if isRunning {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Läuft")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                    } else if isHovered {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.body.bold())
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // Title and Meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    HStack(spacing: 6) {
                        Text(game.formattedSize)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(game.bottleName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
    }

    private var fallbackCard: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.7))
                Text(game.name)
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
    }
}
