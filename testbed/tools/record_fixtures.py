#!/usr/bin/env python3
"""Record protocol fixtures (WP-01) from the testbed dashboard.

Usage: scripts/up.sh && .venv/bin/python testbed/tools/record_fixtures.py [name ...]
Writes Fixtures/<name>.jsonl, one line per frame:
  {"i": <n>, "dir": "in"|"out", "ms": <ms since start>, "frame": {...}}
and Fixtures/index.json (name -> description, methods and events seen).

Scrubs: WS tickets and cookies never appear in frames. gateway.ready's skin is replaced by
{"_trimmed": true} everywhere except handshake.jsonl (it is ~2 KB of colour tokens).
Frames are otherwise verbatim. Ids, timestamps and session ids differ per run.
"""
import asyncio
import json
import os
import sys
import time
import traceback

import websockets

sys.path.insert(0, os.path.dirname(__file__))
from hclient import Gateway, Rpc  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "Fixtures")
SCENARIOS = {}


def scenario(desc):
    def deco(fn):
        SCENARIOS[fn.__name__] = (desc, fn)
        return fn
    return deco


class Recorder:
    """Wraps one or more sockets and logs every frame in order."""

    def __init__(self, keep_skin=False):
        self.t0 = time.monotonic()
        self.lines = []
        self.keep_skin = keep_skin
        self.notes = []

    def log(self, direction, frame, tag=None):
        if (not self.keep_skin and direction == "in" and frame.get("method") == "event"
                and frame["params"].get("type") == "gateway.ready"):
            frame = json.loads(json.dumps(frame))
            frame["params"]["payload"]["skin"] = {"_trimmed": True}
        line = {"i": len(self.lines), "dir": direction, "ms": int((time.monotonic() - self.t0) * 1000), "frame": frame}
        if tag:
            line["socket"] = tag
        self.lines.append(line)

    def note(self, text):
        self.notes.append(text)


class Sock:
    """A recorded socket: send/recv go through the Recorder."""

    def __init__(self, rec, rpc, tag="A"):
        self.rec, self.rpc, self.tag = rec, rpc, tag
        self.n = 0

    async def recv(self, timeout=30):
        f = json.loads(await asyncio.wait_for(self.rpc.ws.recv(), timeout))
        self.rec.log("in", f, self.tag)
        return f

    async def send(self, obj):
        self.rec.log("out", obj, self.tag)
        await self.rpc.ws.send(json.dumps(obj))

    async def call(self, method, params=None, timeout=60):
        self.n += 1
        rid = f"{self.tag}{self.n}"
        await self.send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        while True:
            f = await self.recv(timeout)
            if f.get("id") == rid and "method" not in f:
                return f

    async def until(self, pred, timeout=60):
        while True:
            f = await self.recv(timeout)
            if pred(f):
                return f

    async def event(self, etype, timeout=60):
        return await self.until(lambda f: f.get("method") == "event" and f["params"].get("type") == etype, timeout)

    async def ready(self):
        f = await self.recv()
        assert f["params"]["type"] == "gateway.ready", f
        r = await self.call("client.capabilities", {"server_requests": True})
        assert "result" in r, r
        return f

    async def close(self):
        await self.rpc.ws.close()


async def open_sock(gw, rec, tag="A", ready=True):
    s = Sock(rec, await gw.connect(), tag)
    if ready:
        await s.ready()
    return s


STORED = {}  # live session id -> stored session id (session.resume/activate want the stored id)


async def new_session(s, **params):
    r = await s.call("session.create", params)
    STORED[r["result"]["session_id"]] = r["result"]["stored_session_id"]
    return r["result"]["session_id"]


def is_request(f):
    return "method" in f and "id" in f and f.get("method") != "event"


@scenario("Connect: gateway.ready, client.capabilities, gateway.capabilities, ping, read-only RPCs")
async def handshake(gw, rec):
    rec.keep_skin = True
    s = await open_sock(gw, rec)
    for m in ("gateway.capabilities", "ping", "gateway.ping", "session.list", "commands.catalog", "model.options",
              "profiles.list", "session.active_list", "config.get"):
        await s.call(m, {"key": "model"} if m == "config.get" else {})
    await s.close()


@scenario("One text turn")
async def chat_simple(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "hello [[scenario:text]]"})
    await s.event("message.complete")
    await s.call("session.usage", {"session_id": sid})
    await s.call("session.history", {"session_id": sid})
    await s.close()


@scenario("Turn with a terminal tool call")
async def chat_tool_call(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "run it [[scenario:tool_call]]"})
    await s.event("message.complete")
    await s.close()


