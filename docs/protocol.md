# Hermes dashboard protocol (WP-01)

What simplyHermes talks to, as found by reading the upstream source and recording traffic from the testbed. Read this before writing client code.

Labels: **[V]** verified live against the testbed. **[S]** read from upstream source or the generated contract, not exercised. **[D]** from the public docs only. Anything not labeled is a statement about the files in this repo.

## 0. What this is based on

- Upstream commit `d97007c32d6340f7ba79ac1dfb5773cc00846448` (NousResearch/hermes-agent, 2026-10-13), the same commit the testbed builds (`testbed/hermes/Dockerfile`). `hermes --version` reports `vgit.d97007c (2026.9.24)`.
- **PyPI `hermes-agent` 0.19.0 (2026-07-20) is too old.** It has no `client.capabilities`, `gateway.capabilities`, `session.events.since`, `ping` or `groups.*`. [V] The docs describe the newer behavior. Do not test against PyPI.
- Machine-readable contracts, committed here:
  - `docs/protocol/gateway-contract.openrpc.json`: OpenRPC for the whole WebSocket protocol, generated upstream from Python models (257 methods, 16 server-to-client requests, 77 notifications, 774 schemas). Copied from `apps/shared/src/gateway-contract.openrpc.json` at the commit above. **This is the source of truth for params and results.** Use it for model generation (WP-10).
  - `docs/protocol/dashboard-openapi.json`: OpenAPI of the REST surface (300 paths), fetched from the running testbed dashboard. **`/openapi.json` exists**, so WP-12 can generate the REST client. [V] It needs a logged-in session on a gated server.
- Reference client (TypeScript, upstream `apps/shared/src/json-rpc-gateway.ts`, `json-rpc-channel.ts`, `reconnect-backoff.ts`). Its reconnect, replay and heartbeat rules are copied below.
- Fixtures: `Fixtures/*.jsonl` (see section 11). Coverage list: `docs/protocol/coverage.json`.

## 1. Surfaces

| Surface | Start | Notes |
|---|---|---|
| Headless backend | `hermes serve [--host H] [--port P\|0] [--isolated]` | JSON-RPC over WebSocket plus REST. No SPA (`GET /` answers a one-line HTML stub). [V] |
| Dashboard | `hermes dashboard` | Same API plus the web UI. Both commands exist; docs use both names. |

The client targets either; `serve` is what Desktop spawns for SSH. Endpoints used:

- `GET /api/status` (public): `version` is **`"unknown"` on git installs** [V]. Use `release_date` (`"2026.9.24"`), `config_version` / `latest_config_version`, `auth_required`, `profiles`, `gateway_running`. The RPC `session.create` result carries `info.desktop_contract` (integer, `8` here) [V]; use it as the protocol-compat number. Minimum-version checks (plan section 3) should key on `desktop_contract` and `gateway.capabilities`, not `version`.
- `WS /api/ws`: JSON-RPC (section 4).
- `WS /api/pty`: terminal (WP-61). [S]
- REST under `/api/...`: see OpenAPI. Many routes take `?profile=<name>`. [S]

**Base URL with a path prefix** (reverse proxy): the server learns the prefix from `X-Forwarded-Prefix`; the operator must set `HERMES_DASHBOARD_PUBLIC_URL`. [S] Clients join every path onto the base URL (`wss://host/prefix/api/ws`).

## 2. Authentication

Two mutually exclusive modes, chosen by the server's bind address. `GET /api/status` → `auth_required` tells which. [V]

