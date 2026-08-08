import Agent0Core
import Darwin
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

    init() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--agent0-tick"), idx + 1 < args.count {
            do {
                let text = args[(idx + 1)...].joined(separator: " ")
                let brain = Agent0Brain(directory: Persist.dir.appendingPathComponent("core", isDirectory: true))
                let result = try brain.tick(observing: text, speaker: "cli")
                print(result.reply)
                Darwin.exit(0)
            } catch {
                fputs("agent0 tick failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
        if let idx = args.firstIndex(of: "--agent0-redirect"), idx + 2 < args.count {
            do {
                let source = args[idx + 1]
                let target = args[idx + 2]
                let reason = idx + 3 < args.count ? args[(idx + 3)...].joined(separator: " ") : "manual redirect"
                let brain = Agent0Brain(directory: Persist.dir.appendingPathComponent("core", isDirectory: true))
                let redirect = try brain.redirectRoute(source: source, target: target, reason: reason)
                print("redirected \(redirect.lawKey): \(redirect.reason)")
                Darwin.exit(0)
            } catch {
                fputs("agent0 redirect failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
        if let idx = args.firstIndex(of: "--agent0-suppress-concept"), idx + 1 < args.count {
            do {
                let concept = args[idx + 1]
                let reason = idx + 2 < args.count ? args[(idx + 2)...].joined(separator: " ") : "manual concept redirect"
                let brain = Agent0Brain(directory: Persist.dir.appendingPathComponent("core", isDirectory: true))
                let redirect = try brain.suppressConcept(concept, reason: reason)
                print("suppressed concept \(redirect.concept): \(redirect.reason)")
                Darwin.exit(0)
            } catch {
                fputs("agent0 suppress concept failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
        if args.contains("--agent0-state") {
            do {
                let brain = Agent0Brain(directory: Persist.dir.appendingPathComponent("core", isDirectory: true))
                let state = try brain.state()
                print("ticks=\(state.tick) concepts=\(state.concepts.count) laws=\(state.laws.count) scaffolds=\(state.scaffolds.count) redirectedConcepts=\(state.redirectedConcepts.count) redirectedRoutes=\(state.redirectedRoutes.count) tensions=\(state.unresolvedTensions.count) hash=\(state.ledgerHash)")
                Darwin.exit(0)
            } catch {
                fputs("agent0 state failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
    }

    var body: some Scene {
        WindowGroup("Agent 0 · Living Graph") {
            ContentView()
                .frame(minWidth: 960, minHeight: 680)
                .background(Color.black)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
