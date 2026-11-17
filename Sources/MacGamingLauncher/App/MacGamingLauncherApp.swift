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

    func applicationWillTerminate(_ notification: Notification) {
        model?.applicationWillTerminate()
    }
}