### 2.1 Loopback bind (SSH mode)
- No login. A per-process **session token** protects the API. [V]
- REST: header `X-Hermes-Session-Token: <token>` or `Authorization: Bearer <token>`. Missing token → `401`. [V]
- WebSocket: `?token=<token>` query. Wrong or missing → **HTTP 403 at the upgrade** (no WebSocket, no close code). [V]
- Host guard (REST only, DNS-rebinding defense): any loopback name is accepted, port ignored (`127.0.0.1`, `127.0.0.1:1`, `localhost:N`, `[::1]:N` all `200`); any other `Host` → `400 {"detail":"Invalid Host header..."}`. [V] **The plan's "rewrite Host to the remote port or `/api/ws` closes 4403" is wrong for this build**: through an in-app forwarder, `URLSession` sends `Host: 127.0.0.1:<local port>` and that is accepted. No Host rewriting is needed unless the user types a non-loopback hostname.
- WebSocket Host is **not checked**; **`Origin` is**: a foreign `Origin` → HTTP 403. [V] `URLSessionWebSocketTask` sends no `Origin`; never set one.

### 2.2 Non-loopback bind (gateway mode)
- Auth gate on; needs a provider: `basic`, `nous` (OAuth), or `self-hosted` OIDC. `GET /api/auth/providers` → `{"providers":[{"name","display_name","supports_password"}]}`. [V]
- **Basic**: `POST /auth/password-login` with JSON `{"provider":"basic","username","password","next":""}` → `{"ok":true,"next":...}` and `Set-Cookie` session cookies. [V] Wrong credentials `401`; **rate limit 10 attempts per 60 s per IP → `429`** [V] (so silent re-login must back off and never loop). Cookies refresh transparently server-side (access TTL 12 h default, refresh 30 days). [S] Sessions are stateless HMAC tokens; they survive restarts only when `HERMES_DASHBOARD_BASIC_AUTH_SECRET` is set. [S]
- Unauthenticated API calls: `401`; `GET /openapi.json` returns the login HTML with `200` (do not treat `200` as success without checking content type). [V]
- `GET /api/auth/me` → `{"user_id","email","display_name","org_id","provider","expires_at"}`. [V]
- **WS ticket**: `POST /api/auth/ws-ticket` (cookie-authenticated) → `{"ticket":"<43 chars>","ttl_seconds":30}`. Single use, 30 s. Connect with `wss://host[/prefix]/api/ws?ticket=<ticket>`. [V] Mint a fresh ticket before every connect and every reconnect.
- **Failure shape**: a bad, reused, expired or missing ticket gives **HTTP 403 at the upgrade** [V]. The upstream code calls `close(4401)` / `close(4403)` *before* accepting, which Starlette turns into the 403 response, so **a client never sees close codes 4401/4403 on this build**. [S] Plan section 2.2's "4401 → re-mint, 4403 → misconfigured" cannot be implemented as written. Do this instead: on upgrade 403, mint a new ticket and retry once; if it fails again, first call `GET /api/auth/me` (401 → "sign in again"; 200 → "proxy or Origin/Host blocked the socket; check `HERMES_DASHBOARD_PUBLIC_URL`"). Keep handling real close codes anyway (4404 chat disabled, 4408 peer not allowed, 4400 bad request) in case a proxy or later version accepts first. [S]
- Native PKCE (`/auth/native/*`) and OIDC are documented [D][S] but **not exercised here** (the testbed has the optional Dex service, untested). WP-13 owns that.
- In gated mode a foreign `Origin` with a valid ticket was **accepted** [V]; only the loopback bind rejects it. Still never send `Origin`.
- The server pings WebSocket frames every 20 s on non-loopback binds (not on loopback). [S] `URLSession` answers pings automatically.

## 3. Wire format [V]

