# simplyHermes

Native iPhone client for [Hermes Agent](https://hermes-agent.nousresearch.com), designed first for iPhone Duo.

- Plan: see `docs/architecture.md` and `CONTRIBUTING.md`.
- Connects to a Hermes dashboard server over HTTPS/WebSocket or through an SSH tunnel.
- Swift 6, SwiftUI, iOS 26.0+. Fold-aware layout on iPhone Duo needs iOS 27.1.

## Layout

| Path | What |
|---|---|
| `Sources/HermesKit` | Pure Swift core: models, JSON-RPC, REST, auth, reducer. Builds on Linux. |
| `Sources/HermesSSH` | SSH session, exec, loopback forwarder. Builds on Linux. |
| `Sources/HermesUI` | SwiftUI design system and feature views. Apple platforms only. |
| `App/` | App target, unit tests, UI tests. |
| `testbed/` | Test Hermes backend for CI (WP-03). |
| `docs/` | Architecture and protocol notes. |

## Build

- Packages (any OS with Swift 6.1): `swift build && swift test`
- App: `xcodegen generate`, then open `simplyHermes.xcodeproj`. CI does this on macOS runners; there is no local Mac requirement for the project owner.
