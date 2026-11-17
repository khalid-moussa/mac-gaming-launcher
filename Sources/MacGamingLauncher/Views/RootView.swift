import LauncherCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var controllers

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                detail
                    .navigationDestination(item: $model.selectedGameID) { id in
                        // Looked up on every render, so install/update progress shows up in the open detail.
                        GameDetailContainer(gameID: id)
                    }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Spiele durchsuchen")
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            activityBanner.animation(.snappy, value: model.activity)
        }
        .sheet(item: $model.bottleSettingsTarget) { bottle in
            BottleSettingsView(bottle: bottle)
        }
        .alert("Fehler", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            await model.refresh()
            await model.checkForRuntimeUpdate()
        }
        .task { await model.monitor() }
    }

    @ViewBuilder private var detail: some View {
        if !model.hasLoaded {
            ProgressView("Bibliothek wird geladen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.isSetupComplete && model.games.isEmpty {
            SetupView()
        } else {
            LibraryView()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let controller = controllers.controllers.first {
                Label {
                    Text(controller.name)
                } icon: {
                    Image(systemName: controller.symbol)
                }
                .labelStyle(.titleAndIcon)
                .font(.callout)
                .help([controller.name, controller.batteryText].compactMap { $0 }.joined(separator: " · "))
            }
            if let bottle = model.primaryBottle, model.steamInstalled.contains(bottle.id) {
                Button {
                    Task { await model.openSteam(in: bottle) }
                } label: {
                    Label("Steam", systemImage: model.steamRunning.contains(bottle.id) ? "circle.fill" : "circle")
                }
                .help(model.steamRunning.contains(bottle.id) ? "Steam läuft – Fenster anzeigen" : "Steam starten")
                .accessibilityValue(model.steamRunning.contains(bottle.id) ? "läuft" : "beendet")
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
            .help("Bibliothek neu einlesen (⌘R)")
        }
    }

    @ViewBuilder private var activityBanner: some View {
        if let activity = model.activity {
            HStack(spacing: 14) {
                if let progress = activity.progress {
                    ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.callout.weight(.semibold))
                    if let detail = activity.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let progress = activity.progress {
                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct GameDetailContainer: View {
    @Environment(AppModel.self) private var model
    let gameID: SteamGame.ID

    var body: some View {
        if let game = model.games.first(where: { $0.id == gameID }) {
            GameDetailView(game: game)
        }
    }
}
