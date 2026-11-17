import LauncherCore
import SwiftUI

/// Step-by-step assistant: Rosetta → runtime → bottle → Steam → login.
struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Windows-Spiele auf dem Mac")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Der Assistent richtet eine Windows-Umgebung mit Steam ein. Spiele laufen über Wine mit Übersetzung von DirectX nach Metal (DXMT, DXVK und optional Apples D3DMetal aus dem Game Porting Toolkit 4).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 12) {
                    ForEach(SetupStep.allCases) { step in
                        SetupStepRow(step: step)
                    }
                }
                Text("Hinweis: Spiele mit Kernel-Anti-Cheat (z. B. Valorant, Fortnite, Call of Duty) laufen unter Wine nicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Einrichtung")
    }
}

/// Compact reminder shown above the library while setup is incomplete.
struct SetupBanner: View {
    @Environment(AppModel.self) private var model
    /// Users who only play through the native macOS Steam client may not want a Windows setup.
    @AppStorage("setupBannerHidden") private var hidden = false

    var body: some View {
        if let step = model.currentSetupStep, !hidden {
            SetupStepRow(step: step)
                .overlay(alignment: .topTrailing) {
                    Button("Ausblenden", systemImage: "xmark") { hidden = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Einrichtungshinweis ausblenden")
                        .padding(10)
                }
        }
    }
}

struct SetupStepRow: View {
    @Environment(AppModel.self) private var model
    let step: SetupStep

    var body: some View {
        let done = model.isDone(step)
        let current = model.currentSetupStep == step
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : current ? "\(step.rawValue + 1).circle.fill" : "\(step.rawValue + 1).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : current ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if current && model.activity == nil {
                    action.padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .opacity(done || current ? 1 : 0.55)
        .background(current ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: .rect(cornerRadius: 16))
    }

    private var title: String {
        switch step {
        case .rosetta: "Rosetta 2"
        case .runtime: "Wine-Runtime"
        case .bottle: "Windows-Umgebung (Bottle)"
        case .steam: "Steam für Windows"
        case .login: "Steam-Konto verbinden"
        }
    }

    private var description: String {
        switch step {
        case .rosetta:
            return "Übersetzt Windows-x86-Code für Apple Silicon. Wird einmalig von macOS installiert."
        case .runtime:
            if let version = model.runtimeVersion { return "Installiert: \(version)" }
            if let crossOver = model.crossOverEngine { return "\(crossOver.displayName) erkannt." }
            return "Wine 11 (CrossOver-Basis) mit DXMT und DXVK, ca. 460 MB Download."
        case .bottle:
            return "Ein 64-Bit-Windows-10-Präfix, in dem Steam und deine Spiele laufen."
        case .steam:
            return "Der offizielle Steam-Client wird heruntergeladen und still installiert."
        case .login:
            return "Steam öffnet sich – melde dich dort mit deinem Konto an (inkl. Steam Guard). Beim ersten Start aktualisiert sich Steam selbst."
        }
    }

    @ViewBuilder private var action: some View {
        switch step {
        case .rosetta:
            Button("Rosetta installieren") { Task { await model.installRosetta() } }
                .buttonStyle(.glassProminent)
        case .runtime:
            Button("Runtime laden & installieren") { Task { await model.installRuntime() } }
                .buttonStyle(.glassProminent)
        case .bottle:
            Button("Bottle „Steam“ erstellen") { Task { await model.createSteamBottle() } }
                .buttonStyle(.glassProminent)
        case .steam:
            if let bottle = model.bottles.first(where: { $0.owner == .launcher }) ?? model.bottles.first {
                Button("Steam installieren") { Task { await model.installSteam(in: bottle) } }
                    .buttonStyle(.glassProminent)
            }
        case .login:
            if let bottle = model.primaryBottle {
                Button("Steam öffnen & anmelden") { Task { await model.openSteam(in: bottle) } }
                    .buttonStyle(.glassProminent)
            }
        }
    }
}
