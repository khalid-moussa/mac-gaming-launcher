import Foundation
import SwiftUI
import Observation
import AppKit

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Alle Spiele"
    case installed = "Installiert"
    case recent = "Zuletzt gespielt"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .all: return "gamecontroller"
        case .installed: return "arrow.down.circle"
        case .recent: return "clock"
        }
    }
}

@Observable
@MainActor
public final class AppState {
    public var games: [SteamGame] = []
    public var bottles: [Bottle] = []
    public var engines: [Engine] = []

    public var selectedBottle: Bottle? = nil
    public var selectedEngine: Engine? = nil
    public var selectedGame: SteamGame? = nil

    public var runningGameIDs: Set<String> = []
    public var searchQuery: String = ""
    public var selectedFilter: LibraryFilter = .all

    public var isLoading: Bool = false
    public var statusMessage: String? = nil

    public init() {
        refresh()
    }

    public var filteredGames: [SteamGame] {
        var result = games

        if let selectedBottle = selectedBottle {
            result = result.filter { $0.bottleName == selectedBottle.name }
        }

        switch selectedFilter {
        case .all, .installed:
            break
        case .recent:
            result = result.filter { $0.lastPlayed != nil }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        }

        if !searchQuery.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }

        return result
    }

    public func refresh() {
        isLoading = true
        statusMessage = "Erkenne Engines und Bottles..."

        Task.detached(priority: .userInitiated) {
            let detectedEngines = EngineService.shared.discoverEngines()
            let detectedBottles = BottleService.shared.discoverBottles()

            var allGames: [SteamGame] = []
            for bottle in detectedBottles {
                let bottleGames = SteamService.shared.scanGames(in: bottle)
                allGames.append(contentsOf: bottleGames)
            }
            let sortedGames = allGames.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })

            await MainActor.run {
                self.engines = detectedEngines
                self.selectedEngine = detectedEngines.first

                self.bottles = detectedBottles
                if self.selectedBottle == nil {
                    self.selectedBottle = detectedBottles.first(where: { $0.hasSteamInstalled }) ?? detectedBottles.first
                }

                self.games = sortedGames
                if self.selectedGame == nil {
                    self.selectedGame = sortedGames.first
                }

                self.isLoading = false
                self.statusMessage = nil
            }
        }
    }

    public func launchSteamClient(bottle: Bottle) {
        guard let engine = selectedEngine ?? engines.first else {
            statusMessage = "Keine Wine/GPTK Engine gefunden!"
            return
        }
        do {
            try GameRunner.shared.launchSteamClient(bottle: bottle, engine: engine)
        } catch {
            statusMessage = "Fehler beim Starten von Steam: \(error.localizedDescription)"
        }
    }

    public func launch(game: SteamGame, overrideHUD: Bool? = nil) {
        guard let engine = selectedEngine ?? engines.first else {
            statusMessage = "Keine Wine/GPTK Engine gefunden!"
            return
        }

        guard let bottle = bottles.first(where: { $0.name == game.bottleName }) ?? selectedBottle else {
            statusMessage = "Bottle '\(game.bottleName)' nicht gefunden!"
            return
        }

        runningGameIDs.insert(game.appId)

        do {
            try GameRunner.shared.launchGame(
                game: game,
                bottle: bottle,
                engine: engine,
                overrideHUD: overrideHUD
            ) { [weak self] in
                Task { @MainActor in
                    self?.runningGameIDs.remove(game.appId)
                }
            }
        } catch {
            runningGameIDs.remove(game.appId)
            statusMessage = "Fehler beim Starten: \(error.localizedDescription)"
        }
    }

    public func terminate(game: SteamGame) {
        GameRunner.shared.terminateGame(appId: game.appId)
        runningGameIDs.remove(game.appId)
    }

    public func updateBottle(_ updated: Bottle) {
        if let idx = bottles.firstIndex(where: { $0.name == updated.name }) {
            bottles[idx] = updated
            BottleService.shared.updateBottleConfiguration(bottle: updated)
        }
        if selectedBottle?.name == updated.name {
            selectedBottle = updated
        }
    }

    public func playtime(for game: SteamGame) -> String {
        PlaytimeTracker.shared.formattedPlaytime(appId: game.appId)
    }

    public func revealInFinder(bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([bottle.path])
    }

    public func revealInFinder(game: SteamGame) {
        let gameFolder = game.bottlePath.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common").appendingPathComponent(game.installDir)
        if FileManager.default.fileExists(atPath: gameFolder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([gameFolder])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([game.bottlePath])
        }
    }

    public func openSteamStore(game: SteamGame) {
        if let url = URL(string: "https://store.steampowered.com/app/\(game.appId)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func runCustomExecutable(in bottle: Bottle) {
        guard let engine = selectedEngine ?? engines.first else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.message = "Wähle eine Windows .exe-Datei zum Ausführen im Bottle '\(bottle.name)'"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try GameRunner.shared.launchCustomExecutable(exeURL: url, bottle: bottle, engine: engine)
            } catch {
                statusMessage = "Fehler: \(error.localizedDescription)"
            }
        }
    }

    public func openWineCfg(in bottle: Bottle) {
        guard let engine = selectedEngine ?? engines.first else { return }
        do {
            try GameRunner.shared.launchWineCfg(bottle: bottle, engine: engine)
        } catch {
            statusMessage = "Fehler: \(error.localizedDescription)"
        }
    }
}
