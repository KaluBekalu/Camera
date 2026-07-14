import SwiftUI

@main
struct CameraApp: App {
    // A single shared engine drives the main window, the menu-bar preview,
    // and reflects live control state everywhere.
    @StateObject private var camera = CameraController()

    init() { SettingsKey.registerDefaults() }

    var body: some Scene {
        WindowGroup("Camera", id: "Camera") {
            ContentView(camera: camera)
        }
        .windowResizability(.contentSize)

        // Hand Mirror-style quick check from the menu bar.
        MenuBarExtra("Camera", systemImage: "camera.fill") {
            MenuBarView(camera: camera)
        }
        .menuBarExtraStyle(.window)

        // Standard ⌘, preferences window.
        Settings {
            SettingsView()
        }
    }
}
