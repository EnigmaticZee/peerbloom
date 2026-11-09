import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched with `swift run`, which doesn't start as a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { store?.saveBeforeQuit() }
    }

    // Keep running in the menu bar when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PeerbloomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore.shared

    var body: some Scene {
        Window("Peerbloom", id: "main") {
            MainWindow()
                .environment(store)
                .themed()
                .onAppear { delegate.store = store }
                .onOpenURL { store.handleIncoming(url: $0) }
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            FileCommands(store: store)
            TransferCommands(store: store)
        }

        Settings {
            SettingsView().environment(store).themed()
        }

        MenuBarExtra(isInserted: Binding(
            get: { store.preferences.showMenuBarIcon },
            set: { if store.preferences.showMenuBarIcon != $0 { store.preferences.showMenuBarIcon = $0 } }
        )) {
            MenuBarView().environment(store).themed()
        } label: {
            Label(Format.totalRate(store.totalDownloadRate), systemImage: "arrow.up.arrow.down")
                .labelStyle(.titleAndIcon)
        }
        .menuBarExtraStyle(.window)
    }

}

private struct FileCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Torrent File…") { store.chooseTorrentFile() }
                .keyboardShortcut("o")
            Button("Add Magnet Link…") { store.pendingAdd = .magnet(pasteboardMagnet ?? "") }
                .keyboardShortcut("u")
        }
    }

    private var pasteboardMagnet: String? {
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.lowercased().hasPrefix("magnet:") == true ? text : nil
    }
}

private struct TransferCommands: Commands {
    let store: AppStore

    var body: some Commands {
        CommandMenu("Transfers") {
            SelectionCommands(store: store)
            Divider()
            Button("Resume All") { store.resumeAll() }
            Button("Pause All") { store.pauseAll() }
            Divider()
            Button(store.altSpeedActive ? "Turn Off Slow Mode" : "Turn On Slow Mode") { store.toggleAltSpeed() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

private struct SelectionCommands: View {
    let store: AppStore

    var body: some View {
        let none = store.selection.isEmpty
        Button("Resume") { store.resume() }
            .keyboardShortcut("r")
            .disabled(none)
        Button("Pause") { store.pause() }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(none)
        Divider()
        Button("Show in Finder") { store.showInFinder() }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(none)
        Button("Copy Magnet Link") { store.copyMagnetLinks() }
            .disabled(none)
        Divider()
        Button("Remove…") { store.requestRemove() }
            .keyboardShortcut(.delete)
            .disabled(none)
    }
}
