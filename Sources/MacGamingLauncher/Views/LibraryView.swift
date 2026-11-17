import LauncherCore
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 22)]

    var body: some View {
        let games = model.visibleGames
        ScrollView {
            if !model.isSetupComplete {
                SetupBanner().padding([.horizontal, .top], 24)
            }
            if games.isEmpty {
                emptyState.padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(games) { game in
                        GameCard(game: game)
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(games.count) \(games.count == 1 ? "Spiel" : "Spiele")")
    }

    private var title: String {
        switch model.selection {
        case .library(let filter): filter.title
        case .bottle(let id): model.bottle(id: id)?.name ?? "Bottle"
        case .macSteam: "Steam (macOS)"
        case .none: "Bibliothek"
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else if showsInstallPrompt, let bottle = emptyStateBottle, model.steamInstalled.contains(bottle.id) {
            ContentUnavailableView {
                Label("Noch keine Spiele installiert", systemImage: "gamecontroller")
            } description: {
                Text(model.accounts[bottle.id] == nil
                     ? "Öffne Steam und melde dich mit deinem Konto an. Danach kannst du Spiele aus deiner Bibliothek installieren – sie erscheinen automatisch hier."
                     : "Installiere Spiele in Steam – sie erscheinen automatisch hier.")
            } actions: {
                Button("Steam öffnen") { Task { await model.openSteam(in: bottle) } }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ContentUnavailableView("Keine Spiele", systemImage: "gamecontroller", description: Text(model.selection == .library(.recent)
                ? "Hier erscheinen Spiele, sobald du sie über den Launcher gespielt hast."
                : "Für diesen Filter gibt es keine Spiele."))
        }
    }

    /// "Install games in Steam" fits when there are no games at all, nothing installed, or an empty bottle is selected.
    private var showsInstallPrompt: Bool {
        if case .bottle = model.selection { return true }
        return model.games.isEmpty || model.selection == .library(.installed)
    }

    /// The selected bottle, else the primary one.
    private var emptyStateBottle: Bottle? {
        if case .bottle(let id) = model.selection { return model.bottle(id: id) }
        return model.primaryBottle
    }
}

struct GameCard: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame
    @State private var isHovered = false

    var body: some View {
        let session = model.sessions[game.id]
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CachedImage([game.posterURL]) { PosterPlaceholder(name: game.name) }
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isHovered ? Color.accentColor : .white.opacity(0.1), lineWidth: isHovered ? 2 : 1)
                    }
                    .shadow(color: .black.opacity(isHovered ? 0.35 : 0.18), radius: isHovered ? 14 : 6, y: 4)
                    .scaleEffect(isHovered ? 1.02 : 1)

                badge(for: session)
                    .padding(10)
            }
            .contentShape(.rect)
            // The double tap must be declared first, or the single tap always wins.
            .onTapGesture(count: 2) { if game.isFullyInstalled, model.activity == nil { model.launch(game) } }
            .onTapGesture { model.selectedGameID = game.id }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name).font(.headline).lineLimit(1)
                Text(statusLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .onHover { hovering in withAnimation(.snappy(duration: 0.2)) { isHovered = hovering } }
        .contextMenu { GameActions(game: game) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.selectedGameID = game.id }
        .accessibilityAction(named: "Spielen") { if game.isFullyInstalled { model.launch(game) } }
    }

    private var statusLine: String {
        if !game.isFullyInstalled { return "Wird von Steam installiert/aktualisiert" }
        return [game.sizeOnDisk > 0 ? game.sizeOnDisk.formatted(.byteCount(style: .file)) : nil, model.sourceName(for: game)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func badge(for session: SessionState?) -> some View {
        switch session {
        case .running:
            Label("Läuft", systemImage: "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: .capsule)
        case .preparing:
            ProgressView().controlSize(.small)
                .padding(8)
                .background(.ultraThinMaterial, in: .circle)
        case nil:
            if isHovered && game.isFullyInstalled && model.activity == nil {
                Button {
                    model.launch(game)
                } label: {
                    Image(systemName: "play.fill").font(.title3).frame(width: 30, height: 30)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .help("Spielen")
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct GameActions: View {
    @Environment(AppModel.self) private var model
    let game: SteamGame

    var body: some View {
        switch model.sessions[game.id] {
        case .running:
            Button("Beenden", systemImage: "stop.fill") { Task { await model.stop(game) } }
        case .preparing:
            Button("Start abbrechen", systemImage: "xmark") { model.cancelLaunch(game) }
        case nil:
            Button("Spielen", systemImage: "play.fill") { model.launch(game) }
                .disabled(!game.isFullyInstalled || model.activity != nil)
        }
        Divider()
        Button("Details", systemImage: "info.circle") { model.selectedGameID = game.id }
        Button("Im Finder zeigen", systemImage: "folder") { model.reveal(game.installFolder) }
        if let url = game.storeURL {
            Link(destination: url) { Label("Im Steam Store ansehen", systemImage: "safari") }
        }
        if let bottle = model.bottle(for: game) {
            Button("Bottle-Einstellungen …", systemImage: "slider.horizontal.3") { model.bottleSettingsTarget = bottle }
        }
    }
}

struct PosterPlaceholder: View {
    let name: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.55), .purple.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.75))
                Text(name)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
    }
}
