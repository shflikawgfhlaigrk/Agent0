import SwiftUI
import AppKit

// SPM executable GUI apps need the activation policy nudged so the window
// comes to the front. Without this the process runs but stays background-only.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct Agent0GraphApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("Agent 0 · Living Graph") {
            ContentView()
                .frame(minWidth: 960, minHeight: 680)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
