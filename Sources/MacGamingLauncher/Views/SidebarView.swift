import LauncherCore
import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var exeTarget: Bottle?
    @State private var showExeImporter = false
    @State private var bottleToDelete: Bottle?
    @State private var bottleToKill: Bottle?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Bibliothek") {
                ForEach(LibraryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.icon)
                        .badge(count(for: filter))
                        .tag(SidebarItem.library(filter))
                }
            }

            if !model.bottles.isEmpty || model.macSteamInstalled {
                Section("Bottles") {
                    ForEach(model.bottles) { bottle in
                        BottleRow(bottle: bottle)
                            .tag(SidebarItem.bottle(bottle.id))
                            .contextMenu { menu(for: bottle) }
                    }
                    if model.macSteamInstalled {
                        Label("Steam (macOS)", systemImage: "apple.logo")
                            .badge(model.games.filter(model.isMacSteamGame).count)
                            .tag(SidebarItem.macSteam)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { accountFooter }
        // The target is kept separately: SwiftUI may reset `isPresented` before calling the completion.
        .fileImporter(isPresented: $showExeImporter, allowedContentTypes: [.exe, .msi]) { result in
            if case .success(let url) = result, let bottle = exeTarget {
                Task { await model.run(executable: url, in: bottle) }
            }
            exeTarget = nil
        }
        .confirmationDialog(
            "„\(bottleToDelete?.name ?? "")“ löschen?",
            isPresented: Binding(get: { bottleToDelete != nil }, set: { if !$0 { bottleToDelete = nil } }),
            presenting: bottleToDelete
        ) { bottle in
            Button("Löschen", role: .destructive) { Task { await model.deleteBottle(bottle) } }
        } message: { _ in
            Text("Das Bottle mit allen darin installierten Spielen und Spielständen, die nicht in der Steam Cloud liegen, wird in den Papierkorb verschoben.")
        }
        .confirmationDialog(
            "Alle Prozesse in „\(bottleToKill?.name ?? "")“ beenden?",
            isPresented: Binding(get: { bottleToKill != nil }, set: { if !$0 { bottleToKill = nil } }),
            presenting: bottleToKill
        ) { bottle in
            Button("Beenden", role: .destructive) { Task { await model.killBottle(bottle) } }
        } message: { _ in
            Text("Laufende Spiele und Steam werden sofort beendet. Nicht gespeicherter Fortschritt geht verloren.")
        }
    }

    private func count(for filter: LibraryFilter) -> Int {
        switch filter {
        case .all: model.games.count
        case .installed: model.games.filter(\.isFullyInstalled).count
        case .recent: model.games.filter { model.lastPlayed(for: $0) != nil }.count
        }
    }

    @ViewBuilder private func menu(for bottle: Bottle) -> some View {
        let steamInstalled = model.steamInstalled.contains(bottle.id)
        if steamInstalled {
            Button("Steam öffnen", systemImage: "play.circle") { Task { await model.openSteam(in: bottle) } }
            if model.steamRunning.contains(bottle.id) {
                Button("Steam beenden", systemImage: "stop.circle") { Task { await model.quitSteam(in: bottle) } }
            }
        } else {
            Button("Steam installieren", systemImage: "arrow.down.circle") { Task { await model.installSteam(in: bottle) } }
        }
        Divider()
        Button("Einstellungen …", systemImage: "slider.horizontal.3") { model.bottleSettingsTarget = bottle }
        Button("Windows-Programm ausführen …", systemImage: "app.badge") {
            exeTarget = bottle
            showExeImporter = true
        }
        Menu("Werkzeuge", systemImage: "wrench.and.screwdriver") {
            Button("Wine-Konfiguration (winecfg)") { Task { await model.runTool("winecfg", in: bottle) } }
            Button("Registry-Editor") { Task { await model.runTool("regedit", in: bottle) } }
            Button("Task-Manager") { Task { await model.runTool("taskmgr", in: bottle) } }
        }
        Divider()
        Button("Im Finder zeigen", systemImage: "folder") { model.reveal(bottle.url) }
        Button("Log anzeigen", systemImage: "doc.text.magnifyingglass") { model.revealLog(for: bottle) }
        Button("Alle Prozesse beenden …", systemImage: "xmark.octagon") { bottleToKill = bottle }
        if bottle.owner == .launcher {
            Divider()
            Button("Bottle löschen …", systemImage: "trash", role: .destructive) { bottleToDelete = bottle }
        }
    }

    @ViewBuilder private var accountFooter: some View {
        if let account = model.primaryAccount {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.personaName).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("Steam-Konto verbunden").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = account.profileURL {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        .help("Steam-Profil öffnen")
                        .accessibilityLabel("Steam-Profil öffnen")
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
            .padding(10)
        }
    }
}

private struct BottleRow: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: bottle.owner == .crossOver ? "shippingbox.fill" : "cube.fill")
                .foregroundStyle(model.engine(for: bottle) == nil ? Color.secondary : Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(bottle.name)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.steamRunning.contains(bottle.id) {
                Circle().fill(.green).frame(width: 7, height: 7).help("Steam läuft")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(model.steamRunning.contains(bottle.id) ? "Steam läuft" : "")
    }

    private var subtitle: String {
        if model.engine(for: bottle) == nil {
            return bottle.owner == .crossOver ? "CrossOver fehlt" : "Runtime fehlt"
        }
        if let account = model.accounts[bottle.id] { return account.personaName }
        if model.steamInstalled.contains(bottle.id) { return "Steam – nicht angemeldet" }
        return bottle.owner == .crossOver ? "CrossOver" : "Ohne Steam"
    }
}

extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
    static let msi = UTType(filenameExtension: "msi") ?? .data
}