async def answer_requests(s, sid, result_for, stop_event="message.complete", timeout=60):
    """Answer server->client requests until stop_event arrives."""
    while True:
        f = await s.recv(timeout)
        if is_request(f):
            await s.send({"jsonrpc": "2.0", "id": f["id"], "result": result_for(f)})
        elif f.get("method") == "event" and f["params"].get("type") == stop_event:
            return f


@scenario("Approval request answered with a JSON-RPC response")
async def approval(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "delete [[scenario:approval]]"})
    await answer_requests(s, sid, lambda f: {"choice": "once"})
    await s.close()


@scenario("Approval denied")
async def approval_denied(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "delete [[scenario:approval]]"})
    await answer_requests(s, sid, lambda f: {"choice": "deny"})
    await s.close()


@scenario("Two sockets; B answers the approval through approval.respond, A gets request.cancel")
async def approval_answered_elsewhere(gw, rec):
    a = await open_sock(gw, rec, "A")
    b = await open_sock(gw, rec, "B")
    sid = await new_session(a)
    await a.call("prompt.submit", {"session_id": sid, "text": "delete [[scenario:approval]]"})
    req = await a.until(is_request)
    rec.note(f"A got request {req['id']} (request_id {req['params'].get('request_id')})")
    r = await b.call("approval.respond", {"session_id": sid, "request_id": req["params"]["request_id"], "choice": "once"})
    rec.note(f"B approval.respond -> {json.dumps(r)[:120]}")
    try:
        await a.until(lambda f: f.get("method") == "event" and f["params"].get("type") in ("request.cancel", "approval.cancelled"), 15)
    except asyncio.TimeoutError:
        rec.note("A saw no request.cancel within 15 s")
    try:
        await a.event("message.complete", 30)
    except asyncio.TimeoutError:
        rec.note("A saw no message.complete within 30 s")
    await a.close()
    await b.close()


@scenario("Clarify request with choices")
async def clarify(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "ask [[scenario:clarify]]"})
    await answer_requests(s, sid, lambda f: {"answers": {q["qid"]: (q["choices"] or ["free text"])[0].replace(" (Recommended)", "")
                                                          for q in f["params"]["questions"]}})
    await s.close()


@scenario("Sudo/secret style request (answered with a value)")
async def sudo(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "sudo [[scenario:sudo]]"})
    seen = []

    def res(f):
        seen.append(f["method"])
        return {"value": "not-a-real-password"}
    try:
        await answer_requests(s, sid, res, timeout=40)
    except asyncio.TimeoutError:
        rec.note("timeout waiting for message.complete")
    rec.note(f"server requests seen: {seen}")
    await s.close()


@scenario("Interrupt a streaming turn")
async def interrupt(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "go slow [[scenario:slow]]"})
    await s.event("message.delta")
    await s.call("session.interrupt", {"session_id": sid})
    try:
        await s.until(lambda f: f.get("method") == "event" and f["params"].get("type") in ("message.complete", "error"), 30)
    except asyncio.TimeoutError:
        rec.note("no terminal event after interrupt within 30 s")
    await s.close()


@scenario("Drop the socket mid-stream, reconnect, catch up with session.events.since and session.resume")
async def drop_and_catch_up(gw, rec):
    a = await open_sock(gw, rec, "A")
    sid = await new_session(a)
    await a.call("prompt.submit", {"session_id": sid, "text": "stream [[scenario:medium_stream]]"})
    last_seq = 0
    for _ in range(25):
        f = await a.until(lambda f: f.get("method") == "event" and f["params"].get("session_id") == sid)
        last_seq = f["params"].get("seq", last_seq)
    rec.note(f"dropping socket A at seq {last_seq}")
    await a.rpc.ws.close()
    await asyncio.sleep(2.0)
    b = await open_sock(gw, rec, "B")
    r = await b.call("session.events.since", {"session_id": sid, "last_seen": last_seq})
    rec.note(f"events.since count={r.get('result', {}).get('count')} truncated={r.get('result', {}).get('truncated')}")
    rr = await b.call("session.resume", {"session_id": STORED[sid]})
    rec.note(f"session.resume(stored id) -> {json.dumps(rr)[:200]}")
    await b.call("session.events.since", {"session_id": rr.get("result", {}).get("session_id", sid), "last_seen": 10**9})
    try:
        await b.event("message.complete", 90)
    except asyncio.TimeoutError:
        rec.note("message.complete not seen after resume")
    await b.close()


