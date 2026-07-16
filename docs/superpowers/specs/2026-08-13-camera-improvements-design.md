# Camera Improvements — Design Spec

Date: 2026-08-13
Status: awaiting user review

## Goal

Four improvements to the macOS Camera app: (1) an app icon, (2) open-source preparation with a private GitHub publish, (3) digital zoom, (4) aspect-ratio selection. Plus a documented backlog of brainstormed future features.

## Guiding principle: capability-driven UI

No feature is gated by device identity (`if device == iPhone…`). Every control's visibility and limits come from platform capability APIs, observed live via KVO where the value can change at runtime:

- Controls appear only when the active device/format reports support (`isCenterStageSupported`, `canPerformReactionEffects`, `isTorchAvailable`, …). This is already the codebase's `DeviceCapabilities` pattern — new work extends it, never bypasses it.
- Replace the existing timed re-read of `isCenterStageActive` (0.4 s `asyncAfter`) with KVO observation.
- Numeric limits derive from device-reported data, not constants: max digital zoom is computed from the active format's pixel dimensions (zoom capped where the cropped output would fall below a 640-px minimum width), so a 4K Continuity Camera feed allows deeper zoom than a 720p webcam automatically.
- Observe `displayVideoZoomFactorMultiplier` (macOS 14+) via KVO so system-driven zoom on Continuity Camera is reflected, not fought.

## Verified platform facts (macOS 26 SDK headers + runtime probe)

- `videoZoomFactor` is `API_UNAVAILABLE(macos)` — no device zoom API on macOS. Zoom must be digital (crop-based).
- Continuity Camera exposes only the iPhone rear camera system; no front/back swap, no macro control. Constituent-lens inspection (`activePrimaryConstituentDevice`, macOS 12+) is read-only.
- Torch APIs exist on macOS (10.15+), but the iPhone via Continuity Camera reports `hasTorch = false` at runtime (verified on this machine). No flashlight control; a "screen flash" is the viable substitute (backlog).
- System video effects (Portrait, Studio Light, Background Replacement) are user-controlled via Control Center; apps observe active state only.

## 1. App icon

- **Design:** macOS-squircle, dark glass background with subtle vertical gradient matching the app's glass aesthetic; centered lens motif — concentric rings, aperture-blade hint, specular glass highlight.
- **Source of truth:** `Resources/icon.svg` (hand-authored, checked in).
- **Build:** `scripts/make-icon.sh` renders the SVG to the 10 required sizes (16→1024 @1x/@2x) into an `.iconset`, then `iconutil -c icns` → `Resources/AppIcon.icns`. Rendering uses tools available without full Xcode (`qlmanage`/`sips` or `rsvg-convert` if present; the script picks what exists).
- **Wiring:** `Resources/AppIcon.icns` committed (so builds don't require regeneration); referenced from `project.yml` (`CFBundleIconFile`) and copied by `build.sh` into the app bundle; `Info.plist` gains `CFBundleIconFile`.

## 2. Zoom (digital; preview + photos)

- **Range:** 1.0× to a per-format computed max (see principle above), continuous.
- **Input:** trackpad pinch (`MagnifyGesture`) and scroll wheel on the preview; a glass zoom button cycling 1×/2×/3× (shown only when max zoom ≥ 2×); the button label always shows the live factor.
- **Preview:** `CATransform3D` scale on the preview layer around its center — cheap, GPU-composited.
- **Photos:** captured image is center-cropped to `1/zoom` of its dimensions and saved at cropped size (no upscaling). What you saw is what you get.
- **Video:** records full-frame (no `AVAssetWriter` rewrite in this round). When recording starts at zoom > 1×, a transient status message notes that video saves un-zoomed. Backlog item covers full video zoom.
- **State:** `@Published var zoomFactor` on `CameraController`; resets to 1× on device switch (a new device has new capabilities).

## 3. Aspect ratio

- **Choices:** Full (native) · 16:9 · 4:3 · 1:1, cycled by a glass button showing the current ratio.
- **Preview:** dimmed letterbox/pillarbox masks overlay the preview (iOS Camera style) — the visible region is exactly what will be saved.
- **Photos:** center-cropped to the selected ratio, composed with zoom (crop = zoom window ∩ ratio window).
- **Video:** same policy as zoom — full-frame with a transient notice; backlog for real video cropping.
- **Persistence:** last-used ratio saved in `UserDefaults` (`SettingsKey.aspectRatio`).

## 4. Open-source kit (private publish)

- `git init`; author = user's identity; **no AI attribution of any kind in any commit** (no co-author trailers, no generated-with lines).
- `.gitignore` review (`build/`, `graphify-out/`, `.DS_Store`, `*.xcodeproj` stays tracked since it's committed today — regenerate note in README).
- `LICENSE` — MIT, copyright Kalkidan.
- `README.md` — updated for the new features, screenshots section placeholder, badges, build instructions kept.
- `CONTRIBUTING.md` — build prerequisites, XcodeGen regeneration flow, PR expectations.
- `.github/ISSUE_TEMPLATE/` — bug report + feature request; `.github/workflows/build.yml` — macOS runner, runs `./build.sh` on push/PR.
- Publish: `gh repo create <name> --private --source . --push` (repo name confirmed at publish time).

## 5. Feature backlog (documented, not built)

Screen flash (flashlight substitute) · burst mode · GIF/clip capture · Core Image filters · session gallery strip · global snap hotkey + URL scheme · countdown sounds · gesture/smile trigger (Vision) · video pause-resume, codec/fps pickers · Desk View window · floating PiP preview · watermark/timestamp · share menu from thumbnail · real zoom/crop for video via `AVAssetWriter`.

Recorded as a "Roadmap / Ideas" section in README so contributors can pick items up.

## Architecture notes

- All capture-side changes live in `CameraController` (the graph-confirmed hub) — but zoom/crop math goes in a small new `Sources/CaptureGeometry.swift` (pure functions: crop rect from zoom+ratio+source dims) so it's unit-testable without a camera.
- UI changes: `ContentView` gains the two glass buttons and gesture handlers; `CameraPreview` gains the transform + mask application.
- `graphify update .` runs after implementation to keep the graph current.

## Error handling

- Crop failures (zero-size rect, format mismatch) fall back to saving the uncropped original — never lose a shot.
- Icon script exits non-zero with a clear message if no SVG renderer is available; the committed `.icns` keeps builds green regardless.

## Testing

- `CaptureGeometry` gets pure unit tests (crop-rect math for zoom × ratio × odd dimensions).
- Manual verification: preview/photo parity at several zoom/ratio combos on built-in cam and (when connected) Continuity Camera; device-switch resets; settings persistence.
- CI builds via `build.sh` on every push.
