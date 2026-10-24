# Alpha known issues

This lists what is not done, what is decided by default, and what has not been checked yet for the first alpha build. It is based on the review of the 34 open PRs (#48 to #81) at their fix-round heads, on top of `main` at 75bb636. PR numbers and states change as PRs merge, so check the PR before you rely on an item.

## Read first

- Nothing in this build has run on an iPhone yet. CI runs unit tests, simulator checks and screenshots. The app target only builds on macOS CI.
- Free-account signing may drop the App Group and the shared Keychain. Widgets, the Share extension and Spotlight depend on them. The app should still run without them. Check this on the first install.
- Report what you find from the app's bug report screen. It files a GitHub issue.
- Alpha releases ship the `.ipa` and its SHA-256 file only. The release job no longer takes simulator screenshots.

## Not in this alpha

| Area | Status |
|---|---|
| Routines pane (WP-44) | Not built. |
| On-device MLX models (#71) | Device only. Waits for the wiring follow-up after #70. |
| MCP, toolset and capability settings (#76) | Held. #76 defines toolset types that #54 also defines, so the app would show two toolset layers if both shipped. Decision pending. |
| Profile import (#72) | Hidden in this build. The import path has not been checked on a live server. The applies-to selector and scope guard ship. |
| Hermes Cloud sign-in (#74) | Built, but hidden until a live check. |
| Action button (WP-63) | Not built. |
| Translations (WP-71) | English only. The VoiceOver pass is not done. |
| Performance pass (WP-70) | Needs a device. |
| Push notifications | Not in v1. Live Activity only. |

## Decisions made by default

These are built as the recommended option. Each can change.

- **Picked slash commands (#48).** They run on the server. An alias runs its target once with the typed arguments. Commands with files attached go out as typed.
- **Read aloud (#50).** It interrupts other apps' audio. Mixing was tried and reverted.
- **Remembered model (#53).** The last model comes back only when the server lists it. Bot and profile chats still get it.
- **Preview size (#66).** Previews download up to 50 MB.
- **New chat (#69).** The server chat is created on the first message. A message sent in a New chat you leave before the server answers waits until that chat opens.
- **Lock Screen titles (#73).** Chat titles are hidden while the phone is locked. There is no generic label.
- **Bubble radius (#81).** 20 pt, to match the chat bubble.
- **Rewind (#58).** The chat is cut with `session.undo` and the text refills the composer.

## Open items by PR

| PR | Area | Open item |
|---|---|---|
| #48 | Slash commands and @ mentions | Japanese input with the completion popover. Alias semantics against a live server. |
| #49 | Edit and regenerate | Event order and the 4018 reload on a live server. |
| #50 | Voice | Read aloud over other audio. Keep-alive across category changes. Microphone while a hold starts. |
| #51 | Terminal | Close-tab confirmation, global tabs, key-row labels. |
| #52 | Composer history and drafts | Undo pill visibility after send. Draft debounce and pruning. |
| #53 | Model picker | Reasoning values and the `provider:model` syntax against a live server. Pill height on device. |
| #54 | Skills, toolsets, plugins | Three minor review items are open. A name with a space or "/" may be double-encoded and return 404. The /update and /activate request bodies are not recorded against a server. The tests use hand-written fixtures. The install prompt says the catalog review does not cover a git URL. That claim is not checked. |
| #58 | Rewind | If `session.history` lags behind `session.undo`, Rewind may never complete. |
| #59 | Export, prune, @session links | Confirmation text. Export file handling. |
| #60 | Tool output preview | Inline transcript card has the same fallback gap. |
| #61 | Workspaces | Filesystem response shapes. |
| #62 | File browser | Going up can leave the workspace root. |
| #63 | Bots | Error code 4022 handling. Avatar colours. Reload triggers. |
| #64 | Cron jobs | Detach, no active server, bot picker, edit prompt. |
| #65 | Workspace picker | Server answer for a deleted folder. |
| #66 | QuickLook | WP-37 UI test never runs in CI. Preview cap needs owner sign-off. |
| #67 | Artifacts | Image share format on a device. The PR body is out of date. |
| #68 | Memory journey | Minor layout and reload items. |
| #69 | New chat | Command palette with the server down. Empty chat cleanup after 20 s. A server switch during chat creation is not handled. |
| #70 | Offline chat | Transcript-text repeat check and cache-file protection not built. |
| #72 | Profiles | Import row hidden in this build. The import path has not been checked against a live server. |
| #73 | Siri, Spotlight, Control Center, Share | Spotlight on the Lock Screen and the Share extension need a device. "Stop all turns" needs an authentication decision. |
| #77 | Messaging, pairing, webhooks | One tap sends one request (simulator check). Telegram QR needs a real channel. |
| #79 | Server control, logs, usage | Gateway status scoping. Baseline window is 60 s here and 120 s in the protocol note. Restart and update need a live server. A `user:password` in a log URL still shows. |
| #80 | Kanban | Done path against a live server. Copy approval. VoiceOver column navigation. |
| #81 | Group rooms | Protocol error codes 4123, 4115, 5116, 5114 and 4112. Pending-action row. |

## Live checks to run on your server or device

- Chat over the gateway and over SSH, including approvals and a long turn with the phone locked.
- Live Activity and the Bots widget on a sideloaded build. The widget shows "Open simplyHermes" if the App Group is dropped.
- Keep bots live (Settings) with the app in the background.
- Settings sections that change server state: providers, messaging, server restart and update.
- Tools tab actions that change server state: skill and plugin install, update and remove, toolset setup, and the skill hub.
- Kanban Done, room history with the app closed, and the posture debug view on each fold posture.