- One JSON object per WebSocket **text** frame, JSON-RPC 2.0. Server-side the frame is trimmed; no newline needed.
- Client request: `{"jsonrpc":"2.0","id":"<string|int>","method":"...","params":{...}}`. Params models reject unknown keys (error `4000`/`4004`), so send only documented keys.
- Success: `{"jsonrpc":"2.0","id":...,"result":{...}}`. Failure: `{"jsonrpc":"2.0","id":...,"error":{"code":N,"message":"...","data"?:{}}}`. **Application errors use codes 4xxx** (not `-32xxx`). Unknown method: `-32601` (`"unknown method: x"`); parse error `-32700` (id `null`); internal `-32603`.
- **Events** are notifications: `{"jsonrpc":"2.0","method":"event","params":{"type":"<name>","session_id":"<live id>","payload":{...},"seq":<int>}}`. `session_id` is `""` and `seq` absent for global events (`sessions.changed`). `seq` is a per-session, per-server-process counter.
- **Server-to-client requests** look like requests: `{"jsonrpc":"2.0","id":"srq-<hex>","method":"approval","params":{...}}`. The client answers with a response carrying the same `id`. Unimplemented ones must answer `-32601` so the agent fails fast. A handler that throws answers `-32603`. [S]
- Streaming deltas (`message.delta`, `reasoning.delta`, `thinking.delta`) are coalesced server-side to ~30 fps batches; each is still its own frame. [S]
- Session ids: **`session_id` in events and most params is the short live id** (8 hex, e.g. `9f365736`). `session.create` also returns `stored_session_id` (`20261014_030939_cf35cb`), the durable id. **`session.activate` takes the live id; `session.resume` takes the stored id** (the other one fails with `4001` / `4007 "session not found"`). [V]

## 4. Connection lifecycle [V unless marked]

