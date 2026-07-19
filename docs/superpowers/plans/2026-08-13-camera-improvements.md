# Camera Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add app icon, digital zoom (preview + photos), aspect-ratio selection, and a full open-source kit to the macOS Camera app.

**Architecture:** All capture-side state lives in `CameraController` (the app's hub); pure crop/zoom math goes in a new `Sources/CaptureGeometry.swift` (CoreGraphics-only, unit-tested via a CLT-compatible `test.sh`). Preview zoom is a `CATransform3D` scale on the preview layer; saved photos are center-cropped via ImageIO to match the preview exactly. The icon is drawn programmatically with CoreGraphics — no external renderer.

**Tech Stack:** Swift 5 / SwiftUI / AVFoundation / ImageIO / CoreGraphics. Build via `build.sh` (Command Line Tools only) or XcodeGen project.

## Global Constraints

- **Capability-driven UI:** no device-identity conditionals. Controls appear based on API-reported capabilities; limits derive from device-reported data (max zoom from active-format width). Live-changing values use KVO, not timed re-reads.
- **No AI attribution in any commit** — no `Co-Authored-By`, no "Generated with" lines. Plain conventional-commit messages. Author: `Kalkidan Aleme <kalkidan.aleme@tibeblabs.com>` (repo-local config, already set).
- Deployment target: macOS 14.0. Swift version 5. No new dependencies.
- `swiftc` path on this machine: `/Library/Developer/CommandLineTools/usr/bin/swiftc` (xcrun is broken here — `DEVELOPER_DIR` points to an unmounted volume; never rely on bare `xcrun` locally).
- `Sources/CaptureGeometry.swift` must import only `Foundation`/`CoreGraphics` (keeps tests dependency-free).
- Never lose a capture: any crop failure falls back to saving the original data.
- After all tasks: run `graphify update .` (AST-only) to refresh the knowledge graph.

---

### Task 1: CaptureGeometry — pure crop/zoom math + test harness

**Files:**
- Create: `Sources/CaptureGeometry.swift`
- Create: `Tests/CaptureGeometryTests.swift`
- Create: `test.sh` (executable)

**Interfaces:**
- Produces: `enum AspectRatio: String, CaseIterable, Identifiable` with cases `.full, .wide ("16:9"), .classic ("4:3"), .square ("1:1")`, properties `ratio: CGFloat?`, `label: String`, `next: AspectRatio`.
- Produces: `enum CaptureGeometry` with
  - `static func maxZoom(formatWidth: CGFloat, minOutputWidth: CGFloat = 640) -> CGFloat`
  - `static func cropRect(imageSize: CGSize, zoom: CGFloat, aspect: CGFloat?) -> CGRect`
  - `static func centeredRect(ratio: CGFloat, inside rect: CGRect) -> CGRect`

- [ ] **Step 1: Write the failing test**

`Tests/CaptureGeometryTests.swift`:

```swift
import Foundation
import CoreGraphics

var failures = 0
func expect(_ cond: Bool, _ name: String) {
    if cond { print("PASS \(name)") } else { failures += 1; print("FAIL \(name)") }
}
func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.01) -> Bool { abs(a - b) <= tol }

@main
struct TestRunner {
    static func main() {
        // maxZoom derives from format width, clamped to [1, 6]
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 1920), 3.0), "maxZoom 1920 -> 3x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 4032), 6.0), "maxZoom 4032 clamps to 6x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 640), 1.0), "maxZoom 640 -> 1x")
        expect(approx(CaptureGeometry.maxZoom(formatWidth: 0), 1.0), "maxZoom 0 -> 1x safe")

        // cropRect: zoom only — centered 1/zoom window
        let full = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 2, aspect: nil)
        expect(full == CGRect(x: 480, y: 270, width: 960, height: 540), "cropRect 2x centered")

        // cropRect: no zoom, no aspect — full frame
        let none = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 1, aspect: nil)
        expect(none == CGRect(x: 0, y: 0, width: 1920, height: 1080), "cropRect identity")

        // cropRect: square aspect from 16:9
        let sq = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 1, aspect: 1)
        expect(sq == CGRect(x: 420, y: 0, width: 1080, height: 1080), "cropRect 1:1")

        // cropRect: 16:9 aspect from 4:3 sensor
        let wide = CaptureGeometry.cropRect(imageSize: CGSize(width: 1600, height: 1200), zoom: 1, aspect: 16.0/9.0)
        expect(approx(wide.width, 1600) && approx(wide.height, 900) && approx(wide.origin.y, 150), "cropRect 16:9 from 4:3")

        // cropRect: zoom + aspect compose
        let combo = CaptureGeometry.cropRect(imageSize: CGSize(width: 1920, height: 1080), zoom: 2, aspect: 1)
        expect(combo == CGRect(x: 690, y: 270, width: 540, height: 540), "cropRect 2x + 1:1")

        // cropRect: degenerate input is safe
        expect(CaptureGeometry.cropRect(imageSize: .zero, zoom: 2, aspect: 1) == .zero, "cropRect zero size safe")

        // cropRect: odd dimensions stay integral and in-bounds
        let odd = CaptureGeometry.cropRect(imageSize: CGSize(width: 1279, height: 719), zoom: 1.7, aspect: 4.0/3.0)
        expect(odd.width == odd.width.rounded() && odd.height == odd.height.rounded(), "cropRect integral")
        expect(odd.maxX <= 1279 && odd.maxY <= 719 && odd.minX >= 0 && odd.minY >= 0, "cropRect in bounds")

        // centeredRect: mask geometry for the preview
        let cut = CaptureGeometry.centeredRect(ratio: 1, inside: CGRect(x: 0, y: 100, width: 800, height: 450))
        expect(cut == CGRect(x: 175, y: 100, width: 450, height: 450), "centeredRect square in 16:9")

        // AspectRatio cycle
        expect(AspectRatio.full.next == .wide && AspectRatio.square.next == .full, "aspect cycle wraps")
        expect(AspectRatio.wide.ratio.map { approx($0, 16.0/9.0) } == true && AspectRatio.full.ratio == nil, "aspect ratios")

        if failures > 0 { print("\(failures) FAILURES"); exit(1) }
        print("All tests passed")
    }
}
```

`test.sh`:

```bash
#!/bin/bash
# Compiles CaptureGeometry + its tests with the CLT toolchain and runs them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    else
        SWIFTC="$(xcrun -f swiftc)"
    fi
fi
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path --sdk macosx)"
ARCH="$(uname -m)"

mkdir -p "$ROOT/build"
"$SWIFTC" -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -swift-version 5 -parse-as-library \
    -o "$ROOT/build/capture-geometry-tests" \
    "$ROOT/Sources/CaptureGeometry.swift" "$ROOT/Tests/CaptureGeometryTests.swift"
exec "$ROOT/build/capture-geometry-tests"
```

Then: `chmod +x test.sh`

- [ ] **Step 2: Run test to verify it fails**

Run: `./test.sh`
Expected: FAIL to compile — `cannot find 'CaptureGeometry' in scope` (file doesn't exist yet).

- [ ] **Step 3: Write minimal implementation**

`Sources/CaptureGeometry.swift`:

```swift
import Foundation
import CoreGraphics

/// Selectable output aspect ratios. `full` means the sensor's native frame.
enum AspectRatio: String, CaseIterable, Identifiable {
    case full = "full"
    case wide = "16:9"
    case classic = "4:3"
    case square = "1:1"

    var id: String { rawValue }

    /// width / height; nil means keep the native frame.
    var ratio: CGFloat? {
        switch self {
        case .full: return nil
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        case .square: return 1
        }
    }

    var label: String { self == .full ? "Full" : rawValue }

    var next: AspectRatio {
        let all = AspectRatio.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Pure geometry for digital zoom and aspect-ratio cropping. macOS exposes no
/// device zoom API (`videoZoomFactor` is unavailable), so zoom is a centered
/// crop computed here and applied to the preview transform and saved photos.
enum CaptureGeometry {

    /// Max digital zoom for a capture format, derived from its pixel width so
    /// the cropped output never drops below `minOutputWidth`. Clamped to [1, 6].
    static func maxZoom(formatWidth: CGFloat, minOutputWidth: CGFloat = 640) -> CGFloat {
        guard formatWidth > 0 else { return 1 }
        return min(6, max(1, formatWidth / minOutputWidth))
    }

    /// Centered crop rect in image pixel space for a zoom factor and optional
    /// target aspect (width/height). Integral and guaranteed within bounds.
    static func cropRect(imageSize: CGSize, zoom: CGFloat, aspect: CGFloat?) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let z = max(1, zoom)
        var w = imageSize.width / z
        var h = imageSize.height / z
        if let a = aspect, a > 0 {
            if w / h > a { w = h * a } else { h = w / a }
        }
        w.round(.down)
        h.round(.down)
        let x = ((imageSize.width - w) / 2).rounded(.down)
        let y = ((imageSize.height - h) / 2).rounded(.down)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Largest rect of the given aspect (width/height) centered inside `rect`.
    /// Used to position the preview's dimmed letterbox masks.
    static func centeredRect(ratio: CGFloat, inside rect: CGRect) -> CGRect {
        guard ratio > 0, rect.width > 0, rect.height > 0 else { return rect }
        var w = rect.width
        var h = rect.height
        if w / h > ratio { w = h * ratio } else { h = w / ratio }
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./test.sh`
Expected: all `PASS` lines, exit 0, `All tests passed`.

- [ ] **Step 5: Verify the app still builds**

Run: `./build.sh`
Expected: `✓ Built .../build/Camera.app` (new file compiles into the app harmlessly).

- [ ] **Step 6: Commit**

```bash
git add Sources/CaptureGeometry.swift Tests/CaptureGeometryTests.swift test.sh
git commit -m "feat: add CaptureGeometry crop/zoom math with test harness"
```

---

### Task 2: CameraController — zoom + aspect state (capability-driven)

**Files:**
- Modify: `Sources/CameraController.swift`
- Modify: `Sources/Settings.swift` (add `SettingsKey.aspectRatio` + registered default)

**Interfaces:**
- Consumes: `CaptureGeometry.maxZoom`, `AspectRatio` (Task 1).
- Produces (used by Tasks 3–5):
  - `DeviceCapabilities.maxZoom: CGFloat` (default 1)
  - `@Published private(set) var zoomFactor: CGFloat` (default 1)
  - `@Published var aspectRatio: AspectRatio` (persisted to `SettingsKey.aspectRatio`)
  - `func setZoom(_ factor: CGFloat)` — clamps to `[1, capabilities.maxZoom]`
  - `func cycleZoomPreset()` — cycles 1×→2×→3×→1× (presets filtered by maxZoom)
  - `@Published private(set) var sensorAspect: CGFloat` (active format w/h, default 16/9)

- [ ] **Step 1: Add the settings key**

In `Sources/Settings.swift`, add to `SettingsKey`:

```swift
    static let aspectRatio = "aspectRatio"    // AspectRatio rawValue
```

and to `registerDefaults()` dictionary:

```swift
            aspectRatio: AspectRatio.full.rawValue,
```

- [ ] **Step 2: Add zoom/aspect state to CameraController**

In `DeviceCapabilities` (CameraController.swift:23) add:

```swift
    var maxZoom: CGFloat = 1
```

In the "Published UI state" section add:

```swift
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
```

Add controls (in `// MARK: Controls`):

```swift
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
```

- [ ] **Step 3: Derive maxZoom + sensorAspect from the active format**

In `publishCapabilities()` (CameraController.swift:197), after the existing capability lines and before `capabilities = caps`, add:

```swift
        let dims = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription)
        caps.maxZoom = CaptureGeometry.maxZoom(formatWidth: CGFloat(dims.width))
        sensorAspect = dims.height > 0 ? CGFloat(dims.width) / CGFloat(dims.height) : 16.0 / 9.0
```

Add `import CoreMedia` at the top of the file (below `import Combine`).

- [ ] **Step 4: Reset zoom on device switch**

In `switchToSelectedDevice()`'s trailing `DispatchQueue.main.async` block (CameraController.swift:189), add:

```swift
                self.zoomFactor = 1
```

- [ ] **Step 5: Build**

Run: `./build.sh` → Expected: `✓ Built`. Run `./test.sh` → Expected: `All tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CameraController.swift Sources/Settings.swift
git commit -m "feat: zoom and aspect-ratio state with format-derived limits"
```

---

### Task 3: Preview layer — zoom transform, gravity, scroll-wheel

**Files:**
- Modify: `Sources/CameraPreview.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Task 4): `CameraPreview(session:mirrored:zoom:aspectFill:onZoomDelta:)` — `zoom: CGFloat = 1`, `aspectFill: Bool = true`, `onZoomDelta: ((CGFloat) -> Void)? = nil` (scroll-wheel pixels, positive = zoom in).

- [ ] **Step 1: Extend CameraPreview**

Replace the full contents of `Sources/CameraPreview.swift` with:

```swift
import SwiftUI
import AVFoundation

/// Live camera preview backed by `AVCaptureVideoPreviewLayer`.
///
/// Digital zoom is a GPU-composited `CATransform3D` scale on the preview
/// layer (macOS has no device zoom API); the matching crop is applied to
/// saved photos so preview and output agree.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var mirrored: Bool = false
    var zoom: CGFloat = 1
    var aspectFill: Bool = true
    var onZoomDelta: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
        apply(to: nsView)
    }

    private func apply(to view: PreviewView) {
        view.previewLayer.videoGravity = aspectFill ? .resizeAspectFill : .resizeAspect
        view.zoom = zoom
        view.onZoomDelta = onZoomDelta
        guard let conn = view.previewLayer.connection, conn.isVideoMirroringSupported else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = mirrored
    }

    /// Layer-backed NSView that hosts the capture preview layer as a *sublayer*
    /// (more reliable than making it the backing layer) and keeps it sized to
    /// the view's bounds. Zoom scales the layer around its center.
    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        var onZoomDelta: ((CGFloat) -> Void)?

        var zoom: CGFloat = 1 {
            didSet {
                guard zoom != oldValue else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                previewLayer.transform = CATransform3DMakeScale(zoom, zoom, 1)
                CATransaction.commit()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.masksToBounds = true
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            // Set bounds+position (not frame) so the zoom transform composes
            // cleanly; disable implicit animations so resizing tracks crisply.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.bounds = bounds
            previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            CATransaction.commit()
        }

        override func scrollWheel(with event: NSEvent) {
            onZoomDelta?(event.scrollingDeltaY)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `./build.sh` → Expected: `✓ Built` (call sites still compile — new params have defaults).

- [ ] **Step 3: Commit**

```bash
git add Sources/CameraPreview.swift
git commit -m "feat: preview zoom transform, gravity switch, scroll-wheel hook"
```

---

### Task 4: ContentView — zoom/aspect controls, pinch, masks

**Files:**
- Modify: `Sources/ContentView.swift`

**Interfaces:**
- Consumes: `camera.zoomFactor`, `camera.setZoom`, `camera.cycleZoomPreset`, `camera.cycleAspectRatio`, `camera.aspectRatio`, `camera.sensorAspect`, `camera.capabilities.maxZoom` (Task 2); `CameraPreview` params (Task 3); `CaptureGeometry.centeredRect`, `AspectRatio` (Task 1).
- Produces: `AspectMaskOverlay` view (private to file).

- [ ] **Step 1: Wire preview params + pinch gesture**

In `ContentView`, add state (below the `@AppStorage` lines):

```swift
    @State private var zoomAtPinchStart: CGFloat?
```

Replace `previewLayer` (ContentView.swift:47-62) with:

```swift
    private var previewLayer: some View {
        GeometryReader { geo in
            CameraPreview(session: camera.session,
                          mirrored: camera.mirrored,
                          zoom: camera.zoomFactor,
                          aspectFill: camera.aspectRatio == .full,
                          onZoomDelta: { delta in
                              camera.setZoom(camera.zoomFactor * (1 + delta * 0.01))
                          })
                .overlay {
                    if let ratio = camera.aspectRatio.ratio {
                        AspectMaskOverlay(sensorAspect: camera.sensorAspect, targetRatio: ratio)
                    }
                }
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
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if zoomAtPinchStart == nil { zoomAtPinchStart = camera.zoomFactor }
                            camera.setZoom((zoomAtPinchStart ?? 1) * value.magnification)
                        }
                        .onEnded { _ in zoomAtPinchStart = nil }
                )
                .ignoresSafeArea()
        }
    }
```

- [ ] **Step 2: Add the dimmed aspect mask overlay**

At the bottom of `Sources/ContentView.swift` (after `GlassTimerButton`), add:

```swift
/// Dims the regions of the preview that fall outside the selected aspect
/// ratio, iOS-Camera style. The clear window is exactly what gets saved.
private struct AspectMaskOverlay: View {
    let sensorAspect: CGFloat   // active format width/height
    let targetRatio: CGFloat    // selected output width/height

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size)
            let video = CaptureGeometry.centeredRect(ratio: sensorAspect, inside: bounds)
            let window = CaptureGeometry.centeredRect(ratio: targetRatio, inside: video)
            Path { p in
                p.addRect(bounds)
                p.addRect(window)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 3: Add zoom + aspect buttons to the control column**

In `controlColumn` (ContentView.swift:135), after the `GlassTimerButton(seconds: $selfTimer)` line, add:

```swift
            if camera.capabilities.maxZoom >= 1.5 {
                Button { camera.cycleZoomPreset() } label: {
                    Text(zoomLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(camera.zoomFactor > 1.01 ? Theme.accent : .white)
                        .frame(width: Theme.controlSize, height: Theme.controlSize)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(
                            camera.zoomFactor > 1.01 ? Theme.accent.opacity(0.9) : .white.opacity(0.12),
                            lineWidth: camera.zoomFactor > 1.01 ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .help("Zoom (pinch or scroll on the preview)")
            }

            Button { camera.cycleAspectRatio() } label: {
                Text(camera.aspectRatio.label)
                    .font(.system(size: camera.aspectRatio == .full ? 10 : 11, weight: .bold))
                    .foregroundStyle(camera.aspectRatio == .full ? .white : Theme.accent)
                    .frame(width: Theme.controlSize, height: Theme.controlSize)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(
                        camera.aspectRatio == .full ? .white.opacity(0.12) : Theme.accent.opacity(0.9),
                        lineWidth: camera.aspectRatio == .full ? 1 : 1.5))
            }
            .buttonStyle(.plain)
            .help("Aspect ratio")
```

And add the helper next to `timeString` (ContentView.swift:203):

```swift
    private var zoomLabel: String {
        camera.zoomFactor > 1.01 ? String(format: "%.1f×", camera.zoomFactor) : "1×"
    }
```

- [ ] **Step 4: Build and verify visually**

Run: `./build.sh && open build/Camera.app`
Expected: zoom button + aspect button appear on the right column (zoom only when the camera's format allows ≥1.5×); pinch and scroll zoom the preview smoothly; selecting 16:9/4:3/1:1 letterboxes with dimmed masks; grid/focus tap still work.

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "feat: zoom and aspect-ratio controls with dimmed preview masks"
```

---

### Task 5: Photo crop on capture + video full-frame notice

**Files:**
- Modify: `Sources/CameraController.swift`

**Interfaces:**
- Consumes: `CaptureGeometry.cropRect` (Task 1), `zoomFactor`/`aspectRatio` (Task 2).
- Produces: photos saved cropped to match the preview; `showStatus` notice when recording starts with zoom/aspect active.

- [ ] **Step 1: Capture the crop parameters at shutter time**

In `CameraController`, add near the other private vars (CameraController.swift:76):

```swift
    private var pendingZoom: CGFloat = 1
    private var pendingAspect: CGFloat?
```

In `capturePhoto()` (CameraController.swift:340), at the top (main thread — before `triggerFlash()`), add:

```swift
        pendingZoom = zoomFactor
        pendingAspect = aspectRatio.ratio
```

- [ ] **Step 2: Crop in the photo delegate with lossless fallback**

Add `import ImageIO` and `import UniformTypeIdentifiers` at the top of the file. Replace the `AVCapturePhotoCaptureDelegate` extension (CameraController.swift:433-443) with:

```swift
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
        guard pendingZoom > 1.001 || pendingAspect != nil else { return nil }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        let rect = CaptureGeometry.cropRect(imageSize: size, zoom: pendingZoom, aspect: pendingAspect)
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
```

- [ ] **Step 3: Video notice**

In `startRecording()` (CameraController.swift:367), before `sessionQueue.async`, add:

```swift
        if zoomFactor > 1.001 || aspectRatio != .full {
            showStatus("Video records the full frame")
        }
```

(`startRecording` is invoked from `trigger()` on the main thread, so reading published state here is safe.)

- [ ] **Step 4: Build + manual verify**

Run: `./build.sh && open build/Camera.app`
Expected: set 2× + 1:1, take a photo → saved file dimensions are square and half the sensor width (check with `sips -g pixelWidth -g pixelHeight <file>`), image matches the clear preview window. A photo at 1×/Full saves byte-identical path (no re-encode). Start recording at 2× → "Video records the full frame" badge appears.

- [ ] **Step 5: Commit**

```bash
git add Sources/CameraController.swift
git commit -m "feat: crop saved photos to match preview zoom and aspect"
```

---

### Task 6: Center Stage KVO (replace timed re-read)

**Files:**
- Modify: `Sources/CameraController.swift`

**Interfaces:**
- Consumes: existing `centerStageOn`, `activeDevice`.
- Produces: `centerStageOn` now tracks the device via KVO — including changes made from Control Center.

- [ ] **Step 1: Add the observation**

Add near the other private vars (CameraController.swift:76):

```swift
    private var centerStageObservation: NSKeyValueObservation?
```

In `publishCapabilities()` (CameraController.swift:197), replace the final line

```swift
        centerStageOn = { if #available(macOS 12.3, *) { return dev.isCenterStageActive } else { return false } }()
```

with:

```swift
        centerStageObservation = nil
        if #available(macOS 12.3, *) {
            centerStageObservation = dev.observe(\.isCenterStageActive, options: [.initial, .new]) { [weak self] device, _ in
                DispatchQueue.main.async { self?.centerStageOn = device.isCenterStageActive }
            }
        } else {
            centerStageOn = false
        }
```

In `toggleCenterStage()` (CameraController.swift:279), delete the trailing `DispatchQueue.main.asyncAfter` re-read block (lines 286-289) and the `centerStageOn = on` line — KVO now owns the published state:

```swift
    func toggleCenterStage() {
        guard #available(macOS 12.3, *) else { return }
        let on = !centerStageOn
        AVCaptureDevice.isCenterStageEnabled = on
        showStatus(on ? "Center Stage on" : "Center Stage off")
    }
```

- [ ] **Step 2: Build + verify**

Run: `./build.sh && open build/Camera.app`
Expected: with a Continuity Camera or supported Mac, the Center Stage button reflects toggles from both the app and Control Center's Video Effects menu.

- [ ] **Step 3: Commit**

```bash
git add Sources/CameraController.swift
git commit -m "refactor: track Center Stage state via KVO instead of timed re-read"
```

---

### Task 7: App icon — programmatic drawing + build wiring

**Files:**
- Create: `scripts/make-icon.swift`
- Create: `scripts/make-icon.sh` (executable)
- Create: `Resources/AppIcon.icns` (generated, committed)
- Modify: `Resources/Info.plist`, `build.sh`, `project.yml`

**Interfaces:**
- Produces: `Resources/AppIcon.icns` consumed by `build.sh` and the Xcode target.

- [ ] **Step 1: Write the icon drawer**

`scripts/make-icon.swift` — draws the icon with CoreGraphics at any size. Design: Big Sur-style squircle (canvas margin ~10%), dark glass vertical gradient, concentric lens rings, yellow accent arc echoing `Theme.accent`, specular highlight:

```swift
import AppKit

// Draws the Camera app icon at the given canvas size and writes a PNG.
// Usage: make-icon <size> <output.png>

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon <size> <out.png>\n".utf8))
    exit(64)
}
let out = URL(fileURLWithPath: args[2])
let S = CGFloat(size)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let ctx = gc.cgContext

// Squircle plate: macOS icon grid keeps ~10% transparent margin.
let margin = S * 0.10
let plate = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
let corner = plate.width * 0.2237
let platePath = NSBezierPath(roundedRect: plate, xRadius: corner, yRadius: corner)

// Dark glass background gradient.
platePath.addClip()
let bg = NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.19, alpha: 1),
                             NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)])!
bg.draw(in: plate, angle: -90)

// Lens: concentric rings centered on the plate.
let c = CGPoint(x: plate.midX, y: plate.midY)
func circle(_ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))
}
let rOuter = plate.width * 0.34

// Outer barrel ring.
NSColor(white: 0.30, alpha: 1).setStroke()
let barrel = circle(rOuter); barrel.lineWidth = S * 0.015; barrel.stroke()

// Glass body.
let body = circle(rOuter * 0.92)
let bodyGrad = NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1),
                                   NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)])!
bodyGrad.draw(in: body, angle: -70)

// Accent ring (Theme.accent yellow).
NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.04, alpha: 0.95).setStroke()
let accent = circle(rOuter * 0.72); accent.lineWidth = S * 0.022; accent.stroke()

// Inner pupil.
let pupil = circle(rOuter * 0.45)
NSGradient(colors: [NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.45, alpha: 1),
                    NSColor.black])!.draw(in: pupil, angle: -60)

// Specular highlight, upper-left.
let hl = NSBezierPath(ovalIn: CGRect(x: c.x - rOuter * 0.52, y: c.y + rOuter * 0.10,
                                     width: rOuter * 0.52, height: rOuter * 0.40))
NSColor(white: 1, alpha: 0.28).setFill(); hl.fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
```

`scripts/make-icon.sh`:

```bash
#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
# Requires only the Command Line Tools (swiftc + iconutil).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    else
        SWIFTC="$(xcrun -f swiftc)"
    fi
fi
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path --sdk macosx)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$SWIFTC" -sdk "$SDK" -O -o "$TMP/make-icon" "$ROOT/scripts/make-icon.swift"

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for entry in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
             256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px="${entry%%:*}"; name="${entry#*:}"
    "$TMP/make-icon" "$px" "$SET/icon_$name.png"
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
echo "✓ Wrote Resources/AppIcon.icns"
```

Then: `chmod +x scripts/make-icon.sh`

- [ ] **Step 2: Generate the icon**

Run: `./scripts/make-icon.sh`
Expected: `✓ Wrote Resources/AppIcon.icns`. Sanity-check: `file Resources/AppIcon.icns` reports "Mac OS X icon"; preview it with `qlmanage -p Resources/AppIcon.icns` if desired.

- [ ] **Step 3: Wire into Info.plist, build.sh, project.yml**

`Resources/Info.plist` — add inside the `<dict>` (after `CFBundlePackageType`):

```xml
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
```

`build.sh` — after the `cp .../Info.plist` line (build.sh:33), add:

```bash
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
```

`project.yml` — in the `Camera` target, after the `sources:` block, add:

```yaml
    resources:
      - path: Resources/AppIcon.icns
```

Regenerate the Xcode project if XcodeGen is installed (`command -v xcodegen && xcodegen generate`); if not installed, note it — CI and build.sh don't need it, and the committed change to project.yml keeps it the source of truth.

- [ ] **Step 4: Build + verify**

Run: `./build.sh && open build/Camera.app`
Expected: the new lens icon shows in the Dock (macOS may cache the old generic icon; `killall Dock` refreshes).

- [ ] **Step 5: Commit**

```bash
git add scripts/ Resources/AppIcon.icns Resources/Info.plist build.sh project.yml Camera.xcodeproj
git commit -m "feat: add programmatically drawn app icon"
```

---

### Task 8: build.sh portability + version bump

**Files:**
- Modify: `build.sh`, `project.yml`, `Resources/Info.plist`, `Sources/Settings.swift`

**Interfaces:**
- Produces: `build.sh` that works on GitHub runners (no hardcoded CLT path / arm64), version 1.2 everywhere.

- [ ] **Step 1: Make build.sh host-portable**

In `build.sh`, replace the `SWIFTC=` line (build.sh:12) with:

```bash
SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    else
        SWIFTC="$(xcrun -f swiftc)"
    fi
fi
ARCH="$(uname -m)"
```

And replace the SDK fallback line (build.sh:16) with:

```bash
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path --sdk macosx)"
```

And change the `-target` line (build.sh:26) to:

```bash
    -target "$ARCH-apple-macosx14.0" \
```

- [ ] **Step 2: Bump version to 1.2**

- `project.yml`: `MARKETING_VERSION: "1.2"`
- `Resources/Info.plist`: `CFBundleShortVersionString` → `1.2`
- `Sources/Settings.swift` `AboutSettings` (Settings.swift:128): `Text("Version 1.2")`, and replace the About paragraph with:

```swift
            Text("A lightweight, iOS-style camera for macOS.\nZoom and aspect ratio are digital (centered crops) because macOS doesn't expose device zoom — every other control appears only when your camera reports support for it.")
```

- [ ] **Step 3: Build both paths**

Run: `./build.sh && ./test.sh` → Expected: both succeed.

- [ ] **Step 4: Commit**

```bash
git add build.sh project.yml Resources/Info.plist Sources/Settings.swift
git commit -m "chore: portable toolchain resolution in build.sh; bump to 1.2"
```

---

### Task 9: Open-source kit — LICENSE, CONTRIBUTING, templates, CI

**Files:**
- Create: `LICENSE`, `CONTRIBUTING.md`, `.github/workflows/build.yml`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`

**Interfaces:** none (documentation/infra).

- [ ] **Step 1: LICENSE (MIT)**

```
MIT License

Copyright (c) 2026 Kalkidan Aleme

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: CONTRIBUTING.md**

```markdown
# Contributing to Camera

Thanks for your interest! This is a deliberately *simple* camera app — speed
and familiarity over pro features. PRs that fit that scope are very welcome.

## Building

Two ways, no paid Apple account needed:

- **Xcode:** `open Camera.xcodeproj`, then ⌘R ("Sign to Run Locally").
- **Command Line Tools only:** `./build.sh`, then `open build/Camera.app`.

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonwoo9/XcodeGen). If you add/rename files or
change build settings, edit `project.yml` and run `xcodegen generate` —
don't hand-edit the `.xcodeproj`.

## Tests

`./test.sh` compiles and runs the unit tests for the pure geometry code
(`Sources/CaptureGeometry.swift`). CI runs both `build.sh` and `test.sh` on
every push/PR — please make sure both pass locally.

## Design ground rules

- **Capability-driven UI:** controls are shown/hidden based on what the
  active device *reports* (`DeviceCapabilities`), never on device identity.
  Derive limits from device data; observe live values with KVO.
- **Never lose a capture:** post-processing failures must fall back to
  saving the original data.
- Keep the "glass" visual language — reuse `Theme` components.

## Reporting bugs / proposing features

Use the issue templates. For features, check the Roadmap section in the
README first — an item there just needs a champion.
```

- [ ] **Step 3: CI workflow**

`.github/workflows/build.yml`:

```yaml
name: Build
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build app
        run: ./build.sh
      - name: Run tests
        run: ./test.sh
```

- [ ] **Step 4: Issue templates**

`.github/ISSUE_TEMPLATE/bug_report.md`:

```markdown
---
name: Bug report
about: Something broken or behaving oddly
labels: bug
---

**What happened?**

**What did you expect?**

**Steps to reproduce**
1.

**Setup**
- macOS version:
- Camera used (built-in / iPhone via Continuity / external model):
- App version (Settings → About):
- Built via (Xcode / build.sh):
```

`.github/ISSUE_TEMPLATE/feature_request.md`:

```markdown
---
name: Feature request
about: Propose an addition (check the README roadmap first)
labels: enhancement
---

**What would you like Camera to do?**

**Why does it fit a *simple* camera app?**

**Anything from the README roadmap this relates to?**
```

- [ ] **Step 5: Commit**

```bash
git add LICENSE CONTRIBUTING.md .github/
git commit -m "chore: add license, contributing guide, issue templates, and CI"
```

---

### Task 10: README overhaul + roadmap

**Files:**
- Modify: `README.md`

**Interfaces:** none.

- [ ] **Step 1: Update README**

Apply these changes (keeping the existing tone and the Build & run / layout sections):

1. Under the title, add badges:

```markdown
![Build](https://github.com/KaluBekalu/Camera/actions/workflows/build.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
```

2. In **Features**, after the "Adaptive camera controls" bullet-group, add:

```markdown
- **Digital zoom** — pinch, scroll, or tap the zoom button (up to 6× depending
  on the camera's native resolution). Photos are cropped to exactly match the
  preview.
- **Aspect ratio** — Full / 16:9 / 4:3 / 1:1 with iOS-style dimmed framing;
  saved photos match the visible window.
```

3. Replace the "Why no manual ISO / shutter / zoom?" section body with:

```markdown
macOS marks these `API_UNAVAILABLE(macos)` on capture devices — Apple doesn't
expose manual exposure duration, ISO, EV bias, or *device* zoom for Mac
capture (verified against the macOS 26 SDK headers). Zoom here is therefore
digital: a centered crop applied identically to the preview and saved photos.
Everything else is capability-driven — the app queries what your camera
supports and shows exactly those controls.
```

4. Add a **Screenshots** placeholder section after Features:

```markdown
## Screenshots

*(coming soon)*
```

5. Add a **Roadmap / Ideas** section before Requirements:

```markdown
## Roadmap / Ideas

Contributions welcome — these are researched-but-unbuilt ideas, roughly ordered:

- **Screen flash** — flood the display white as fill light (the iPhone's torch
  is not exposed to macOS; verified at runtime).
- Zoom/aspect crop for **recorded video** (needs an `AVAssetWriter` pipeline
  to replace `AVCaptureMovieFileOutput`).
- Burst mode · GIF/clip capture · Core Image filters
- Session gallery strip · share menu from the thumbnail
- Global snap hotkey · `camera://snap` URL scheme
- Countdown sounds · gesture/smile trigger (Vision)
- Video pause/resume · codec (HEVC/H.264) and fps pickers
- Desk View window · floating picture-in-picture preview
- Watermark / timestamp overlay
```

6. In **Project layout**, add rows:

```markdown
| `Sources/CaptureGeometry.swift` | Pure zoom/aspect crop math (unit-tested) |
| `Tests/` + `test.sh` | CLT-only unit tests for the geometry code |
| `scripts/make-icon.sh` | Regenerates `Resources/AppIcon.icns` programmatically |
```

7. Add a **License** section at the end:

```markdown
## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document zoom/aspect, add badges, roadmap, and license section"
```

---

### Task 11: Final verification, graph update, push

**Files:**
- Modify: none (verification only); `graphify-out/` refresh (untracked).

- [ ] **Step 1: Full verification pass**

```bash
./test.sh && ./build.sh
git log --oneline
git log --format=%B | grep -iE "claude|anthropic|co-authored|generated" && echo "ATTRIBUTION FOUND — FIX" || echo "history clean"
```

Expected: tests pass, build succeeds, history clean.

- [ ] **Step 2: Manual smoke test**

`open build/Camera.app` — verify: icon in Dock; zoom via pinch/scroll/button; aspect cycling with masks; photo at 2×+1:1 saves cropped (`sips -g pixelWidth -g pixelHeight`); photo at 1×/Full saves unmodified; video shows full-frame notice; device switch resets zoom; Center Stage syncs with Control Center.

- [ ] **Step 3: Update the knowledge graph**

Run: `graphify update .` (AST-only, no API cost).

- [ ] **Step 4: Push**

```bash
git push origin main
```

Expected: CI "Build" workflow goes green on GitHub.
