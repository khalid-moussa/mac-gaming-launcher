import Foundation
import SwiftUI
import Observation

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

        Task { @MainActor in
            self.engines = EngineService.shared.discoverEngines()
            self.selectedEngine = self.engines.first

            self.bottles = BottleService.shared.discoverBottles()
            if self.selectedBottle == nil {
                self.selectedBottle = self.bottles.first(where: { $0.hasSteamInstalled }) ?? self.bottles.first
            }

            var allGames: [SteamGame] = []
            for bottle in self.bottles {
                let bottleGames = SteamService.shared.scanGames(in: bottle)
                allGames.append(contentsOf: bottleGames)
            }

            self.games = allGames.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
            if self.selectedGame == nil {
                self.selectedGame = self.games.first
            }

            self.isLoading = false
            self.statusMessage = nil
        }
    }

    public func launch(game: SteamGame) {
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
            try GameRunner.shared.launchGame(game: game, bottle: bottle, engine: engine) { [weak self] in
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
}
