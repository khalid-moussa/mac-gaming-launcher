import AppKit
import LauncherCore
import SwiftUI

@main
struct MacGamingLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var controllers = ControllerMonitor()

    var body: some Scene {
        Window("Mac Gaming Launcher", id: "main") {
            RootView()
                .environment(model)
                .environment(controllers)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { appDelegate.model = model }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(after: .newItem) {
                Button("Bibliothek aktualisieren") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quitting mid-operation can leave a half-created bottle or a half-swapped runtime behind.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let activity = model?.activity else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "„\(activity.title.trimmingCharacters(in: CharacterSet(charactersIn: " …")))“ läuft noch."
        alert.informativeText = "Wenn du jetzt beendest, kann eine unvollständige Installation zurückbleiben."
        alert.addButton(withTitle: "Weiterlaufen lassen")
        alert.addButton(withTitle: "Trotzdem beenden")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.applicationWillTerminate()
    }
}
