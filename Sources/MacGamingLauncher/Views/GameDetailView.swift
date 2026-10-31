import SwiftUI

public struct GameDetailView: View {
    @Bindable var state: AppState
    let game: SteamGame

    var bottle: Bottle? {
        state.bottles.first(where: { $0.name == game.bottleName })
    }

    var isRunning: Bool {
        state.runningGameIDs.contains(game.appId)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero Banner
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: game.heroURL ?? game.headerURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(height: 280)
                                .clipped()
                        default:
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 280)
                        }
                    }

                    // Gradient overlay
                    LinearGradient(
                        colors: [.clear, Color(nsColor: .windowBackgroundColor).opacity(0.8), Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 180)

                    // Hero Content
                    VStack(alignment: .leading, spacing: 12) {
                        Text(game.name)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .shadow(radius: 8)

                        HStack(spacing: 12) {
                            // Big Action Button
                            if isRunning {
                                Button(action: { state.terminate(game: game) }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "stop.fill")
                                        Text("Beenden")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(radius: 4)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(action: { state.launch(game: game) }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                        Text("Spielen")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .shadow(radius: 4)
                                }
                                .buttonStyle(.plain)
                            }

                            // Engine / Bottle Pill
                            HStack(spacing: 6) {
                                Image(systemName: "cube.box")
                                Text(game.bottleName)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())

                            if let engine = state.selectedEngine {
                                HStack(spacing: 6) {
                                    Image(systemName: "cpu")
                                    Text(engine.name)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }

                // Main Details Section
                VStack(alignment: .leading, spacing: 24) {
                    // Quick Stats Grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        StatBox(title: "Installationsgröße", value: game.formattedSize, icon: "internaldrive")
                        StatBox(title: "Zuletzt gespielt", value: game.formattedLastPlayed, icon: "clock")
                        StatBox(title: "Steam App ID", value: game.appId, icon: "tag")
                        StatBox(title: "Ordner", value: game.installDir, icon: "folder")
                    }

                    Divider()

                    // Performance & Graphics Settings (D3DMetal / MSync)
                    if var currentBottle = bottle {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Apple Silicon & Performance-Konfiguration")
                                .font(.title3.bold())

                            Text("Passe hier die Apple GPTK- und CrossOver-Beschleunigungseinstellungen für diesen Titel an.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            VStack(spacing: 12) {
                                ToggleRow(
                                    title: "Apple D3DMetal (Metal 4 Translation)",
                                    subtitle: "Übersetzt Direct3D 11/12 hardwarebeschleunigt direkt in Apples Metal API.",
                                    icon: "sparkles",
                                    isOn: Binding(
                                        get: { currentBottle.d3dMetalEnabled },
                                        set: { newVal in
                                            currentBottle.d3dMetalEnabled = newVal
                                            state.updateBottle(currentBottle)
                                        }
                                    )
                                )

                                ToggleRow(
                                    title: "MSync (Mach Kernel Synchronization)",
                                    subtitle: "Nutzt native Darwin-Mach-Semaphore zur Vermeidung von CPU-Rucklern bei Multi-Threading.",
                                    icon: "bolt.fill",
                                    isOn: Binding(
                                        get: { currentBottle.msyncEnabled },
                                        set: { newVal in
                                            currentBottle.msyncEnabled = newVal
                                            state.updateBottle(currentBottle)
                                        }
                                    )
                                )

                                ToggleRow(
                                    title: "MetalFX Upscaling (D3DM)",
                                    subtitle: "Aktiviert temporales KI-Upscaling über die Apple Silicon Neural Engine.",
                                    icon: "arrow.up.left.and.arrow.down.right",
                                    isOn: Binding(
                                        get: { currentBottle.metalFxEnabled },
                                        set: { newVal in
                                            currentBottle.metalFxEnabled = newVal
                                            state.updateBottle(currentBottle)
                                        }
                                    )
                                )

                                ToggleRow(
                                    title: "Metal Performance HUD",
                                    subtitle: "Blendet während des Spielens FPS, Frametimes und GPU-Auslastung oben rechts ein.",
                                    icon: "gauge.with.needle",
                                    isOn: Binding(
                                        get: { currentBottle.metalHudEnabled },
                                        set: { newVal in
                                            currentBottle.metalHudEnabled = newVal
                                            state.updateBottle(currentBottle)
                                        }
                                    )
                                )
                            }
                            .padding(16)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(28)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
