import SwiftUI

/// UserDefaults keys, kept in one place so the controller and the settings UI
/// agree on names.
enum SettingsKey {
    static let selfTimer = "selfTimer"        // Int seconds: 0 / 3 / 10
    static let showGrid = "showGrid"          // Bool
    static let mirror = "mirror"              // Bool (default preview mirroring)
    static let shutterSound = "shutterSound"  // Bool
    static let videoQuality = "videoQuality"  // "high" | "medium" | "photo"
    static let photoFormat = "photoFormat"    // "jpeg" | "heif"
    static let photoDir = "photoDir"          // custom save path or ""
    static let videoDir = "videoDir"          // custom save path or ""
    static let aspectRatio = "aspectRatio"    // AspectRatio rawValue

    /// Register sane defaults once at launch.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            selfTimer: 0,
            showGrid: false,
            mirror: true,
            shutterSound: true,
            videoQuality: "high",
            photoFormat: "jpeg",
            photoDir: "",
            videoDir: "",
            aspectRatio: AspectRatio.full.rawValue,
        ])
    }
}

/// Standard macOS preferences window (⌘,) with General / Capture / About tabs.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            CaptureSettings()
                .tabItem { Label("Capture", systemImage: "camera.aperture") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
        .padding(20)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.selfTimer) private var selfTimer = 0
    @AppStorage(SettingsKey.showGrid) private var showGrid = false
    @AppStorage(SettingsKey.mirror) private var mirror = true
    @AppStorage(SettingsKey.shutterSound) private var shutterSound = true

    var body: some View {
        Form {
            Picker("Self-timer:", selection: $selfTimer) {
                Text("Off").tag(0)
                Text("3 seconds").tag(3)
                Text("10 seconds").tag(10)
            }
            Toggle("Show rule-of-thirds grid", isOn: $showGrid)
            Toggle("Mirror preview", isOn: $mirror)
            Toggle("Play shutter sound", isOn: $shutterSound)
        }
        .formStyle(.grouped)
    }
}

private struct CaptureSettings: View {
    @AppStorage(SettingsKey.videoQuality) private var videoQuality = "high"
    @AppStorage(SettingsKey.photoFormat) private var photoFormat = "jpeg"
    @AppStorage(SettingsKey.photoDir) private var photoDir = ""
    @AppStorage(SettingsKey.videoDir) private var videoDir = ""

    var body: some View {
        Form {
            Picker("Video quality:", selection: $videoQuality) {
                Text("High").tag("high")
                Text("Medium").tag("medium")
                Text("Photo (max still)").tag("photo")
            }
            Picker("Photo format:", selection: $photoFormat) {
                Text("JPEG").tag("jpeg")
                Text("HEIF (smaller)").tag("heif")
            }
            LabeledContent("Photos folder:") {
                FolderPicker(path: $photoDir, fallback: "Pictures")
            }
            LabeledContent("Videos folder:") {
                FolderPicker(path: $videoDir, fallback: "Movies")
            }
            Text("Quality and folder changes apply to the next launch or capture.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// A folder path field with a Choose… button and a reset to the system default.
private struct FolderPicker: View {
    @Binding var path: String
    let fallback: String

    var body: some View {
        HStack(spacing: 8) {
            Text(path.isEmpty ? "~/\(fallback) (default)" : (path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
            Spacer()
            if !path.isEmpty {
                Button("Reset") { path = "" }.controlSize(.small)
            }
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url { path = url.path }
            }
            .controlSize(.small)
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill").font(.system(size: 46)).foregroundStyle(Theme.accent)
            Text("Camera").font(.title2.bold())
            Text("Version 1.2").foregroundStyle(.secondary)
            Text("A lightweight, iOS-style camera for macOS.\nZoom and aspect ratio are digital (centered crops) because macOS doesn't expose device zoom — every other control appears only when your camera reports support for it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
