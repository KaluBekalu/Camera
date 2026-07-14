import SwiftUI
import AVFoundation

/// The main camera window — a full-bleed live preview with floating,
/// iOS-style glass controls that adapt to what the active camera supports.
struct ContentView: View {
    @ObservedObject var camera: CameraController

    @AppStorage(SettingsKey.showGrid) private var showGrid = false
    @AppStorage(SettingsKey.mirror) private var mirrorSetting = true
    @AppStorage(SettingsKey.selfTimer) private var selfTimer = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.authorization {
            case .authorized: cameraSurface
            case .denied, .restricted: permissionDenied
            default: ProgressView().controlSize(.large).tint(.white)
            }

            // Capture flash.
            if camera.flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .frame(minWidth: 560, minHeight: 680)
        .animation(.easeOut(duration: 0.12), value: camera.flash)
        .onAppear {
            camera.mirrored = mirrorSetting
            camera.start()
        }
        .onChange(of: mirrorSetting) { _, newValue in camera.mirrored = newValue }
    }

    // MARK: Authorized

    private var cameraSurface: some View {
        ZStack {
            previewLayer
            controlsLayer
            countdownLayer
        }
    }

    private var previewLayer: some View {
        GeometryReader { geo in
            CameraPreview(session: camera.session, mirrored: camera.mirrored)
                .overlay { if showGrid { GridOverlay() } }
                .overlay(focusReticle)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let p = CGPoint(x: value.location.x / geo.size.width,
                                        y: value.location.y / geo.size.height)
                        camera.focus(atNormalizedPoint: p)
                    }
                )
                .ignoresSafeArea()
        }
    }

    @ViewBuilder private var focusReticle: some View {
        if let point = camera.focusPoint {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Theme.accent, lineWidth: 1.5)
                    .frame(width: 68, height: 68)
                    .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: camera.focusPoint)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Floating controls

    private var controlsLayer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                deviceSwitcher
                Spacer()
                controlColumn
            }
            .padding(16)

            Spacer()

            if camera.isRecording { recordingBadge }
            else if let status = camera.statusMessage { GlassBadge(text: status) }

            bottomBar
        }
    }

    private var deviceSwitcher: some View {
        Group {
            if !camera.devices.isEmpty {
                Menu {
                    ForEach(camera.devices) { dev in
                        Button {
                            camera.selectedDeviceID = dev.id
                        } label: {
                            Label(dev.name, systemImage: dev.isContinuity ? "iphone" : "camera")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: currentIsContinuity ? "iphone" : "camera")
                        Text(currentDeviceName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var currentDeviceName: String {
        camera.devices.first { $0.id == camera.selectedDeviceID }?.name ?? "Camera"
    }
    private var currentIsContinuity: Bool {
        camera.devices.first { $0.id == camera.selectedDeviceID }?.isContinuity ?? false
    }

    /// The adaptive vertical stack of control buttons on the right.
    private var controlColumn: some View {
        VStack(spacing: 10) {
            // Self-timer cycles Off → 3s → 10s.
            GlassTimerButton(seconds: $selfTimer)

            GlassCircleButton(systemImage: showGrid ? "grid" : "grid",
                              active: showGrid) { showGrid.toggle() }

            if camera.capabilities.canMirror {
                GlassCircleButton(systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                                  active: camera.mirrored) {
                    camera.mirrored.toggle(); mirrorSetting = camera.mirrored
                }
            }
            if camera.capabilities.canLockExposure {
                GlassCircleButton(systemImage: camera.exposureLocked ? "sun.max.fill" : "sun.max",
                                  active: camera.exposureLocked) { camera.toggleExposureLock() }
            }
            if camera.capabilities.canLockFocus {
                GlassCircleButton(systemImage: camera.focusLocked ? "camera.metering.spot" : "camera.metering.center.weighted",
                                  active: camera.focusLocked) { camera.toggleFocusLock() }
            }
            if camera.capabilities.canLockWhiteBalance {
                GlassCircleButton(systemImage: "drop.fill", active: camera.whiteBalanceLocked) {
                    camera.toggleWhiteBalanceLock()
                }
            }
            if camera.capabilities.canCenterStage {
                GlassCircleButton(systemImage: "person.crop.rectangle", active: camera.centerStageOn) {
                    camera.toggleCenterStage()
                }
            }
            if camera.capabilities.canReact {
                reactionsMenu
            }
        }
    }

    private var reactionsMenu: some View {
        Menu {
            ForEach(camera.capabilities.reactionTypes, id: \.self) { r in
                Button(reactionLabel(r)) { camera.performReaction(r) }
            }
        } label: {
            Image(systemName: "hands.sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.controlSize, height: Theme.controlSize)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func reactionLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "AVCaptureReactionType", with: "")
           .replacingOccurrences(of: "reactionType", with: "")
           .capitalized
    }

    private var recordingBadge: some View {
        GlassBadge(text: timeString(camera.recordingSeconds), systemImage: "record.circle.fill",
                   tint: Theme.recording)
            .transition(.opacity)
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            modePicker
            HStack {
                thumbnail
                Spacer()
                shutterButton
                Spacer()
                settingsButton
            }
            .padding(.horizontal, 44)
        }
        .padding(.vertical, 22)
        .background(
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(CaptureMode.allCases) { m in
                Text(m.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(camera.mode == m ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background {
                        if camera.mode == m {
                            Capsule().fill(Theme.accent)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { camera.setMode(m) }
                    }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .opacity(camera.isRecording ? 0.4 : 1)
    }

    private var shutterButton: some View {
        Button(action: camera.trigger) {
            ZStack {
                Circle().stroke(.white, lineWidth: 4).frame(width: 74, height: 74)
                if camera.mode == .video {
                    RoundedRectangle(cornerRadius: camera.isRecording ? 7 : 29)
                        .fill(Theme.recording)
                        .frame(width: camera.isRecording ? 30 : 58,
                               height: camera.isRecording ? 30 : 58)
                } else {
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: camera.isRecording)
            .animation(.easeInOut(duration: 0.15), value: camera.mode)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.space, modifiers: [])
    }

    private var thumbnail: some View {
        Group {
            if let url = camera.lastCapture, let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.5)))
                    .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .help("Reveal last capture in Finder")
            } else {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)))
            }
        }
    }

    private var settingsButton: some View {
        SettingsLink {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help("Settings")
    }

    // MARK: Countdown

    @ViewBuilder private var countdownLayer: some View {
        if let n = camera.countdown {
            Text("\(n)")
                .font(.system(size: 120, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 12)
                .transition(.scale.combined(with: .opacity))
                .id(n)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: camera.countdown)
        }
    }

    // MARK: Denied

    private var permissionDenied: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash.fill").font(.system(size: 44)).foregroundStyle(.white)
            Text("Camera access is off").font(.headline).foregroundStyle(.white)
            Text("Enable it in System Settings › Privacy & Security › Camera.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}

/// A glass control that cycles the self-timer and shows the current value.
struct GlassTimerButton: View {
    @Binding var seconds: Int
    @State private var hovering = false

    private var next: Int { seconds == 0 ? 3 : (seconds == 3 ? 10 : 0) }

    var body: some View {
        Button { seconds = next } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(.white.opacity(seconds == 0 ? 0.12 : 0.0))
                Circle().strokeBorder(Theme.accent.opacity(seconds == 0 ? 0.0 : 0.9), lineWidth: 1.5)
                if seconds == 0 {
                    Image(systemName: "timer").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(seconds)s").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: Theme.controlSize, height: Theme.controlSize)
            .scaleEffect(hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .help("Self-timer")
    }
}
