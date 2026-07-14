import SwiftUI
import AVFoundation

/// Compact live preview shown from the menu bar — a quick "check my hair"
/// glance without launching the full camera window.
struct MenuBarView: View {
    @ObservedObject var camera: CameraController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if camera.authorization == .authorized {
                    CameraPreview(session: camera.session, mirrored: camera.mirrored)
                        .frame(width: 300, height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(.black)
                        .frame(width: 300, height: 190)
                        .overlay(Image(systemName: "camera.fill").font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.4)))
                }
            }

            HStack(spacing: 10) {
                Button {
                    camera.setMode(.photo); camera.trigger()
                } label: {
                    Label("Snapshot", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .disabled(camera.authorization != .authorized)

                Button {
                    openWindow(id: "Camera")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .buttonStyle(.bordered)

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 328)
        .onAppear { camera.start() }
    }
}
