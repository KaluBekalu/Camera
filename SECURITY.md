# Security Policy

## Supported Versions

Only the latest release (the tip of `main`) is supported with security fixes.

## Reporting a Vulnerability

Camera is a local-only app: it makes no network requests, has no accounts, and
stores captures only where you tell it to. The most likely security-relevant
areas are file handling (save paths) and the camera/microphone permission
surface.

If you believe you've found a vulnerability:

- **Preferred:** open a private report via
  [GitHub Security Advisories](https://github.com/KaluBekalu/Camera/security/advisories/new).
- Or email **kalubekalu1@gmail.com** with the details.

Please include steps to reproduce and the macOS version. You can expect an
acknowledgment within a few days. Please don't open a public issue for
security reports until a fix has shipped.
