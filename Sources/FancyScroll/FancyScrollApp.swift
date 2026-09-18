import SwiftUI

@main
struct FancyScrollApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = Settings.shared

    var body: some Scene {
        MenuBarExtra {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(ScrollMonitor.shared)
        } label: {
            Image(systemName: settings.enabled ? "hand.tap.fill" : "hand.tap")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only; no Dock icon even when launched from a bare binary without Info.plist.
        NSApp.setActivationPolicy(.accessory)
        ScrollMonitor.shared.start()
    }
}
