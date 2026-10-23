# simplyHermes

Native iPhone client for [Hermes Agent](https://hermes-agent.nousresearch.com), designed first for iPhone Duo.

**Status: early alpha, v0.1.0-alpha.1.** This is a test build for sideloading. It is not on the App Store or TestFlight. CI runs the unit tests, simulator tests and screenshots. Nothing in this build has run on an iPhone yet. The [known issues](docs/alpha-known-issues.md) list what is unfinished and what still needs a live check.

## What works in the alpha

Most of this is covered by CI tests on the simulator. Checks against a real server and a real iPhone are still open.

- **Chat:** live transcript with inline approvals, clarify and secure prompts, find in chat, edit, regenerate, branch, and a message queue.
- **Composer:** attachments (photos, files, camera, paste), slash commands, `@` mentions, a model picker, and input history with drafts.
- **Sessions and profiles:** an offline-first session library with search, export, and `@session` links. A profile switcher.
- **Bots and automations:** the bot roster, Bot Chat, group rooms, and cron jobs in the Automations tab.
- **Tools:** skills, the skill hub, toolsets and plugins, terminal tabs, git review, a read-only file browser with QuickLook, workspaces, an artifacts gallery, and the memory journey.
- **Settings:** providers and keys, messaging, pairing and webhooks, server control and logs, usage, and kanban boards.
- **Voice and offline:** dictation, read aloud, offline chat, and on-device helpers where Apple Intelligence is on.
- **iOS integration:** Live Activity, the Bots widget, and Siri, Spotlight, Control Center and Share entry points. Share and Spotlight need the App Group, which free signing can drop.
- **Bug reports:** the app files a GitHub issue on this repo from its bug report screen. Testers need access to the private repo.

Not in this alpha: rewind (held until a live check), the MCP and capability settings (held), the Routines pane, on-device MLX models (device only), the Action button, Hermes Cloud sign-in (hidden until a live check), profile import (hidden), push notifications, and translations (English only).

## Install with SideStore

The alpha needs iOS 26.0 or later. Fold-aware layout on iPhone Duo needs iOS 27.1.

The alpha is not signed by Apple. SideStore signs it on your iPhone with a free Apple ID, so you need no paid developer account.

1. On the iPhone, sign in to GitHub with an account that has access to this private repo. Then open the [Releases page](https://github.com/simplyjaytea/simplyHermes/releases) and download the newest **Pre-release** `.ipa`.
2. In SideStore, open **My Apps**, tap **+**, and choose the `.ipa`.
3. If iOS asks you to trust the developer, go to Settings > General > VPN & Device Management and trust your Apple ID.

A free Apple ID signs an app for 7 days. SideStore refreshes it in the background when the phone reaches its refresh helper, or when you open SideStore. Refresh before it expires, or the app stops opening.

The full steps, including the one-time SideStore setup, are in [docs/install-sidestore.md](docs/install-sidestore.md).

## Connect

simplyHermes connects to a Hermes dashboard server over HTTPS or WebSocket, or through an SSH tunnel.

## Documentation

| File | What it covers |
|---|---|
| [docs/install-sidestore.md](docs/install-sidestore.md) | Installing the alpha with SideStore |
| [docs/sideloading.md](docs/sideloading.md) | Installing without a paid Apple Developer account, and checks for the first install |
| [docs/alpha-known-issues.md](docs/alpha-known-issues.md) | Known issues, decisions made by default, and live checks still to run |
| [docs/architecture.md](docs/architecture.md) | Architecture |
| [docs/protocol.md](docs/protocol.md) | Hermes dashboard protocol. Machine-readable specs are in `docs/protocol/`. |
| [docs/duo-platform.md](docs/duo-platform.md) | iPhone Duo platform notes and the posture provider |
| [docs/design-system.md](docs/design-system.md) | Design system |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Rules for changes |
| [CLAUDE.md](CLAUDE.md) | Build, CI and release facts for Claude Code sessions |

Report what you find from the app's bug report screen. It files a GitHub issue on this repo, so testers need access to the private repo.

## Layout

| Path | What |
|---|---|
| `Sources/HermesKit` | Pure Swift core: models, JSON-RPC, REST, auth, reducer. Builds on Linux. |
| `Sources/HermesSSH` | SSH session, exec, loopback forwarder. Builds on Linux. |
| `Sources/HermesUI` | SwiftUI design system and feature views. Apple platforms only. |
| `App/` | App target, widgets, share extension, unit tests and UI tests. Builds on macOS only. |
| `Tests/` | Package tests for HermesKit and HermesSSH. |
| `Fixtures/` | Recorded protocol and REST answers used by the tests. |
| `testbed/` | Test Hermes backend for CI: dashboard, sshd and a scripted fake LLM. |
| `tools/` | Helper scripts for the app icon and voice test fixtures. |
| `docs/` | Architecture, protocol, install and known-issues notes. |
| `.github/workflows/` | `ci.yml` (checks on every PR and push to `main`) and `release.yml` (alpha builds). |

## Build

Packages, on Linux or macOS with Swift 6.1:

```sh
swift format lint --strict -r Sources Tests App
swift build && swift test
```

On Linux, install `libsqlite3-dev` first. GRDB needs it.

The app, on macOS with Xcode 27.1:

```sh
brew install xcodegen swiftlint
xcodegen generate
open simplyHermes.xcodeproj
```

CI builds and tests the app on macOS runners, so a local Mac is not required. Command-line `xcodebuild` calls need `-skipPackagePluginValidation`. [CLAUDE.md](CLAUDE.md) has the details.

## Releases

Alpha builds come from `.github/workflows/release.yml`, which runs on a tag such as `v0.1.0-alpha.1`. [CLAUDE.md](CLAUDE.md) has the tag rules.
