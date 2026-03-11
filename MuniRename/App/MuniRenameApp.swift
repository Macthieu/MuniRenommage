import SwiftUI

@main
struct MuniRenameApp: App {
    @StateObject private var presetStore = RenamePresetStore()

    var body: some Scene {
        // Fenêtre principale (renommeur)
        WindowGroup {
            ContentView()
                .environmentObject(presetStore)
        }

        // Fenêtre de gestion des presets (ouvrable via bouton ou menu)
        Window("Presets", id: "presets") {
            PresetsManagerView()
                .environmentObject(presetStore)
                .frame(minWidth: 920, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands { PresetCommands() }
    }
}

struct PresetCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Presets") {
            Button("Gestion des presets…") {
                openWindow(id: "presets")
            }
            .keyboardShortcut(",", modifiers: [.command, .shift]) // Cmd+Shift+,
        }
    }
}
