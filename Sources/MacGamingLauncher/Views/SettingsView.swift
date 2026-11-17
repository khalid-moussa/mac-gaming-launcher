import LauncherCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var checking = false
    @State private var checkResult: String?

    var body: some View {
        Form {
            Section("Wine-Runtime") {
                LabeledContent("Installiert", value: model.runtimeVersion ?? "Nein")
                if let release = model.availableRuntime {
                    LabeledContent("Verfügbar", value: "\(release.version) (DXMT \(release.dxmtVersion ?? "–"), DXVK \(release.dxvkVersion ?? "–"))")
                }
                HStack {
                    Button(model.runtimeVersion == nil ? "Installieren" : model.availableRuntime != nil ? "Aktualisieren" : "Neu installieren") {
                        Task { await model.installRuntime() }
                    }
                    .disabled(model.activity != nil)
                    Button("Nach Updates suchen") {
                        Task {
                            checking = true
                            let checked = await model.checkForRuntimeUpdate()
                            checking = false
                            if !checked {
                                checkResult = "Prüfung fehlgeschlagen"
                            } else if model.availableRuntime == nil, model.runtimeVersion != nil {
                                checkResult = "Aktuell"
                            } else {
                                checkResult = nil
                            }
                        }
                    }
                    .disabled(model.activity != nil || checking)
                    if checking {
                        ProgressView().controlSize(.small)
                    } else if let checkResult {
                        Text(checkResult).foregroundStyle(.secondary)
                    }
                }
                Text("Quelle: frankea/Whisky (Wine 11 auf CrossOver-Basis, LGPL). Läuft über Rosetta 2.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if let info = model.d3dMetalImported {
                    LabeledContent("D3DMetal", value: info.version)
                    if info.isMetal4 {
                        Label("Game Porting Toolkit 4 · Metal 4 aktiv", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    Button("Entfernen", role: .destructive) { Task { await model.removeD3DMetal() } }
                        .disabled(model.activity != nil)
                } else {
                    Text("Apples D3DMetal übersetzt DirectX 11/12 nach Metal und ist für die meisten DX12-Spiele nötig. Apple erlaubt keine Weitergabe – lade das Game Porting Toolkit (kostenloses Entwicklerkonto) und importiere die .dmg.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("GPTK-Image (.dmg) importieren …") { importing = true }
                            .disabled(model.runtimeVersion == nil || model.activity != nil)
                        Link("Download bei Apple", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
                    }
                }
            } header: {
                Text("Apple Game Porting Toolkit")
            }

            Section("CrossOver") {
                if let engine = model.crossOverEngine {
                    LabeledContent("Erkannt", value: engine.displayName)
                    Text("CrossOver-Bottles erscheinen automatisch in der Seitenleiste und werden mit CrossOver gestartet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Nicht installiert (optional). Falls vorhanden, werden CrossOver-Bottles mitgenutzt.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Daten") {
                Button("Launcher-Ordner im Finder zeigen") { model.reveal(model.paths.root) }
                Button("Logs im Finder zeigen") { NSWorkspace.shared.open(model.paths.logs) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.diskImage, .folder, .application]) { result in
            if case .success(let url) = result {
                Task { await model.importD3DMetal(from: url) }
            }
        }
        .task { await model.checkForRuntimeUpdate() }
    }
}
