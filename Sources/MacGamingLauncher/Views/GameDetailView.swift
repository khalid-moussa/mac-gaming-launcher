import LauncherCore
import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 24) {
                    stats
                    if let bottle = model.bottle(for: game) {
                        compatibility(bottle)
                    }
                }
                .padding(28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle(game.name)
        .toolbar {
            ToolbarItem {
                Menu("Mehr", systemImage: "ellipsis.circle") { GameActions(game: game) }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage([game.heroURL, game.headerURL]) {
                LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .aspectRatio(contentMode: .fill)
            .frame(height: 320)
            .frame(maxWidth: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 14) {
                Text(game.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .shadow(color: .black.opacity(0.4), radius: 8)
                HStack(spacing: 12) {
                    playButton
                    if let bottle = model.bottle(for: game) {
                        Label(bottle.name, systemImage: "cube")
                            .font(.callout)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
            .padding(28)
        }
        .frame(height: 320)
    }

    @ViewBuilder private var playButton: some View {
        switch model.sessions[game.id] {
        case .running(let since):
            Button(role: .destructive) {
                Task { await model.stop(game) }
            } label: {
                Label("Beenden", systemImage: "stop.fill").font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            Text(since, style: .timer).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        case .preparing(let status):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(status).font(.callout)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        case nil:
            Button {
                Task { await model.play(game) }
            } label: {
                Label(game.isFullyInstalled ? "Spielen" : "Wird installiert …", systemImage: "play.fill")
                    .font(.headline).padding(.horizontal, 14).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!game.isFullyInstalled)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            StatTile(title: "Größe", value: game.sizeOnDisk > 0 ? game.sizeOnDisk.formatted(.byteCount(style: .file)) : "—", icon: "internaldrive")
            StatTile(title: "Spielzeit (Launcher)", value: model.playtimeText(for: game), icon: "timer")
            StatTile(title: "Zuletzt gespielt", value: model.lastPlayed(for: game).map { $0.formatted(.relative(presentation: .named)) } ?? "Noch nie", icon: "clock")
            StatTile(title: "Grafik", value: model.effectiveBackend(for: game)?.displayName ?? "—", icon: "cpu")
            StatTile(title: "Steam App-ID", value: game.appID, icon: "number")
        }
    }

    private func compatibility(_ bottle: Bottle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kompatibilität").font(.title3.bold())
            Text("Grafik-Backend, Sync und HUD gelten für alle Spiele im Bottle „\(bottle.name)“.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Bottle-Einstellungen …", systemImage: "slider.horizontal.3") { model.bottleSettingsTarget = bottle }
                Button("Log anzeigen", systemImage: "doc.text.magnifyingglass") { model.revealLog(for: bottle) }
            }
            .buttonStyle(.glass)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}
