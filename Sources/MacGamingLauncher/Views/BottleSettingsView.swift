import LauncherCore
import SwiftUI

struct BottleSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var bottle: Bottle
    @State private var steamArguments: String

    init(bottle: Bottle) {
        _bottle = State(initialValue: bottle)
        _steamArguments = State(initialValue: bottle.settings.extraSteamArguments.joined(separator: " "))
    }

    private var engine: Engine? { model.engine(for: bottle) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grafik-Backend", selection: $bottle.settings.graphics) {
                        ForEach(engine?.availableBackends ?? GraphicsBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    Text(bottle.settings.graphics.summary).font(.caption).foregroundStyle(.secondary)
                    if bottle.settings.graphics == .automatic, let engine, engine.kind == .managed {
                        LabeledContent("Aktiv", value: GraphicsPlan.gameBackend(for: .automatic, engine: engine).displayName)
                    }
                    if engine?.kind == .managed, engine?.d3dMetal == nil {
                        Text("D3DMetal (für DirectX-12-Spiele) wird verfügbar, sobald du das Game Porting Toolkit in den Einstellungen importierst.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Grafik")
                } footer: {
                    Text("Steam selbst läuft immer über DXVK – das ist für die Steam-Oberfläche nötig.")
                }

                Section("Leistung") {
                    Toggle("MSync (Mach-Synchronisation)", isOn: $bottle.settings.msync)
                    Toggle("AVX/AVX2 über Rosetta melden", isOn: $bottle.settings.advertiseAVX)
                    Toggle("MetalFX-Upscaling (DLSS → MetalFX)", isOn: $bottle.settings.metalFX)
                        .disabled(engine?.d3dMetal == nil && engine?.kind != .crossOver)
                }

                Section("Anzeige") {
                    Toggle("Metal Performance HUD", isOn: $bottle.settings.metalHUD)
                    Toggle("Retina-Modus (volle Auflösung)", isOn: $bottle.settings.retina)
                        .disabled(bottle.owner == .crossOver)
                }

                if bottle.owner == .launcher {
                    Section("Erweitert") {
                        Picker("Windows-Version", selection: $bottle.settings.windowsVersion) {
                            Text("Windows 10").tag("win10")
                            Text("Windows 11").tag("win11")
                        }
                        TextField("Zusätzliche Steam-Argumente", text: $steamArguments, prompt: Text("z. B. -cef-disable-gpu"))
                    }
                }

                if model.steamRunning.contains(bottle.id) {
                    Section {
                        Label("Änderungen wirken beim nächsten Start von Steam.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Einstellungen – \(bottle.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                if model.steamRunning.contains(bottle.id) {
                    ToolbarItem {
                        Button("Sichern & Steam neu starten") { save(restart: true) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save(restart: false) }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }

    private func save(restart: Bool) {
        let windowsVersionChanged = model.bottle(id: bottle.id)?.settings.windowsVersion != bottle.settings.windowsVersion
        bottle.settings.extraSteamArguments = steamArguments.split(separator: " ").map(String.init)
        model.save(bottle)
        let saved = bottle
        Task {
            if windowsVersionChanged { await model.applyWindowsVersion(in: saved) }
            if restart { await model.restartSteam(in: saved) }
        }
        dismiss()
    }
}
