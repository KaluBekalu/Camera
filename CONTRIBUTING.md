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
