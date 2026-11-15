import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApp.activate()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        PlaytimeTracker.shared.flushAllActiveSessions()
    }
}
