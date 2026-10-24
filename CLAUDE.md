# CLAUDE.md

Guidance for Claude Code sessions in this repo. [CONTRIBUTING.md](CONTRIBUTING.md) has the rules for every change, and [README.md](README.md) has the layout.

## Status

- v0.1.0-alpha.1 is the current alpha. Nothing in it has run on an iPhone yet. The live checks still to run are in `docs/alpha-known-issues.md`.
- Do not describe device or live-server behavior as verified unless you saw it run. CI checks run on the simulator and against the testbed.
- Design choices belong to JT. Ask before you choose one.

## Build and test

- Linux or macOS with Swift 6.1:
  - `swift format lint --strict -r Sources Tests App`
  - `swift build && swift test`
  - On Linux, install `libsqlite3-dev` first. GRDB needs it.
- `HermesKit` and `HermesSSH` build and test on Linux. They must not import UIKit, SwiftUI or Combine.
- `HermesUI` and everything under `App/` compile only on macOS. That covers the app, the widgets and share extension, and the Spotlight indexer in `App/HermesApp/Spotlight`. Only the App CI job compiles and tests them, so check those changes there.
- Every `xcodebuild build`, `archive` and `test` call passes `-skipPackagePluginValidation`. Without it, Xcode refuses the `SwiftTermBuildInfoPlugin` package plugin. `ci.yml` and `release.yml` both pass it.
- CI builds with `CODE_SIGNING_ALLOWED=NO`. The alpha `.ipa` is unsigned, and SideStore signs it on the phone.

Local macOS commands, as CI runs them:

```sh
brew install xcodegen swiftlint xcbeautify
xcodegen generate
swiftlint --strict
xcodebuild test -skipPackagePluginValidation -project simplyHermes.xcodeproj -scheme simplyHermes -destination "<simulator id>" CODE_SIGNING_ALLOWED=NO
```

## CI

`.github/workflows/ci.yml` runs on every PR and on pushes to `main`.

| Job | Runner | What it does |
|---|---|---|
| `Packages (Linux)` | Linux, `swift:6.1` container | Format lint, `swift build`, `swift test` |
| `Testbed smoke (Docker)` | Linux, Docker | Starts the testbed with `--profile oidc`, runs `testbed/smoke_test.py`, records REST fixtures, runs the SSH and gateway live tests |
| `App (Xcode 27, simulator)` | macOS, Xcode 27.1 | `swiftlint --strict`, starts the testbed dashboard, runs the app tests on a simulator, takes screenshots, builds the unsigned `.ipa` |

- The concurrency group cancels an in-progress run when a new run starts for the same ref. Back-to-back merges to `main` cancel each other's checks. Let one run finish before the next merge.
- The App job queues for macOS runners. It can wait a long time when many PRs push at once.
- The repo is public, so GitHub-hosted runner minutes do not count against the Actions quota. The App job still takes about an hour, so batch changes before you push.
- The App job skips a PR that changes only root `README.md`, `CLAUDE.md` or `CONTRIBUTING.md`, or files under `docs/` other than `docs/protocol/`, which tests read. The `changes` job in `ci.yml` decides this. Pushes to `main` and every other PR still run the App job.
- The App job runs tests with `-retry-tests-on-failure -test-iterations 2`. A retry can hide a flaky test, so a green App job does not prove the test is stable.
- The fold UI test, `testFoldMidStreamKeepsSessionScrollAndDraft` in `App/HermesAppUITests/HermesAppUITests.swift`, is the known flaky test. PR #85 ran only that test in the App job. It was closed without merging. Its branch, `claude/wp-54-fold-debug`, is kept for reference.

## Testbed

- `testbed/` runs a Hermes dashboard, sshd and a scripted fake LLM in Docker. Start it with `testbed/scripts/up.sh` and stop it with `testbed/scripts/down.sh`. `testbed/README.md` lists the scenarios.
- The dashboard is pinned to an upstream commit with `ARG HERMES_REF` in `testbed/hermes/Dockerfile`. Recorded fixtures come from that pin. Re-record them when you change it.
- Live tests read `HERMES_TESTBED_URL`, `HERMES_TESTBED_OIDC_URL` and `HERMES_SSH_TEST_KEY`. CI points them at ports 9119 and 9120 and at `testbed/data/ssh/id_ed25519`.
- The dashboard rate-limits password logins to 10 per minute. `testbed/tools/record_fixtures.py` logs in once for that reason, and `testbed/tools/record_rest.py` does not retry a 429 on `/auth/password-login`. Log in once per run.

## Releases

- Alpha builds come from `.github/workflows/release.yml`. Push a tag such as `v0.1.0-alpha.2`, or run the workflow by hand with `version` and `publish`.
- The version must look like `0.1.0-alpha.N`. Its `0.1.0` part must match `MARKETING_VERSION` in `project.yml`. `N` becomes the build number.
- A tag push, or a run with `publish` set, makes a GitHub prerelease with the `.ipa` and its SHA-256 file. Without either, the files are workflow artifacts only.
- Testers install from `docs/install-sidestore.md` and read `docs/alpha-known-issues.md`. The release notes link both.

## Working rules

- Keep `HermesKit` and `HermesSSH` free of UIKit, SwiftUI and Combine. See CONTRIBUTING.md.
- Format with `swift format` and lint with `swiftlint`. Add a dependency only from the approved list in CONTRIBUTING.md. Ask before adding any other.
- When install or release steps change, update `README.md` and `docs/install-sidestore.md` together.
