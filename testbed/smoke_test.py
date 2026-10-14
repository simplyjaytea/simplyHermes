#!/usr/bin/env python3
"""Testbed smoke test (WP-03 CI gate): /api/status, login, /api/ws chat turn, SSH.

Run after `scripts/up.sh`:  python3 testbed/smoke_test.py   (needs `pip install websockets`)"""
import asyncio
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "tools"))
from hclient import Gateway  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


async def chat_turn(gw):
    rpc = await gw.connect()
    ready = await rpc.recv()
    assert ready["params"]["type"] == "gateway.ready", ready
    caps = await rpc.call("client.capabilities", {"server_requests": True})
    assert "result" in caps, caps
    created = await rpc.call("session.create", {})
    sid = created["result"]["session_id"]
    sub = await rpc.call("prompt.submit", {"session_id": sid, "text": "hello [[scenario:text]]"})
    assert "result" in sub, sub
    done = await rpc.until_event("message.complete", timeout=90)
    text = done["params"]["payload"].get("text") or str(done["params"]["payload"])
    assert "fake LLM" in text, done
    await rpc.close()


def main():
    gw = Gateway()
    status, body = gw.request("GET", "/api/status")
    assert status == 200 and body.get("auth_required") is True, (status, body)
    print("ok /api/status auth_required")

    status, _ = gw.request("GET", "/api/sessions")
    assert status == 401, f"unauthenticated /api/sessions should be 401, got {status}"
    gw.login()
    status, _ = gw.request("GET", "/api/sessions")
    assert status == 200, status
    print("ok login + authenticated REST")

    asyncio.run(chat_turn(gw))
    print("ok /api/ws chat turn")

    key = os.path.join(HERE, "data", "ssh", "id_ed25519")
    out = subprocess.run(
        ["ssh", "-i", key, "-p", "2222", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
         "-o", "BatchMode=yes", "tester@127.0.0.1", "hermes --version"],
        capture_output=True, text=True, timeout=60)
    assert out.returncode == 0 and "Hermes" in out.stdout, (out.returncode, out.stdout, out.stderr)
    print("ok ssh + hermes on PATH:", out.stdout.splitlines()[0])


if __name__ == "__main__":
    main()
