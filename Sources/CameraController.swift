import AVFoundation
import AppKit
import Combine
import CoreMedia
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Capture mode the UI is currently in.
enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case video = "Video"
    var id: String { rawValue }
}

/// A selectable camera (built-in, external, or iPhone via Continuity Camera).
struct CameraDevice: Identifiable, Hashable {
    let id: String          // AVCaptureDevice.uniqueID
    let name: String
    let isContinuity: Bool
}

/// Which controls the *currently active* device actually supports. Drives which
/// floating buttons the UI shows — a basic webcam exposes few of these, an
/// iPhone via Continuity Camera exposes Center Stage, reactions, and more.
struct DeviceCapabilities {
    var canLockExposure = false
    var canLockFocus = false
    var canFocusAtPoint = false
    var canLockWhiteBalance = false
    var canCenterStage = false
    var canMirror = false
    var canReact = false
    var reactionTypes: [String] = []   // AVCaptureReactionType raw values
    var maxZoom: CGFloat = 1
}

/// Owns the `AVCaptureSession` and drives photo/video capture plus the
/// macOS-supported hardware controls (exposure/focus/white-balance lock,
/// Center Stage, mirroring, reaction effects).
///
/// Published properties are touched only on the main thread; all session and
/// device mutation happens on `sessionQueue`.
final class CameraController: NSObject, ObservableObject {

    // MARK: Published UI state
    @Published private(set) var devices: [CameraDevice] = []
    @Published var selectedDeviceID: String? { didSet { if oldValue != selectedDeviceID { switchToSelectedDevice() } } }
    @Published private(set) var mode: CaptureMode = .photo
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds = 0
    @Published private(set) var authorization: AVAuthorizationStatus = .notDetermined
    @Published private(set) var lastCapture: URL?
    @Published private(set) var statusMessage: String?

    // Live control state
    @Published private(set) var capabilities = DeviceCapabilities()
    @Published private(set) var exposureLocked = false
    @Published private(set) var focusLocked = false
    @Published private(set) var whiteBalanceLocked = false
    @Published private(set) var centerStageOn = false
    @Published var mirrored = false { didSet { if oldValue != mirrored { applyMirroring() } } }
    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var sensorAspect: CGFloat = 16.0 / 9.0
    @Published var aspectRatio: AspectRatio = AspectRatio(
        rawValue: UserDefaults.standard.string(forKey: SettingsKey.aspectRatio) ?? "full") ?? .full {
        didSet {
            if oldValue != aspectRatio {
                UserDefaults.standard.set(aspectRatio.rawValue, forKey: SettingsKey.aspectRatio)
                showStatus(aspectRatio == .full ? "Full frame" : aspectRatio.rawValue)
            }
        }
    }

    // Transient UI cues
    @Published var flash = false           // white capture-flash overlay
    @Published var countdown: Int? = nil   // self-timer countdown number
    @Published var focusPoint: CGPoint? = nil // normalized tap location for reticle

    // Crop parameters captured at shutter time
    private var pendingZoom: CGFloat = 1
    private var pendingAspect: CGFloat?
    private let pendingCropLock = NSLock()
    private var centerStageObservation: NSKeyValueObservation?

    // MARK: AVFoundation
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.local.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var activeDevice: AVCaptureDevice?
    private var discovery: AVCaptureDevice.DiscoverySession?
    private var recordingTimer: Timer?
    private var reactionTypeMap: [String: AVCaptureReactionType] = [:]

    // MARK: Lifecycle

