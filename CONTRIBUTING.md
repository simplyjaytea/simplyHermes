# Contributing

## Rules for every work package (WP)

- One WP is one PR.
- Read `docs/protocol.md`, `docs/architecture.md`, `docs/duo-platform.md` and `docs/design-system.md` first (stubs exist until their WP lands).
- Only approved dependencies: Citadel, SwiftNIO (via Citadel), GRDB, swift-markdown, SwiftTerm, swift-snapshot-testing, mlx-swift + MLX LM, swift-openapi-generator (only if the server exposes `/openapi.json`), one syntax highlighter chosen in WP-00. Anything else: ask first.
- Tests: `swift test` for packages. UI changes include SwiftUI previews for outer, inner portrait, inner landscape and half-fold, plus snapshot tests where the WP says so.
- Acceptance criteria are literal. If one cannot be met, stop and report. Do not improvise.
- Every acceptance has a **CI gate** (automatic; the WP is not done until green) and a **Manual check** (JT, on CI simulator screenshots or a build on the iPhone; short checklist in the PR). "—" means none.
- Design choices go to JT first.

## Local checks

```sh
swift format lint --strict -r Sources Tests App   # Swift 6.x toolchain
swift build && swift test
```

macOS-only (CI runs these): `swiftlint --strict`, `xcodegen generate`, `xcodebuild test`.

## Style

- Swift 6, structured concurrency, one `actor` per connection, `@Observable` view models on the main actor.
- `HermesKit` and `HermesSSH` must not import UIKit, SwiftUI or Combine.
- `swift-format` (`.swift-format`) is the formatter; `swiftlint` is the linter.

## Models

- Sonnet 5.5 for WPs tagged [S] in the plan; Haiku 5.5 (max effort) for [H].
