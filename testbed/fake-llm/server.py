#!/usr/bin/env python3
"""Scripted OpenAI-compatible LLM for the simplyHermes testbed.

Stdlib only. Serves GET /v1/models and POST /v1/chat/completions (streaming and
non-streaming). Behaviour comes from JSON scenario files in ./scenarios.

Scenario selection, first match wins:
  1. A marker `[[scenario:NAME]]` in the last user message.
  2. The scenario set with POST /__scenario {"name": "NAME"} (sticky).
  3. The scenario named by $FAKE_LLM_DEFAULT (default "text").

A scenario is {"steps": [step, ...]}. The step used for a request is the number of
tool-result messages that follow the last user message (0 for the first LLM call of a
turn, 1 after the first tool result, ...). The last step repeats if the agent keeps going.

A step is one of:
  {"text": "...", "chunk_delay_ms": 10, "chunk_size": 4}
  {"text": "...", "tool_calls": [{"name": "terminal", "arguments": {"command": "echo hi"}}]}
  {"error": {"status": 429, "message": "rate limited", "retry_after": 30}}
  {"repeat_text": "word ", "count": 2000}   # long stream
"""
import json
import os
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIO_DIR = os.environ.get("FAKE_LLM_SCENARIOS", os.path.join(HERE, "scenarios"))
DEFAULT = os.environ.get("FAKE_LLM_DEFAULT", "text")
MODEL = os.environ.get("FAKE_LLM_MODEL", "fake-model")
MARKER = re.compile(r"\[\[scenario:([A-Za-z0-9_\-]+)\]\]")

_state = {"sticky": None, "log": []}
_lock = threading.Lock()


def load_scenario(name):
    path = os.path.join(SCENARIO_DIR, f"{name}.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(p.get("text", "") for p in content if isinstance(p, dict))
    return ""


def pick(messages):
    last_user = -1
    for i, m in enumerate(messages):
        if m.get("role") == "user":
            last_user = i
    name = None
    if last_user >= 0:
        found = MARKER.search(text_of(messages[last_user].get("content")))
        if found:
            name = found.group(1)
    with _lock:
        name = name or _state["sticky"] or DEFAULT
    tool_results = sum(1 for m in messages[last_user + 1 :] if m.get("role") == "tool")
    return name, tool_results


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet
        pass

    def _json(self, status, obj, headers=None):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") in ("/v1/models", "/models"):
            self._json(200, {"object": "list", "data": [{"id": MODEL, "object": "model"}]})
        elif self.path == "/__log":
            with _lock:
                self._json(200, {"requests": _state["log"][-50:]})
        elif self.path == "/health":
            self._json(200, {"ok": True})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return self._json(400, {"error": "bad json"})
        if self.path == "/__scenario":
            with _lock:
                _state["sticky"] = req.get("name") or None
            return self._json(200, {"scenario": req.get("name")})
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._json(404, {"error": "not found"})
        name, step_idx = pick(req.get("messages", []))
        try:
            steps = load_scenario(name)["steps"]
        except (OSError, KeyError, json.JSONDecodeError) as exc:
            return self._json(500, {"error": {"message": f"bad scenario {name}: {exc}"}})
        step = steps[min(step_idx, len(steps) - 1)]
        with _lock:
            _state["log"].append({"scenario": name, "step": step_idx, "stream": bool(req.get("stream"))})
        if "error" in step:
            err = step["error"]
            headers = {}
            if err.get("retry_after") is not None:
                headers["Retry-After"] = str(err["retry_after"])
            return self._json(
                err.get("status", 500),
                {"error": {"message": err.get("message", "scripted error"), "type": err.get("type", "scripted_error")}},
                headers,
            )
        text = step.get("text", "")
        if "repeat_text" in step:
            text = step["repeat_text"] * int(step.get("count", 100))
        calls = [
            {
                "index": i,
                "id": f"call_{uuid.uuid4().hex[:12]}",
                "type": "function",
                "function": {"name": c["name"], "arguments": json.dumps(c.get("arguments", {}))},
            }
            for i, c in enumerate(step.get("tool_calls", []))
        ]
        finish = "tool_calls" if calls else "stop"
        if req.get("stream"):
            self._stream(text, calls, finish, step)
        else:
            msg = {"role": "assistant", "content": text or None}
            if calls:
                msg["tool_calls"] = [{k: v for k, v in c.items() if k != "index"} for c in calls]
            self._json(
                200,
                {
                    "id": "chatcmpl-fake",
                    "object": "chat.completion",
                    "created": int(time.time()),
                    "model": MODEL,
                    "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
                    "usage": usage(text),
                },
            )

    def _stream(self, text, calls, finish, step):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()

        def send(delta, fin=None, extra=None):
            payload = {
                "id": "chatcmpl-fake",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": MODEL,
                "choices": [{"index": 0, "delta": delta, "finish_reason": fin}],
            }
            if extra:
                payload.update(extra)
            data = f"data: {json.dumps(payload)}\n\n".encode()
            self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
            self.wfile.flush()

        send({"role": "assistant", "content": ""})
        size = int(step.get("chunk_size", 4))
        delay = step.get("chunk_delay_ms", 5) / 1000.0
        for i in range(0, len(text), size):
            send({"content": text[i : i + size]})
            if delay:
                time.sleep(delay)
        for c in calls:
            send({"tool_calls": [c]})
        send({}, finish)
        send_usage = {"id": "chatcmpl-fake", "object": "chat.completion.chunk", "created": int(time.time()),
                      "model": MODEL, "choices": [], "usage": usage(text)}
        data = f"data: {json.dumps(send_usage)}\n\n".encode()
        self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n")
        done = b"data: [DONE]\n\n"
        self.wfile.write(f"{len(done):x}\r\n".encode() + done + b"\r\n0\r\n\r\n")
        self.wfile.flush()


def usage(text):
    n = max(1, len(text) // 4)
    return {"prompt_tokens": 100, "completion_tokens": n, "total_tokens": 100 + n}


if __name__ == "__main__":
    host = os.environ.get("FAKE_LLM_HOST", "127.0.0.1")
    port = int(os.environ.get("FAKE_LLM_PORT", "8700"))
    ThreadingHTTPServer((host, port), Handler).serve_forever()