    func start() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.authorization = granted ? .authorized : .denied
                        if granted { self.configureAndRun() }
                    }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: Device discovery

    private func refreshDevices() {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external]
        if #available(macOS 14.0, *) {
            types.append(.continuityCamera)
            types.append(.deskViewCamera)
        }
        let disc = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified)
        self.discovery = disc

        let found = disc.devices.map { dev -> CameraDevice in
            var continuity = false
            if #available(macOS 14.0, *) {
                continuity = dev.deviceType == .continuityCamera || dev.deviceType == .deskViewCamera
            }
            return CameraDevice(id: dev.uniqueID, name: dev.localizedName, isContinuity: continuity)
        }
        DispatchQueue.main.async {
            self.devices = found
            if self.selectedDeviceID == nil { self.selectedDeviceID = found.first?.id }
        }
    }

    private func device(for id: String?) -> AVCaptureDevice? {
        guard let id else { return AVCaptureDevice.default(for: .video) }
        return discovery?.devices.first { $0.uniqueID == id } ?? AVCaptureDevice(uniqueID: id)
    }

    // MARK: Session configuration

    private func configureAndRun() {
        refreshDevices()
        // Take app control of Center Stage so we can toggle it programmatically.
        if #available(macOS 12.3, *) {
            AVCaptureDevice.centerStageControlMode = .app
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = self.preferredPreset()
            self.attachVideoInput()
            self.attachAudioInput()
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            self.applyMirroring()
            DispatchQueue.main.async {
                self.isRunning = self.session.isRunning
                self.publishCapabilities()
            }
        }
    }

    private func attachVideoInput() {
        if let existing = videoInput { session.removeInput(existing); videoInput = nil }
        guard let dev = device(for: selectedDeviceID),
              let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoInput = input
        activeDevice = dev
    }

    private func attachAudioInput() {
        guard audioInput == nil, let mic = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: mic),
              session.canAddInput(input) else { return }
        session.addInput(input)
        audioInput = input
    }

    private func switchToSelectedDevice() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.attachVideoInput()
            self.session.commitConfiguration()
            self.applyMirroring()
            DispatchQueue.main.async {
                self.exposureLocked = false; self.focusLocked = false; self.whiteBalanceLocked = false
                self.zoomFactor = 1
                self.publishCapabilities()
            }
        }
    }

    /// Inspect the active device and republish which controls are available.
    private func publishCapabilities() {
        guard let dev = activeDevice else { capabilities = DeviceCapabilities(); return }
        var caps = DeviceCapabilities()
        caps.canLockExposure = dev.isExposureModeSupported(.locked) && dev.isExposureModeSupported(.continuousAutoExposure)
        caps.canLockFocus = dev.isFocusModeSupported(.locked)
        caps.canFocusAtPoint = dev.isFocusPointOfInterestSupported
        caps.canLockWhiteBalance = dev.isWhiteBalanceModeSupported(.locked)
        if #available(macOS 12.3, *) { caps.canCenterStage = dev.activeFormat.isCenterStageSupported }
        caps.canMirror = (movieOutput.connection(with: .video)?.isVideoMirroringSupported ?? false)
            || (session.connections.first { $0.isVideoMirroringSupported } != nil)
        if #available(macOS 14.0, *), dev.canPerformReactionEffects {
            caps.canReact = true
            let map = Dictionary(uniqueKeysWithValues: dev.availableReactionTypes.map { ($0.rawValue, $0) })
            reactionTypeMap = map
            caps.reactionTypes = Array(map.keys).sorted()
        }
        let dims = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription)
        caps.maxZoom = CaptureGeometry.maxZoom(formatWidth: CGFloat(dims.width))
        sensorAspect = dims.height > 0 ? CGFloat(dims.width) / CGFloat(dims.height) : 16.0 / 9.0
        capabilities = caps
        centerStageObservation = nil
        if #available(macOS 12.3, *) {
            centerStageObservation = dev.observe(\.isCenterStageActive, options: [.initial, .new]) { [weak self] device, _ in
                DispatchQueue.main.async { self?.centerStageOn = device.isCenterStageActive }
            }
        } else {
            centerStageOn = false
        }
    }

    // MARK: Device configuration helper

    /// Acquire an exclusive lock, mutate the device, then republish state.
    private func configureDevice(_ body: @escaping (AVCaptureDevice) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let dev = self.activeDevice else { return }
            do { try dev.lockForConfiguration(); body(dev); dev.unlockForConfiguration() }
            catch { return }
        }
    }

    // MARK: Controls

    func toggleExposureLock() {
        let lock = !exposureLocked
        configureDevice { dev in
            dev.exposureMode = lock ? .locked : .continuousAutoExposure
        }
        exposureLocked = lock
        showStatus(lock ? "Exposure locked" : "Auto exposure")
    }

    func toggleFocusLock() {
        let lock = !focusLocked
        configureDevice { dev in
            if dev.isFocusModeSupported(lock ? .locked : .continuousAutoFocus) {
                dev.focusMode = lock ? .locked : .continuousAutoFocus
            }
        }
        focusLocked = lock
        showStatus(lock ? "Focus locked" : "Auto focus")
    }

    func toggleWhiteBalanceLock() {
        let lock = !whiteBalanceLocked
        configureDevice { dev in
            if dev.isWhiteBalanceModeSupported(lock ? .locked : .continuousAutoWhiteBalance) {
                dev.whiteBalanceMode = lock ? .locked : .continuousAutoWhiteBalance
            }
        }
        whiteBalanceLocked = lock
        showStatus(lock ? "White balance locked" : "Auto white balance")
    }

    /// Tap-to-focus at a normalized point (0…1 in preview space).
    func focus(atNormalizedPoint point: CGPoint) {
        focusPoint = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.focusPoint == point { self?.focusPoint = nil }
        }
        configureDevice { dev in
            if dev.isFocusPointOfInterestSupported {
                dev.focusPointOfInterest = point
                if dev.isFocusModeSupported(.autoFocus) { dev.focusMode = .autoFocus }
            }
            if dev.isExposurePointOfInterestSupported {
                dev.exposurePointOfInterest = point
                if dev.isExposureModeSupported(.autoExpose) { dev.exposureMode = .autoExpose }
            }
        }
    }

    func toggleCenterStage() {
        guard #available(macOS 12.3, *) else { return }
        let on = !centerStageOn
        AVCaptureDevice.isCenterStageEnabled = on
        showStatus(on ? "Center Stage on" : "Center Stage off")
    }

    func performReaction(_ raw: String) {
        guard #available(macOS 14.0, *), let type = reactionTypeMap[raw] else { return }
        configureDevice { dev in dev.performEffect(for: type) }
    }

    func setZoom(_ factor: CGFloat) {
        let clamped = min(max(1, factor), max(1, capabilities.maxZoom))
        if abs(clamped - zoomFactor) > 0.001 { zoomFactor = clamped }
    }

    func cycleZoomPreset() {
        let presets: [CGFloat] = [1, 2, 3].filter { $0 <= capabilities.maxZoom + 0.001 }
        let next = presets.first { $0 > zoomFactor + 0.01 } ?? 1
        setZoom(next)
        showStatus(String(format: "%g×", next))
    }

    func cycleAspectRatio() {
        aspectRatio = aspectRatio.next
    }

    private func applyMirroring() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            for output in [self.movieOutput as AVCaptureOutput, self.photoOutput] {
                if let conn = output.connection(with: .video), conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = self.mirrored
                }
            }
        }
    }

    // MARK: Mode

    func setMode(_ newMode: CaptureMode) {
        guard newMode != mode, !isRecording else { return }
        mode = newMode
    }

    // MARK: Capture actions

    /// Shutter. Honors the self-timer for photos; toggles recording for video.
    func trigger() {
        switch mode {
        case .photo:
            let timer = UserDefaults.standard.integer(forKey: SettingsKey.selfTimer)
            if timer > 0 { runCountdown(from: timer) { [weak self] in self?.capturePhoto() } }
            else { capturePhoto() }
        case .video:
            isRecording ? stopRecording() : startRecording()
        }
    }

    private func runCountdown(from seconds: Int, then action: @escaping () -> Void) {
        countdown = seconds
        func tick(_ remaining: Int) {
            guard remaining > 0 else { countdown = nil; action(); return }
            countdown = remaining
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(remaining - 1) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(seconds - 1) }
    }

    private func capturePhoto() {
        pendingCropLock.lock()
        pendingZoom = zoomFactor
        pendingAspect = aspectRatio.ratio
        pendingCropLock.unlock()
        triggerFlash()
        if UserDefaults.standard.bool(forKey: SettingsKey.shutterSound) {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            let settings = self.makePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let wantsHEIF = UserDefaults.standard.string(forKey: SettingsKey.photoFormat) == "heif"
        if wantsHEIF, photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            return AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        return AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
    }

    private func triggerFlash() {
        DispatchQueue.main.async {
            self.flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flash = false }
        }
    }

    private func startRecording() {
        if zoomFactor > 1.001 || aspectRatio != .full {
            showStatus("Video records the full frame")
        }
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            let url = self.outputURL(kind: .video)
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingSeconds = 0
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    self.recordingSeconds += 1
                }
            }
        }
    }

    private func stopRecording() {
        sessionQueue.async { [weak self] in self?.movieOutput.stopRecording() }
    }

    // MARK: Settings-derived values

    private func preferredPreset() -> AVCaptureSession.Preset {
        switch UserDefaults.standard.string(forKey: SettingsKey.videoQuality) {
        case "medium": return .medium
        case "photo": return .photo
        default: return .high
        }
    }

    enum OutputKind { case photo, video }

    private func outputURL(kind: OutputKind) -> URL {
        let key = kind == .photo ? SettingsKey.photoDir : SettingsKey.videoDir
        let ext = kind == .photo
            ? (UserDefaults.standard.string(forKey: SettingsKey.photoFormat) == "heif" ? "heic" : "jpg")
            : "mov"
        let base: URL
        if let custom = UserDefaults.standard.string(forKey: key), !custom.isEmpty {
            base = URL(fileURLWithPath: custom)
        } else {
            let dir: FileManager.SearchPathDirectory = kind == .photo ? .picturesDirectory : .moviesDirectory
            base = (try? FileManager.default.url(for: dir, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return base.appendingPathComponent("Camera \(stamp).\(ext)")
    }

    private func showStatus(_ message: String) {
        DispatchQueue.main.async {
            withAnimation { self.statusMessage = message }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { if self.statusMessage == message { self.statusMessage = nil } }
            }
        }
    }

    private func announce(_ message: String, capture url: URL?) {
        DispatchQueue.main.async {
            if let url { self.lastCapture = url }
        }
        showStatus(message)
    }
}

// MARK: - Photo delegate
extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            announce("Photo failed", capture: nil); return
        }
        let final = croppedPhotoData(data) ?? data   // never lose a shot
        let url = outputURL(kind: .photo)
        do { try final.write(to: url); announce("Saved photo", capture: url) }
        catch { announce("Could not save photo", capture: nil) }
    }

    /// Applies the zoom/aspect crop the user saw in the preview. Returns nil
    /// (caller falls back to the original) when no crop is active or any
    /// ImageIO step fails.
    private func croppedPhotoData(_ data: Data) -> Data? {
        pendingCropLock.lock()
        let zoom = pendingZoom
        let aspect = pendingAspect
        pendingCropLock.unlock()
        guard zoom > 1.001 || aspect != nil else { return nil }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let rect = CaptureGeometry.cropRect(imageSize: size, zoom: zoom, aspect: aspect)
        guard rect.width >= 1, rect.height >= 1, rect != CGRect(origin: .zero, size: size),
              let cropped = image.cropping(to: rect) else { return nil }
        let type = CGImageSourceGetType(src) ?? UTType.jpeg.identifier as CFString
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cropped, props)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}

// MARK: - Video delegate
extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingTimer?.invalidate(); self.recordingTimer = nil
        }
        announce(error == nil ? "Saved video" : "Recording failed", capture: error == nil ? outputFileURL : nil)
    }
}
