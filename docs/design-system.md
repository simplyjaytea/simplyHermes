# Design system (WP-20)

Code: `Sources/HermesUI/` (`Theme/`, `Components/`, `Gallery/`). Mockups: the "simplyHermes look" design canvas
(https://claude.ai/artifact/NzMVAUk7ivZ6Wpgfr7Yk36).

## Decisions (JT, 2026-10-14)

| Question | Decision |
| --- | --- |
| Q1 visual direction | Pure iOS 27 native: system colors, SF fonts, Liquid Glass |
| Q8 motion and haptics | Rich, with a Reduce Motion fallback for every animation |
| Q10 appearance | Follow system light/dark |
| Chat style | **A · Bubbles**: your messages in accent bubbles, Hermes, tool output and approvals in grey bubbles; docked composer |
| Accent | **System blue**, drawn as `#0068D9` (darker than `#007AFF` so white text reaches 4.5:1); same in light and dark |
| Tent posture | **Glance view**: task title and elapsed time, the pending command in mono, large Stop / Deny / Approve |
| App icon | **Winged bubble**: white bubble with a wing on a blue gradient; dark and tinted variants |

Ask JT before any new design choice.

## Tokens

- **Color** (`HermesColor`): system colors only, plus `accent`. `outgoingBubble` = accent with `onAccent` (white)
  text; `incomingBubble` = `systemGray5`; status dots use `systemGreen` / `systemOrange` / `systemGray`.
- **Type** (`HermesFont`): Dynamic Type text styles in SF Pro; `code` and `codeSmall` are SF Mono for commands,
  paths and tool output. Dynamic Type replaces Desktop's zoom.
- **Metrics** (`HermesMetrics`): 44 pt minimum tap target; bubble radius 20; inner radius 12; card radius 18;
  bubbles keep 56 pt free on the far side.

## Motion (`HermesMotion`)

| Name | Spring | Used for |
| --- | --- | --- |
| `snappy` | 0.3 s, bounce 0.2 | buttons, chips, toggles |
| `bubbleIn` | 0.45 s, bounce 0.3 | a new bubble (move up + fade + scale from its corner) |
| `gentle` | 0.5 s, bounce 0.1 | fold/unfold, sheets, preview rail |
| `press` | 0.2 s, bounce 0.4 | button press scale (0.96) |

With Reduce Motion on, every animation becomes `reducedFade` (0.15 s ease) and nothing moves or scales.
`\.hermesReduceMotion` overrides the system value for previews and tests (`nil` follows the system).
Streaming: `TypingIndicator` (bouncing dots) before text arrives, `StreamingCaret` (pulsing accent capsule) while
it streams. Per-token effects and incremental markdown belong to the transcript (WP-30).

## Haptics (`HermesFeedback`, via `sensoryFeedback`)

| Moment | Feedback |
| --- | --- |
| send | soft impact, 0.7 |
| stream started | soft impact, 0.4 |
| approval needed | warning |
| approved / turn complete | success |
| denied | medium impact |
| error | error |
| chip selection | selection |

## Components

`MessageBubble`, `ToolOutputBubble`, `ApprovalBubble`, `TypingIndicator`, `StreamingText`, `StreamingCaret`,
`HermesButtonStyle` (primary, secondary, tinted, destructive), `HermesChip`, `HermesCard`, `HermesSheetHeader` +
`.hermesSheet` (medium and large detents), `StatusStrip` (Liquid Glass capsule), `Composer`.
`ComponentGallery` shows them all; the app links to it from the start screen.

## Postures

`DuoPreviewPosture` gives preview and snapshot sizes: outer 466×678, inner portrait 626×890, inner landscape
890×626, half-fold 890×313. These are estimates (pixels ÷ 3) until WP-02 measures the real point sizes.
Layouts per posture (WP-21): outer = chat-first Simple mode with a tab bar; inner portrait = sidebar + chat;
inner landscape = sidebar + chat + preview rail; half-fold = transcript on top, composer and quick actions
(Approve, Deny, Stop, Voice, Attach, Terminal) below; tent = glance view.

## Snapshot tests

`App/HermesAppTests/ComponentGallerySnapshotTests.swift` renders the gallery in every posture × light/dark ×
Reduce Motion on/off (16 images). Nobody has a Mac, so references are recorded on CI: a missing reference is
recorded and the test passes, an existing one must match (perceptual precision 0.98). Images go to
`build/shots/gallery/` and the test result. To lock references, commit the PNGs from a CI run into
`App/HermesAppTests/__Snapshots__/ComponentGallery/`.

## App icon

`App/HermesApp/Assets.xcassets/AppIcon.appiconset`: 1024 px light, dark and tinted PNGs, rendered from the
winged-bubble SVG on the design canvas.