@scenario("Catch-up after a long outage: session.events.since reports truncated=true (ring overflow)")
async def catch_up_truncated(gw, rec):
    a = await open_sock(gw, rec, "A")
    sid = await new_session(a)
    await a.call("prompt.submit", {"session_id": sid, "text": "stream [[scenario:long_stream]]"})
    f = await a.until(lambda f: f.get("method") == "event" and f["params"].get("session_id") == sid and f["params"].get("seq"))
    first = f["params"]["seq"]
    await a.rpc.ws.close()
    await asyncio.sleep(25)
    b = await open_sock(gw, rec, "B")
    r = await b.call("session.events.since", {"session_id": sid, "last_seen": first})
    rec.note(f"count={r['result']['count']} truncated={r['result']['truncated']} latest_seq={r['result']['latest_seq']}")
    await b.close()


@scenario("Cold attach to an in-flight turn: session.activate / session.resume return inflight")
async def cold_resume_inflight(gw, rec):
    a = await open_sock(gw, rec, "A")
    sid = await new_session(a)
    await a.call("prompt.submit", {"session_id": sid, "text": "stream [[scenario:slow]]"})
    await a.event("message.delta")
    await a.call("session.status", {"session_id": sid})
    b = await open_sock(gw, rec, "B")
    await b.call("session.active_list")
    await b.call("session.activate", {"session_id": sid})
    await b.call("session.activate", {"session_id": STORED[sid]})
    await b.call("session.resume", {"session_id": STORED[sid]})
    await b.event("message.complete", 60)
    await a.close()
    await b.close()


async def submit_idle(s, sid, text):
    """prompt.submit, retrying while the previous turn is still finalising ('queued')."""
    for _ in range(20):
        r = await s.call("prompt.submit", {"session_id": sid, "text": text})
        if r.get("result", {}).get("status") == "streaming":
            await s.event("message.complete")
            await asyncio.sleep(1.0)
            return r["result"]["user_row_id"]
        await asyncio.sleep(1.0)
    raise RuntimeError("session never became idle")


