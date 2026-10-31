import SwiftUI

public struct SidebarView: View {
    @Bindable var state: AppState

    public var body: some View {
        List {
            Section("Bibliothek") {
                ForEach(LibraryFilter.allCases) { filter in
                    Button(action: {
                        state.selectedFilter = filter
                        state.selectedBottle = nil
                    }) {
                        HStack {
                            Label(filter.rawValue, systemImage: filter.icon)
                            Spacer()
                            if filter == .all || filter == .installed {
                                Text("\(state.games.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        state.selectedFilter == filter && state.selectedBottle == nil
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }

            Section("Bottles & Umgebungen") {
                ForEach(state.bottles) { bottle in
                    Button(action: {
                        state.selectedBottle = bottle
                    }) {
                        HStack {
                            Image(systemName: "cube.box.fill")
                                .foregroundColor(bottle.hasSteamInstalled ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bottle.name)
                                    .font(.body)
                                if bottle.hasSteamInstalled {
                                    Text("Steam Bottle")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if bottle.hasSteamInstalled {
                                let count = state.games.filter { $0.bottleName == bottle.name }.count
                                Text("\(count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        state.selectedBottle?.name == bottle.name
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                }
            }

            if !state.engines.isEmpty {
                Section("Grafik-Engine") {
                    ForEach(state.engines) { engine in
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.name)
                                    .font(.caption.bold())
                                HStack(spacing: 4) {
                                    if engine.hasD3DMetal {
                                        Text("D3DMetal 4")
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                    if engine.hasMSync {
                                        Text("MSync")
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.2))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()
                HStack {
                    Button(action: { state.refresh() }) {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    if let selectedBottle = state.selectedBottle ?? state.bottles.first(where: { $0.hasSteamInstalled }),
                       let engine = state.selectedEngine ?? state.engines.first {
                        Button(action: {
                            try? GameRunner.shared.launchSteamClient(bottle: selectedBottle, engine: engine)
                        }) {
                            Text("Steam öffnen")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
