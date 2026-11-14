# simplyHermes: autonomous operating plan (approved by the user 2026-11-02)

Goal: the team ships the reliability plan and the next features without waiting on the user, and stops only for decisions that only the user can make.

## 1. Who does what
| Role | Owner | Standing job |
|---|---|---|
| Dispatch, board, reports | Janet | Keeps `eng_tasks` true, dispatches the next ready task, unblocks handoffs, posts digests |
| Architecture, review, merge | Gilfoyle | Reviews every PR, keeps CI green, merges on the gate below, gives routine work to Dinesh |
| Implementation | Dinesh | One work package (WP) at a time, each in its own worktree and PR |
| UX and feature specs | Poppy | Specs and UI review for user-facing WPs (WP-8 status pill, WP-10, next features) |
| QA | Moss | Independent check of each user-facing PR before merge; writes the device test scripts |

## 2. Merge gate (no user input needed when all pass)
1. All 4 CI jobs green on the PR head (Changed files, Packages Linux, Testbed smoke, App simulator). A known infra or flaky failure gets one rerun, never an admin override.
2. Gilfoyle review: approved, no open findings at "major" or above.
3. User-facing change: Moss's report on that head shows no FAIL. Plan rule: Linux evidence alone never counts as "fixed" for device behavior.
4. Merge commit, no force-push to main. Board row updated with the merge SHA.