1. Open the socket. First frame (no request needed): event `gateway.ready`, payload `{skin, change_events: bool, replay_epoch: "<hex>", heartbeat: true}`. `skin` is colour tokens; ignore it (fixtures trim it except `handshake.jsonl`).
2. **Immediately send `client.capabilities {"server_requests": true}`.** Result `{"server_requests":[16 names], "declines_not_shown": true}`. Without it approvals are withdrawn. [D][S]
3. Optional: `gateway.capabilities` → `{"per_session_exclusive_submit": true}`. `ping` → `{"pong":true}`. `gateway.ping` → `{"ok":true}`.
4. **Heartbeat**: when `gateway.ready.payload.heartbeat` is true, send `gateway.ping` every **15 s**; if **no inbound frame of any kind** arrives for **45 s**, drop the socket and reconnect. Any inbound frame counts as liveness. [S: reference client]
5. **Reconnect**: full-jitter exponential backoff, base 300 ms, cap 15 s, `random(0, min(cap, base*2^attempt))`. A socket that dies within 5 s of opening counts as a failed attempt (do not reset the ladder). Connect timeout 15 s. [S]
6. **Request timeouts**: 120 s default; `approval.respond` 300 s (matches the server's approval window). [S]

### 4.1 Replay after a drop
- The server keeps a ring of the last **512** events per session. [V: `count=512`]
- After reconnecting, for each session with a watermark call `session.events.since {session_id, last_seen}` → `{events:[...], latest_seq, truncated, count, epoch, open_requests:[...]}`. [V]
- `epoch` equals `gateway.ready.payload.replay_epoch` (a server-process id). If it differs from the last one, the server restarted: clear all watermarks and reload from REST/`session.history`. [S]
- `truncated: true` means the ring overflowed: do **not** paint the gap. Advance the watermark to `latest_seq` and re-read history. [V fixture `catch_up_truncated`]
- Replayed events are the original event objects; mark them `replayed` locally and drop any with `seq <= watermark`. Hold live frames for that session until the replay finishes, then flush them seq-gated. [S]
- `open_requests` re-delivers unanswered server requests (approvals, clarify). Treat them as live but flagged replayed; answering twice is harmless (first wins). [S]

### 4.2 Detached sessions and reaping
- When a socket closes, its sessions are **detached and reaped after a 20 s grace** (`HERMES_TUI_WS_ORPHAN_REAP_GRACE_S`, default 20; sessions with recent activity are kept up to 600 s). Reaping emits `session.reclaimed {session_id, stored_session_id, reason:"ws_orphan_reap"}` to other sockets. [S][V events seen]
- Reconnecting inside the grace and calling `session.resume {session_id: <stored id>}` cancels the reap and re-attaches. After the grace, `session.resume` rebuilds the session from the database (cold attach). Result has `inflight` (the running turn so far), `open_requests`, `running`, `turn_started_at`, `queued`, `pending_approval`. [S]
- iOS consequence: backgrounding for more than ~20 s drops the live agent state; always use `session.resume` with the stored id on foreground.
- `session.active_list` lists live sessions (`id`, `session_key`, `status`, `title`, ...). `session.activate {session_id: <live id>}` re-binds a live session to this socket and returns `info`. [V]

## 5. A turn [V]

`prompt.submit {session_id, text, ...}` → result `{status, user_row_id?}`, `status ∈ streaming | queued | steered | redirected`.

- `streaming`: the turn started; `user_row_id` is the durable row id of the user message.
- `queued`: the session is still finalizing/busy; the prompt was queued server-side and `user_row_id` is absent. Queued prompts surface later in `session.resume.queued`. (Seen if you submit within ~1 s of `message.complete`.)
- `steered` / `redirected`: a prompt sent during a running turn steers or redirects it instead of refusing. [S]

Typical event order for a text turn: `session.info` (model, tools, flags), `message.start`, `session.title` (first turn only, title derives from the first line), `thinking.delta` ×n (**cosmetic spinner text such as "formulating..." or the retry notice; not model reasoning**), `message.delta` ×n (`payload.text`), `reasoning.available` (full text), `message.complete`, `session.info`, `sessions.changed`.

Tool turn adds: `tool.generating {name}`, `tool.start {tool_id, name, context, args}`, `tool.complete {tool_id, name, args, duration_s, result}`, `message.interim {text, already_streamed}`, then more deltas. Subagents: `subagent.start|thinking|progress|tool|complete` with `subagent_id`, `child_session_id`, `delegation_id`, `depth`, `goal`; `delegate_task` returns `status:"dispatched", mode:"background"` and completion arrives later. `subagent.list {session_id}` → `{subagents:[...], delegations:[...]}`. [V]

`message.complete.payload`: `{text, usage:{model,input,output,reasoning,prompt,completion,total,calls,context_used,context_max,context_percent,context_source,compressions,avg_latency_s,avg_tps,active_subagents}, status:"complete", persisted_turn:{row_ids[], complete, user_row_id, final_assistant_row_id}}`. `persisted_turn` gives the durable row ids to cache for rewind. Interrupted turns still end in `message.complete` (partial text, `status` differs). [V]

`session.interrupt {session_id}` → `{status:"interrupted"|"not_interrupted"}`, then `message.complete`. [V]

Provider failures are **not** an `error` event: the agent retries internally and emits `status.update {kind:"lifecycle", text:"⏳ Provider temporarily unavailable — retrying automatically in 18s (cycle 1/5); press Esc to stop"}` with backoff 17 s, 34 s, 70 s... up to 5 cycles. [V] The error card needs to read these `status.update` texts; there is no machine-readable HTTP status or `Retry-After` field. The `error` notification exists for terminal failures [S].

### 5.1 Rewind / edit (`prompt.submit` truncate params) [V]

| Situation | Response |
|---|---|
| `truncate_before_row_id` without `confirm_truncate` | error `4029` |
| `truncate_before_user_ordinal` is a boolean | `4004 "must be an integer"` |
| ordinal **alone** (no row id) | `4004 "ordinal-only truncation is unsafe for durable session history; include truncate_before_row_id"` — **always send the row id** |
| row id and ordinal disagree | `4030` |
| row id not in history | `4018`, `data:{user_turn_count,...}` (no fallback) |
| cut would empty the transcript, no `confirm_empty_truncate` | `4028` |
| valid cut | `{status:"streaming", survivor_user_row_ids:[...], user_row_id}`; rebind cached row ids from `survivor_user_row_ids` |
| `4009` busy | documented [D]; interrupt then retry (not triggered in fixtures) |
| `4033` unconfirmed deep cut | documented as *next release* [D]; **not enforced at this commit** (a 2-turn cut without `confirm_deep_truncate` succeeded). Always send `confirm_deep_truncate` when more than one user turn is archived anyway. |

Params keep `extra="forbid"`: do not send `null` for absent keys the server treats as a value (the recorder sends absent keys only).

## 6. Server-to-client requests [V unless marked]

Declared in `client.capabilities`. Answers:

| Method | Params (key fields) | Answer (`result`) |
|---|---|---|
| `approval` | `session_id, request_id, command, description, pattern_key(s), allow_session, allow_permanent, choices?` | `{choice: "once"\|"session"\|"always"\|"deny", all?: bool}` |
| `clarify` | `session_id, questions:[{qid, question, choices\|null, multi_select}]` (first choice carries "(Recommended)") | `{answers: {<qid>: "<text>"}}`; `clarify.lock {request_id, question_id, answer}` edits one answer of a batch until all are locked [S] |
| `sudo` | `session_id, command` | `{value}` |
| `secret` | `session_id, env_var, prompt, metadata?` | `{value}` [S] |
| `vault.code`, `vault.unlock_prompt`, `vault.save_login`, `display.install.sudo` | see contract | `{value}` or per contract [S] |
| `terminal.read`, `window.read`, `preview.act`, `preview.read`, `tour`, `theme.*`, `setup_beat` | desktop-only | answer `-32601` (do not declare them) |

- Deferring is allowed: the request has a long server deadline (approval 300 s, clarify up to 3600 s). [S]
- **Answering elsewhere**: any socket may answer with `approval.respond {session_id, request_id, choice}` → `{resolved: 1}`; the original socket then receives `request.cancel {id, method, reason}` as an event and must dismiss only the matching card. [V fixture `approval_answered_elsewhere`] Plain JSON-RPC responses to `srq-...` ids work only for the socket that received the request.
- `approval.pending {session_id}` lists approvals still waiting (reconnect polling). [S]
- Requests are sent to the socket that owns the session; a second socket that calls `session.resume` on a live session **takes it over** (the first sees `session.reclaimed`/`sessions.changed`). Plan 2.2's "multiple clients attached to one live session" did not reproduce with `session.resume`; treat one live owner per session. [V]

## 7. Sessions, config, commands (RPC and REST) [V list, S details]

- RPC: `session.create/list/active_list/activate/resume/close/interrupt/history/status/title/usage/compress/branch/steer/undo/delete/archive/set_hidden`, `session.events.since`, `session.context_breakdown`. `prompt.submit/background/btw`. `commands.catalog` → `{pairs:[[ "/new", "desc" ],...], ...}`; `command.resolve`, `command.dispatch`, `slash.exec`. `model.options` → providers with `models`, `capabilities`, `is_current`. `config.get/set/show` (unknown key → `4002`).
- REST (OpenAPI): `/api/sessions` (+`/{id}`, `/{id}/messages`, `/search`, `/export`, `/prune`...), `/api/profiles*`, `/api/config*`, `/api/env`, `/api/cron/*`, `/api/skills*`, `/api/tools/toolsets*`, `/api/mcp/*`, `/api/messaging/*`, `/api/webhooks`, `/api/analytics/*`, `/api/logs`, `/api/system/stats`, `/api/gateway/{start,stop,restart,drain}`, `/api/hermes/update[/check]`, `/api/ops/*`, `/api/files*`, `/api/fs/*`, `/api/chat/workspaces`.
- Attachments: `POST /api/chat/image-upload` is **404 on `hermes serve`** ("web UI disabled") [V]; use RPC `image.attach`, `image.attach_bytes`, `file.attach`, `pdf.attach` (see contract) or `POST /api/files/upload[-stream]`.

## 8. WP-01 questions answered

| Question (plan WP-01) | Answer |
|---|---|
| `/api/ws` speaks the TUI-gateway protocol? | Yes. The WebSocket handler dispatches to the same `tui_gateway.server.dispatch`. [S][V] |
| WS ticket endpoint | `POST /api/auth/ws-ticket` → `{ticket, ttl_seconds:30}`, `?ticket=` on the upgrade. Loopback uses `?token=`. |
| Framing | One JSON-RPC message per text frame. |
| Close codes | Not observable pre-accept; upgrade failures are HTTP 403. See 2.2. |
| Full event list and payloads | Contract: `x-notifications` (77) and `components.schemas`. |
| Server-request payloads | Contract: `x-server-requests` (16). Section 6. |
| Start command | `hermes serve` (headless) and `hermes dashboard`. `--isolated` runs a per-profile server. |
| SSH probe/start and token adoption | Section 9. |
| `/openapi.json` | Present (300 paths). Committed. |
| Bot Mode data paths | Section 10. |
| Workspaces, files, artifacts | `/api/chat/workspaces`, `/api/files*`, `/api/fs/*`, `/api/media`. |
| Kanban | **Exists**: `/api/plugins/kanban/*` (tasks, boards, links, runs, dispatch, ...). WP-55 is unblocked. |
| Git | **Exists**: `/api/git/*` (status, branches, worktrees, `review/{list,diff,stage,unstage,commit,push,revert,create-pr,...}`). WP-62 is unblocked. |
| Profile scoping | `?profile=<name>` on REST; `profile` key in most RPC params. |
| Server version field | `release_date`, `config_version`; `version` is `"unknown"` on git builds; `desktop_contract` in `session.create` info. |

## 9. SSH mode [V]

Upstream Desktop uses the system `ssh` binary with ControlMaster and a spawned `ssh -L` tunnel. simplyHermes uses Citadel and an in-app forwarder (plan 2.4); the remote side is identical. Sequence (all verified in the testbed `sshd` container as a non-root user):

1. Connect with a key (host-key TOFU), run `command -v hermes` / `hermes --version`.
2. Make `~/.hermes/desktop-ssh/<ownershipId>/` with mode `0700`, where `<ownershipId>` is **32 lowercase hex** chars.
3. Write the session token to `~/.hermes/desktop-ssh/<ownershipId>/<nonce>.token`: exactly **64 lowercase hex chars (32 random bytes), no newline, mode `0600`**, owned by the SSH user. `<nonce>` is 16 hex chars. The server refuses anything else (`"contains an invalid token"`) and **deletes the file after reading it**.
4. Start detached: `HERMES_DESKTOP=1 hermes serve --isolated --host 127.0.0.1 --port 0 --ssh-session-token-file <that path> --ssh-owner-nonce <nonce> </dev/null >> <log> 2>&1 &` (use `setsid`/`nohup`; echo `$!`).
5. Read the log until `HERMES_BACKEND_READY port=<n>` (also prints `HERMES_DASHBOARD_READY port=<n>`). Allow up to 120 s on slow hosts (Desktop's default); 45 s minimum.
6. Open a `direct-tcpip` channel to `127.0.0.1:<n>` per forwarded connection.
7. **Served-token adoption**: `GET /` returns an HTML stub containing `window.__HERMES_SESSION_TOKEN__="<token>"`. It equals the uploaded token here. Desktop re-reads it and trusts the served value over its own. Do the same, then use `X-Hermes-Session-Token` on REST and `?token=` on the WebSocket.
8. Reuse across app launches: Desktop records ownership in a lockfile under `~/.hermes/desktop-ssh/<ownershipId>/backend.lock.json` and reaps only servers it can prove it owns (matching `--ssh-owner-nonce` and token path in the process args). `hermes serve --status` lists running servers; `--stop` stops **all** of them (avoid; it would stop other users' servers). v1: always spawn our own `--isolated` server, record the pid, kill it on disconnect.
9. If the remote Hermes predates `--ssh-session-token-file` (`hermes serve --help | grep ssh-session-token-file` fails), show "Update Hermes on the server".

## 10. Bot Mode [S unless marked]

- A Bot is a profile. `profiles.list` → `{profiles:[{name, path, is_default, model, provider, description, display_name, skill_count, last_session, ui_meta?, ...}], bot_mode_protocol: true, install_id}` [V]. `bot_mode_protocol: true` means this backend injects the teammate-messaging protocol.
- Create: `profiles.create {name, description?, clone_from?, clone_all?, soul?, model?, provider?, ...}`; details: `profiles.describe`; edit: `profiles.configure` (carries `ui_meta` with compare-and-swap); assets: `profiles.get_asset/set_asset`.
- `ui_meta` (look, title, model pin, sections, hidden, memberships) travels inside `profiles.list` rows and `profiles.configure`. Contract schemas `ProfileRow`, `ProfilesConfigureParams`.
- Export and import (REST, WP-41, UNTESTED LIVE): `POST /api/profiles/{name}/export` takes `{output, extra_files}`; `POST /api/profiles/import` takes `{archive, name?}`, and the phone sends `archive` as base64. Neither takes `?profile=`. The spec gives no response schema and the archive format is not documented, so the phone reads the export answer as raw bytes or a base64 `archive`/`data`/`base64`/`content` field, and reports a bare `path` as "saved on the server". An import counts as done only when the answer has `ok: true` or a `name`. `ProfileTransferShapeTests` pin these shapes; `ProfileTransferLiveTests` is the live probe that CI's testbed job runs. Until that job passes, both stay untested live.
- `GET /api/status` takes `?profile=` in the spec, but the phone keeps that call unscoped: it is the public probe run before a profile is chosen. `GET /api/profiles/sessions` takes `?profile=` (default `all`) and lists every profile, so the phone never sends the active profile to it. `ProfileRESTScopeTests` lists both as the documented exceptions.
- Rooms (same gateway): `groups.capabilities` → `{protocol_version, driver: bool, persistent_process, authority_gateway_id, room_link, features[], methods[], max_log_limit}`; `groups.create {room_id, name, members:[{member_id, profile, handle}], authority_gateway_id?}` (idempotent); `groups.send {room_id, event_id?, payload:{text, thread_id?}}` (`event_id` makes it idempotent; same id with a different payload → `4111`); `groups.log {room_id, since_seq?, limit?}`; `groups.state`; `groups.stop {room_id}` → `{cancelled}`; `groups.list`, `groups.rename`, `groups.disband`.
- The gateway runs the turns (`driver: true`); closing the client does not stop a room. A room whose authority is another gateway rejects sends with `4111`.
- `groups.promote/demote/replicate/replica_state/peer.*` are replication and split-brain recovery. Never call automatically (plan 2.5).
- `message_agent` delivery states are agent-tool results, not RPC (they appear in `tool.complete.result`).
- Fixture `bot_and_group_room.jsonl` records the room flow if the fake LLM could drive it; see its `index.json` entry for what happened.

## 11. Fixtures

`Fixtures/<name>.jsonl`, one JSON object per line: `{"i": n, "dir": "in"|"out", "ms": n, "frame": {...}, "socket"?: "A"|"B"}`. `in` is server to client, `out` is client to server. Frames are verbatim except `gateway.ready.payload.skin`, which is replaced by `{"_trimmed": true}` everywhere except `handshake.jsonl`. `Fixtures/index.json` lists, per fixture, its description, run status, the methods/events/requests it contains and notes about what happened.

Re-record: `testbed/scripts/up.sh`, then `.venv/bin/python testbed/tools/record_fixtures.py [name...]`. Re-record after bumping `HERMES_REF`.

CI gate: `Tests/HermesKitTests/FixtureLintTests.swift` checks every line is valid JSON-RPC 2.0 and that every name in `docs/protocol/coverage.json` is in a fixture or listed under `gaps` with a reason (and flags stale gaps).

## 12. Known gaps and risks

- **Cron/delegation turns with `display_kind`** (`inflight.display_kind`/`display_metadata`) were not recorded: the scripted LLM cannot trigger a cron turn inside a recording window. Types are in the contract (`InflightTurn`).
- **Secrets other than sudo** (`secret`, `vault.*`) were not triggered. Only `sudo` is recorded.
- **Real-model differences** (plan manual check): fake LLM replies are deterministic and have no reasoning stream, usage numbers are synthetic.
- **Native PKCE / OIDC / `nous`** untested.
- **Kanban and git** endpoints are known only from OpenAPI, not exercised.
- Upstream moves fast (contract `version: "1"`, `desktop_contract: 8`). Pin `HERMES_REF`; re-record and diff the OpenRPC file on each bump.
