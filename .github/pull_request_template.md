## What does this PR do?

<!-- One or two sentences. Link the issue or roadmap item if there is one. -->

## Checklist

- [ ] `./build.sh` succeeds locally
- [ ] `./test.sh` passes (add cases to `Tests/` if you touched `CaptureGeometry`)
- [ ] New controls are **capability-driven** (gated by what the device reports,
      never by device identity) — see CONTRIBUTING.md
- [ ] Capture paths keep the **never-lose-a-shot** guarantee (failures fall back
      to saving the original)
- [ ] Project changes were made in `project.yml` (+ `xcodegen generate`), not by
      hand-editing `Camera.xcodeproj`
- [ ] Screenshots included for UI changes