@scenario("Rewind: prompt.submit with truncate_before_row_id, and each error path")
async def rewind(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    rows = [await submit_idle(s, sid, f"turn {i} [[scenario:text]]") for i in range(3)]
    rec.note(f"user_row_ids {rows}")
    base = {"session_id": sid, "text": "edited [[scenario:text]]"}
    attempts = [
        ("missing confirm_truncate", {**base, "truncate_before_row_id": rows[2]}),
        ("boolean ordinal", {**base, "truncate_before_user_ordinal": True, "confirm_truncate": True}),
        ("ordinal-only (unsafe)", {**base, "truncate_before_user_ordinal": 2, "confirm_truncate": True}),
        ("ordinal and row mismatch", {**base, "truncate_before_row_id": rows[2], "truncate_before_user_ordinal": 0, "confirm_truncate": True}),
        ("stale row id", {**base, "truncate_before_row_id": 99999, "confirm_truncate": True}),
        ("cut to empty without confirm_empty_truncate", {**base, "truncate_before_row_id": rows[0], "confirm_truncate": True}),
        ("ok: deep cut with confirm_deep_truncate", {**base, "truncate_before_row_id": rows[1], "confirm_truncate": True, "confirm_deep_truncate": True}),
    ]
    for label, params in attempts:
        rec.note(f"attempt: {label}")
        r = await s.call("prompt.submit", params)
        if r.get("result", {}).get("status") == "streaming":
            await s.event("message.complete")
            await asyncio.sleep(1.0)
    await s.close()


@scenario("Provider errors: 429 with Retry-After, 500")
async def provider_errors(gw, rec):
    s = await open_sock(gw, rec)
    for name in ("error_500", "error_429"):
        sid = await new_session(s)
        await s.call("prompt.submit", {"session_id": sid, "text": f"x [[scenario:{name}]]"})
        try:
            await s.until(lambda f: f.get("method") == "event" and f["params"].get("type") in ("error", "message.complete"), 45)
        except asyncio.TimeoutError:
            rec.note(f"{name}: no error/complete event in 45 s (agent retries internally)")
        await s.call("session.interrupt", {"session_id": sid})
    await s.close()


@scenario("WebSocket upgrade rejections (HTTP-level; recorded as notes, no frames)")
async def ws_rejections(gw, rec):
    base = gw.base.replace("http", "ws", 1) + "/api/ws"
    cases = [
        ("bogus ticket", f"{base}?ticket=bogus", None),
        ("no credential", base, None),
        ("ticket reuse", None, None),
        ("foreign Origin", f"{base}?ticket={gw.ws_ticket()}", {"Origin": "http://evil.test"}),
    ]
    for label, url, headers in cases:
        if label == "ticket reuse":
            tk = gw.ws_ticket()
            url = f"{base}?ticket={tk}"
            async with websockets.connect(url) as ws:
                await ws.recv()
        try:
            async with websockets.connect(url, additional_headers=headers) as ws:
                await asyncio.wait_for(ws.recv(), 5)
                rec.note(f"{label}: ACCEPTED")
        except websockets.exceptions.InvalidStatus as e:
            rec.note(f"{label}: HTTP {e.response.status_code} at upgrade")
        except websockets.exceptions.ConnectionClosed as e:
            rec.note(f"{label}: closed code={e.rcvd.code if e.rcvd else None}")


@scenario("Subagent: delegate_task (skipped if the fake LLM scenario is missing)")
async def subagents(gw, rec):
    s = await open_sock(gw, rec)
    sid = await new_session(s)
    await s.call("prompt.submit", {"session_id": sid, "text": "delegate [[scenario:delegate]]"})
    await s.event("message.complete", 90)
    await s.call("subagent.list", {"session_id": sid})
    await s.call("spawn_tree.list", {"session_id": sid})
    await s.close()


@scenario("Bot profile + same-gateway group room: profiles.*, groups.capabilities/create/send/log/state/stop/disband")
async def bot_and_group_room(gw, rec):
    s = await open_sock(gw, rec)
    await s.call("profiles.create", {"name": "ops", "description": "Ops bot", "clone_from": "default", "clone_all": True,
                                     "soul": "You are Ops, a terse operations bot."})
    await s.call("profiles.list", {"include_sessions": False})
    await s.call("profiles.describe", {"name": "ops"})
    await s.call("groups.capabilities", {})
    room = f"room-{int(time.time())}"
    await s.call("groups.create", {"room_id": room, "name": "Release room", "members": [
        {"member_id": "default", "profile": "default", "handle": "hermes"},
        {"member_id": "ops", "profile": "ops", "handle": "ops"}]})
    await s.call("groups.list", {})
    r = await s.call("groups.send", {"room_id": room, "event_id": "evt-1", "payload": {"text": "@ops hello [[scenario:text]]", "thread_id": "thread-1"}})
    rec.note(f"groups.send -> {json.dumps(r)[:200]}")
    for _ in range(12):
        await asyncio.sleep(2.0)
        lg = await s.call("groups.log", {"room_id": room, "since_seq": 0})
        n = len(lg.get("result", {}).get("events", []))
        if n >= 3:
            break
    rec.note(f"room log events: {n}")
    await s.call("groups.state", {"room_id": room})
    await s.call("groups.stop", {"room_id": room})
    await s.call("groups.disband", {"room_id": room})
    await s.close()


async def run(names):
    os.makedirs(OUT, exist_ok=True)
    index_path = os.path.join(OUT, "index.json")
    index = json.load(open(index_path)) if os.path.exists(index_path) else {}
    gw = Gateway()
    gw.login()  # once: the dashboard rate-limits password logins to 10 per minute
    for name in names:
        desc, fn = SCENARIOS[name]
        rec = Recorder()
        status = "ok"
        try:
            await asyncio.wait_for(fn(gw, rec), 240)
        except Exception as e:  # keep partial recording; report
            status = f"{type(e).__name__}: {e}"
            traceback.print_exc()
        with open(os.path.join(OUT, f"{name}.jsonl"), "w") as f:
            for line in rec.lines:
                f.write(json.dumps(line, ensure_ascii=False) + "\n")
        methods = sorted({l["frame"]["method"] for l in rec.lines if l["dir"] == "out" and l["frame"].get("method")})
        events = sorted({l["frame"]["params"]["type"] for l in rec.lines
                         if l["dir"] == "in" and l["frame"].get("method") == "event"})
        requests = sorted({l["frame"]["method"] for l in rec.lines
                           if l["dir"] == "in" and "id" in l["frame"] and l["frame"].get("method") not in (None, "event")})
        index[name] = {"description": desc, "status": status, "frames": len(rec.lines),
                       "methods": methods, "events": events, "server_requests": requests, "notes": rec.notes}
        print(f"{name}: {status} ({len(rec.lines)} frames)")
    json.dump(index, open(index_path, "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    asyncio.run(run(sys.argv[1:] or list(SCENARIOS)))