## 3. Work order
Lane A, Dinesh (serial, because they touch `LiveChatModel`/`LiveChatScreen`):
1. PR #99 merge (in CI now)
2. WP-7 standalone local chats (PR #100, stacked on #99)
3. WP-8 status pill and mode UI (Poppy reviews the UI)
4. WP-3b durable outbox for files and slash commands, plus deleting the in-memory queue (rows 67, 69)
5. Bugs: createAgent configure failure (61), group draft clearing (62), test junk files (68)

Lane B, independent files (Gilfoyle does these or hands them to Dinesh between Lane A items):
- WP-9 model status and explicit load, then WP-10 use and test
- WP-11 content digest
- WP-12 foreground and network recovery

Lane C, Poppy:
- After #99 merges: Gilfoyle reviews `feature/next-three` (row 64)
- Next features 1, 3, 4, 5 start after WP-8 (they share files)
- Feature 2, the update banner: feed = latest GitHub release of simplyjaytea/simplyHermes (user decision). Independent; can start any time

## 4. Cadence
- Each finished task returns to Janet, who dispatches the next ready task on the board right away.
- A check-in routine every 4 hours: Janet re-reads the board and CI, restarts stalled work, and posts a short digest only when something changed or something needs the user.
- Board hygiene: rows 3-8, 11 and 47 (October tasks) get checked against git and closed or marked stale.

## 5. Stop and ask the user only for
- Device gates. After P0 (WP-1 to WP-5) and P2 (WP-9 to WP-12), the user runs Moss's script on the iPhone with a signed IPA. Janet batches these.
- Product decisions not covered by the fix plan or Poppy's specs.
- Releases, TestFlight or App Store, any public post, spending, secrets or new accounts.
- Destructive git: force-push to main, deleting branches other than merged PR branches, rewriting history.
- A gate that fails twice for the same cause, or a plan change that drops a user rule (no auto-switch, local chats never hit the network, never lose a message, no fake replies).

## 6. Still open from the fix plan (section 4)
Which build is on the phone, iPhone model and iOS version, Apple Intelligence on/off, Signulous memory entitlement, and how the lost message failed. These are needed by the P0 device gate.

## 7. Process additions (proposed by Janet, approved with changes by Gilfoyle, 2026-11-02)
1. **CI watcher.** Anyone who ends a task with CI pending sets their board row to `awaiting-ci`. The evidence starts with `CI: pr=#N run=RUNID sha=SHA |`. A 30-minute routine hands each finished run (on the current head only) back to its owner, with every job's conclusion. Runs on an outdated head are dropped. A GitHub webhook would be better than polling, but it needs repo admin from the user.
2. **One merge candidate on the macOS runner.** The App job runs only on main, on non-draft PRs, or on PRs labelled `ci:app`. Gilfoyle marks the one merge candidate ready. Order for user-facing PRs: review, then ready, then App job and IPA, then Moss QA, then merge. The merge gate requires App = `success` on the head; skipped doesn't count. Timeouts: App 110 min (healthy runs take 62-84 min), Linux 20 min.
3. **Merge train, no rebasing other people's branches.** After each merge, Gilfoyle runs `gh pr update-branch` on the next candidate only (it merges main in, no force-push). The owner resolves conflicts.
4. **Keep main green.** A failed push run on main's head comes before any new merge: one rerun, then triage. A test that flakes twice is quarantined with a board row (owner, cause, end date) and listed in the digest. Tests that guard the user rules are never quarantined. If one fails twice, it goes to the user.
5. **Scripted merge gate.** `tools/ci/merge_gate.sh <PR>`: not a draft, all 4 jobs `success` on the exact head, then `gh pr merge --merge --match-head-commit <sha>`.
6. **Pending user decisions:** Actions write permission for the OpenBot GitHub app (to cancel stale runs), and later the repo-admin webhook.

## 8. Complete control (user, 2026-11-02 05:14Z: "You have complete control")
- Janet decides product questions, approves publishing the update feed and GitHub releases, and settles team disputes. The team escalates to Janet.
- The user still does only what nobody else can: iPhone device tests, spending, secrets, GitHub account permissions, destructive git.
- The four user rules stay fixed. Nobody weakens them.
- Decisions taken under this:
  - Earlier model downloads (pre WP-11) are verified in place at launch ("Checking files from an earlier download."); only mismatched files are deleted and re-fetched. Replaces the first call (full re-download) after Gilfoyle's #101 review, 2026-11-02.
  - Update feed: standing release `app-update-feed`. The app reads the fixed URL `https://github.com/simplyjaytea/simplyHermes/releases/download/app-update-feed/version.json`, so a future full release can't break it.
  - installURL: `https://www.signulous.com/dashboard`. This is the research doc's documented fallback until Signulous offers a per-app install page.
  - The first feed publish is approved once G3 is merged and an alpha IPA exists.
  - Quick actions: "Show chat title in app shortcuts" defaults to on, as Poppy specced.
  - Dinesh's prepush.sh and catalog drift check are approved. Janet creates the weekly drift routine once the script lands.
  - 2026-11-02 ~11:00Z, user decisions after main failed twice on iOS 27.1 runtime loss: (1) CI may fall back to the newest installed iOS 27.x simulator when 27.1 is missing, naming the runtime used; the fallback PR may merge with --red-main-ok as the red-main fix. (2) The user will grant the OpenBot GitHub app Actions: write (rerun/cancel runs).
  - #105 merged during the red-main freeze (parallel Gilfoyle session, 08:39Z). merge_gate.sh now refuses unless main's newest push run is green (PR #107), with --red-main-ok "<approval>" for approved red-main fixes.
  - 2026-11-02 18:3xZ, iPhone batch (Moss's Shared/simplyhermes-device-check-batch1.md): send it to the user only once main is green and #101/#102 are merged. Local-chat steps (6, 7, 12) move to batch 2 with WP-8 (#113), because main has no user-facing way to start a local chat yet.
  - 2026-11-02, #112 tombstone trade-off accepted: tombstone written after the server delete succeeds and swept at launch; the crash window before the write can leave unsent orphan rows, which breaks no user rule.
  - 2026-11-02 correction: the xcode-27 runners are GitHub-hosted. The 27.1 runtime is downloaded per job; if loss continues after #115, the option is to test on preinstalled iOS 27.0 (user's call).
- 2026-11-03 03:55Z, queue drain (user: "merge everything so I can test"): (a) a PR may merge on its own 4/4-green head without update-branch when there is no conflict and no file overlap with what merged since its run; (b) option B approved: while main's push run is pending with Linux/Changed/Testbed green and nothing failed, merge a PR with no file overlap with the pending merge, using --red-main-ok "queue drain, Janet 2026-11-03: main run <id> pending". Never on a red/failed main. If main goes red, stop, revert via PR, return to strict serial. Ends when the queue is drained.
- 2026-11-03 04:20Z, #113 scope: a brand-new (placeholder) chat during an outage shows no pill/banner and keeps its first message in the composer with "not connected" (nothing lost, sent or faked; rules hold). Accepted for WP-8, stated in the PR. Follow-up row new-chat-outage-state (Poppy spec, then Dinesh): pill + banner on placeholders, first message queued and session created on reconnect.
- 2026-11-03 05:00Z, main runs during the drain: ci.yml cancels an in-progress main run on every push, so each merge supersedes the previous main run. A main run cancelled by our own newer merge is superseded, not red; option B checks the newest main run. Any failed (not cancelled) main run stops merges; suspects are all merges since the last green main. User builds come from the green main run that finishes in a merge gap.

## 9. Wind-down (user, 2026-11-03 ~17:10Z)
User: "Stop all the work. Update the playbook with what we need to do still … merge everything, skip any check, just get everything on GitHub." Reason: Hermes is releasing an official app, so continuing may not be worth it. All work is stopped until the user restarts it.

### State at stop
- The CI watcher (60fe5692) and the 4h check-in (bbe572cb) routines are paused (active=false). To restart, turn both back on.
- The last verified build is main push run 41603166344 on 2e59525, 4/4 green. Its artifact `simplyHermes-unsigned-ipa` contains #102 update banner, #112 undo delete and #116 quick actions.
- **Done (Gilfoyle, 2026-11-03 ~17:15Z): every open PR is merged, and none are left open.** The merges used merge commits and skipped the gate, on the user's instruction. No force-push and no admin override were needed.
  - Merge commits: #110 `2437a23`, #106 `5e463f5`, #111 `d4cca9c`, #113 `5298329`, #117 `68cc341`.
  - Main head is `68cc341`. Push run **41682248563** was still running at the stop, and nobody is watching it.
  - The last green build is still 41603166344 (2e59525).
- Known problems that went to main unfixed:
  - **#113 (status pill):** Gilfoyle's delta review at 34818e2 found one major. "Try again" can send a waiting message twice when the same client recovers on its own. Fix: one OutboxDrainer per chat, swap its submitter, no detach when the client is unchanged, a `retrying` flag, and a Linux exactly-once test. Details are in Shared/simplyhermes-pr113-delta-review-34818e2.md, now also posted on the PR (comment 6610589380). Separately, all four StatusPillUITests fail at StatusPillUITests.swift:172 because a new chat never becomes live in the test (run 41607758047). Check ShellModel.swift:311 `startFirstMessage` and `drafts[id]`. Moss reads the Try-again logic as correct in source (PR comment 6604277662).
  - **#111 (local-chat network guard):** App red on run 41601787195 because of the fold test and the AppUpdate About test (:61/:63). Both passed on main 2e59525, so the fails look like test flakiness, not real breakage.
  - **#117 (merged anyway, since the user said everything):** test-only. It re-enables `SSHTunnelIntegrationTests.chatTurnThroughTunnel` early, with per-step logging. #118's deadlines are on main, so a stuck step now fails in about 30 s instead of hanging for 5 minutes. If Testbed goes red on it, re-add the `.disabled` reason.
- Local-only branches are now on GitHub as archives: `archive/feature-next-three` (message actions, an early update banner, a Dynamic Type/VoiceOver pass), `archive/dinesh-alpha3-bugfixes` (REST path encoding, URL credential redaction) and `archive/fix-chat-reliability-pre-rebase` (the pre-rebase WP-1–6 backup). `prep/*` held only merge commits and wasn't pushed.
- Leftover local worktrees in /tmp and Shared/worktrees can be deleted once everything is on GitHub.

### Still to do, if work restarts (in order)
1. Re-verify main after the unchecked merges: get one green push run and fix whatever went red.
2. Fix #113's double send and the StatusPill UI test setup (Dinesh), then Gilfoyle re-reviews and Moss re-checks Try again.
3. Quarantine or fix testFoldMidStreamKeepsSessionScrollAndDraft (row 90) and the AppUpdate About test flake.
4. Dinesh, Lane A: placeholder-server-name (row 107, ShellModel.swift:372 hardcodes "home-server"), then new-chat-outage-state (row 104, Poppy's spec Shared/simplyhermes-new-chat-outage-state-spec-2026-11-03.md), then dropped-chat-pill-watcher (108), then wp11-identity-optional (100).
5. Reliability WP-3b, WP-9, WP-10 and WP-12 (rows 57, 58, 60, 69), and bugs 61, 62, 68, 87, 88 and 98.
6. Poppy: app-update-withdrawn-feed (101), quick-actions-followups (102), undo-delete-followups (99), what's-new (73), new-reply dot (74).
7. Tooling: the #106 m3 one-line catch, then the weekly drift-check routine (exit 1 with no MISMATCH = "couldn't check").
8. 2026-11-09: lift the remaining quarantines: TerminalLiveTests pty, and testsTheTestbedGateway with #119's minors. chatTurnThroughTunnel is already back on main through #117; add Dinesh's debug-log minor for a close that never returns.

### Only the user can do these
- Run the iPhone checklist (Shared/simplyhermes-device-check-batch1.md) on a green main build.
- Grant the OpenBot GitHub app Actions: write.
- Set APP_UPDATE_INSTALL_URL.
- Decide Hermes server dedupe (Shared/hermes-submit-idempotency-proposal.md).
- Decide the iOS 27.0 simulator pin.
- Decide whether to continue at all, given the official app.

## 10. "Merge everything" (user, 2026-11-13 ~03:00Z; repo public since ~02:30Z)
User: "Merge everything." All 32 open PRs (#122–#153) were merged to main by Gilfoyle without the merge gate, CI, re-review or QA, the same as the 2026-11-03 wind-down. Merge commits only, no force-push, no admin override, no squash. Merged PR branches were deleted by the repo setting; archive/*, backup/* and integration/all-2026-11-12 are kept.

### Merge commits (in order)
#123 `b4d2f21` (#122 rode along as `3dc1456`), #144 `8e52447`, #130 `9a5eb67`, #132 `7857258`, #133 `2ad080e`, #149 `aadf8ab`, #124 `4ea590c`, #125 `5fd1b75`, #137 `8d39581`, #126 `3fb2522`, #140 `c6972ba`, #143 `c643aa9`, #142 `d0d2233`, #127 `e41e9b1`, #129 `4305ffc`, #128 `be2d38e`, #141 `58931b3`, #145 `9b62463`, #134 `00ed6d0`, #135 `5878921`, #136 `102a666`, #138 `9cf33d4`, #139 `7259875`, #146 `590d993`, #152 `33f7c29`, #153 `80de37e`, #131 `39d1c60`, #150 `4e72e98`, #151 `a92df7e`, #147 `9cd616c`, #148 `9ad0fda` (main head).

Conflicts were resolved on the PR branch by merging main, with the integration resolutions: #145 (OutboxServices, with #133), #131 (HermesCache migrations, with #145, and the memory migration test bounded to its own migration), #150 (refresh after #131), #147 (OnDeviceModelSelection, with #139). No content was dropped.

### Went to main with known problems (unfixed)
- **#143, major:** a server switch during the new 20 s first-message wait sends the first message through the wrong server (`startChat` captures `active`; the hand-off uses the server active later).
- **#140, major:** dropped chats are retired only on the next `chat(for:)`, so an old chat can still attach to the new server with its old session id.
- **#134, major:** `finishStagedSettings` ignores `result.applied`, so a refused settings write counts as saved.
- **#138, major (guard):** `ConnectionGuard` matches openers after stripping string contents, so an opener inside interpolation or after an escaped quote passes; Moss's bypasses (`URLSession.self` then `.init(`, `ClientBootstrap.self` then `.init(`) also pass. Rows 87/88 aren't closed. The local-chat network rule's source lint is weaker than intended.
- **#136:** the major (demo-only state) was fixed by Poppy in 69c7503 but not re-reviewed. Moss's FAIL stands: notification ids and tap URLs use the session id only, so two servers with the same chat id collide.
- **Lint, 4 swiftlint --strict errors on 9ad0fda:** `GatewayClient` 515 lines (#146), `AdaptiveShell` over 500 (#145 with #125/#126/#137), identifier `up` in `NewChatCoordinatorTests.swift:98` (#145), and `opening_brace` at `ConnectionGuard.swift:80` (#138; fixed only on the integration branch). CI's Linux job passed on 9ad0fda anyway (run 43358771436), but the App job runs `swiftlint --strict` (ci.yml:208), so **the App job will fail on these 4 errors** until they're fixed. Format lint is clean, and 1821 Linux tests pass locally.
- **Minors open:** #123 m1 (connect retries hide a flaky first connect), #126 m1 (placeholder strip on non-placeholder fallback chats), #131 m (see review), #135 m1, #139 m1, #142 m1, #133 residuals (only the newest model hears changes; the registry never forgets).
- **Unproven:** no App job has run on any of this, so every screen and UI test is unproven, including the StatusPillUITests repair, notifications, memory, skills, the two new local models (#152), Acknowledgements (#153), the 20 s wait and the retire wiring.
- **Still off:** `chatTurnThroughTunnel` (until 2026-11-19, row quarantine-ssh-tunnel-chat-turn). #144's per-step deadlines are now on main.
- **Accepted:** a crash after the server took a message resends it (withKnownIssue, no client id).

## 11. Pause (user, 2026-11-14 ~11:40Z)
User: "Let's pause all work and make sure everything is pushed to GitHub. Confirm with me when everything is pushed and merged please." All work stopped. Everything was pushed and merged, without waiting for the iOS job, the same as section 10.

### State at stop
- **PR #155 merged as `0c5d478`** (head `dad7122`). It holds:
  - Repair round 2: the #138 guard scanner, the #133 leftovers, the #140 in-flight attach fix (`ChatAttach`) and the #143 minor.
  - The iOS build fix (Poppy: `ServerChatDelete.commit` runs on its caller's isolation; Dinesh: two app-test compile errors).
  - The UI-test round: Dinesh's `local/fix-ui-signin` (e9e2625) and Poppy's `local/fix-ui-tests-poppy` (5b69e98).
- **Checks on `dad7122`** (PR run 43592515331): Changed files, Packages (Linux) and Testbed smoke passed. The App (iOS) job was still running at merge, so its result is unknown. Locally: strict lint clean, `tools/ci/prepush.sh` passes, 1880 Linux tests (1 known issue).
- **Last iOS result** (run 43495829201 on `b58602e`): the app and both test targets built, and every unit test passed. 55 UI tests ran: 40 passed, 15 failed, 2 skipped. `dad7122` carries fixes for all 15, **unproven on iOS**.
- No PR is open. The board (eng_tasks) is updated.

### Went to main unchecked
- **The 15 UI-test failures and their fixes, none run on iOS:**
  - **"Sign in again" (6 tests: four StatusPill, GitReview, NewReplyDot).** A test-setup problem: the shared sign-in never ticked "Remember password", so the saved test server had no password (Dinesh). Fix: the sign-in ticks it and checks it is on. `WorkspaceUITests` and `NewGroupUITests` were skipped for the same reason; they now run, and may show new failures.
  - **Largest text size (2 tests).** Test problems, plus two real accessibility bugs fixed (Poppy):
    - the approval banner stacks its buttons at those sizes;
    - the quick-action buttons go icon-only, keeping their names for VoiceOver.
    - Still open, in Dinesh's area: the status pill covers the transcript at the largest size.
  - **Quote and Remember this (2 tests).** Test problems. Nothing was sent, and the memory was saved. The tests now assert on what matters.
  - **Sidebar search (1 test).** The CI simulator's narrow window hid the sidebar. Search chats now brings the sidebar to the front.
  - **Local chat after relaunch (1 test, flaky).** A real bug: with no server saved, Welcome hid existing local chats. New `AppEntryRoute` opens the main screen when local chats exist. Row 98, "Modifying state during view update" from the composer's text view, is fixed.
  - The other three of the 15 are retry repeats of these.
- **Dinesh's note:** `ConnectionsModel.secrets(for:)` reads the keychain with `try?`. A keychain read failure therefore looks like "no password" and ends in "Sign in again", and in `silentPasswordLogin` a store error turns into a silent retry loop. Not fixed; board row.
- **Product note:** a password server saved without "Remember password" shows "Sign in again" on every connect and launch. That's by design, but surprising right after a passing connection check. Product call: Janet.
- **Product question (Poppy):** should Welcome offer "Chat on this iPhone", so a new user with no server can start a local chat?
- Minors still open: #123, #126, #135, #139, #145 review gaps; an abandoned attach leaves a listener; the outbox hand-back does nothing for a value-type sender; notifications from before the update aren't recognised once.
- Accepted: a crash after the server took a message resends it.

### Restart to-do (in order)
1. Read the iOS result of main's push run after `0c5d478` (or rerun it). Fix any build error or UI failure. Main is green only with all four jobs passing.
2. Once main is green: record the run id and the unsigned IPA artifact name, and give the build and the 31-step checklist (Shared/simplyhermes-device-check-2026-11-12.md) to the user for the phone.
3. Keychain read handling (Dinesh's note): surface a read failure instead of "Sign in again", and stop the silent retry loop.
4. Status pill covering the transcript at the largest text size (Dinesh).
5. Product calls (Janet): the Remember-password default or hint; Welcome's "Chat on this iPhone"; WP-9 (remove or label the silent fallback to the Apple model).
6. Tunnel test: re-enable with #144's deadlines after 2026-11-19 to find the stalling step (SSH library or test sshd).
7. The open minors listed above; rows 69 and 87/88 follow-ups; memory phase 3; per-model tool evaluation; user-added skills.
8. Housekeeping: delete old worktrees and `local/*` branches (all on GitHub now); decide on old CI artifacts.

### Only the user
- On #132, delete the old revisions of the description and of Gilfoyle's review comment (they show the real server address and IP).
- Repo settings: approval for outside collaborators, read-only workflow permissions, secret scanning with push protection, Dependabot alerts.
- Give the OpenBot GitHub app "Actions: write"; set the update banner's install link; say which PR "delete that pr" meant.
- Paid `xcode-27-xlarge` runner, if the free iOS queue is too slow.
