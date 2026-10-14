"""Minimal Hermes dashboard client used by the testbed smoke test and the WP-01 fixture recorder.

Needs `pip install websockets`. Not shipped in the app."""
import asyncio
import http.cookiejar
import json
import urllib.error
import urllib.request

import websockets


class Gateway:
    """Gated (basic auth) dashboard: cookie login -> REST -> single-use WS ticket."""

    def __init__(self, base="http://127.0.0.1:9119", username="tester", password="testbed-password"):
        self.base = base.rstrip("/")
        self.username, self.password = username, password
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))

    def request(self, method, path, body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(self.base + path, data=data, method=method,
                                     headers={"Content-Type": "application/json"} if data else {})
        try:
            with self.opener.open(req, timeout=20) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, raw.decode(errors="replace")

    def login(self):
        status, body = self.request("POST", "/auth/password-login", {
            "provider": "basic", "username": self.username, "password": self.password})
        assert status == 200, (status, body)
        return body

    def ws_ticket(self):
        status, body = self.request("POST", "/api/auth/ws-ticket")
        assert status == 200, (status, body)
        return body["ticket"]

    async def connect(self, query=None):
        q = query if query is not None else f"ticket={self.ws_ticket()}"
        url = self.base.replace("http", "ws", 1) + "/api/ws" + (f"?{q}" if q else "")
        return Rpc(await websockets.connect(url, max_size=None))


class Rpc:
    """JSON-RPC over an open /api/ws socket. Keeps every inbound frame in `frames`."""

    def __init__(self, ws):
        self.ws = ws
        self.n = 0
        self.frames = []

    async def recv(self, timeout=30):
        frame = json.loads(await asyncio.wait_for(self.ws.recv(), timeout))
        self.frames.append(("in", frame))
        return frame

    async def send_raw(self, obj):
        self.frames.append(("out", obj))
        await self.ws.send(json.dumps(obj))

    async def call(self, method, params=None, timeout=60):
        """Send a request and return its response frame; other frames are kept in `frames`."""
        self.n += 1
        rid = self.n
        await self.send_raw({"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        while True:
            f = await self.recv(timeout)
            if f.get("id") == rid and "method" not in f:
                return f

    async def until_event(self, etype, timeout=60):
        while True:
            f = await self.recv(timeout)
            if f.get("method") == "event" and f["params"].get("type") == etype:
                return f

    async def close(self):
        await self.ws.close()
