#!/usr/bin/env python3
"""Record REST answers (WP-53/54/55) from the pinned testbed dashboard.

Usage: testbed/scripts/up.sh --profile oidc && python3 testbed/tools/record_rest.py --out build/rest-fixtures
Stdlib only. Options: --base (default http://127.0.0.1:9119), --spec (default docs/protocol/dashboard-openapi.json),
--upstream (default: ARG HERMES_REF in testbed/hermes/Dockerfile).

  1. Logs in once (the body RESTAuthAPI.passwordLogin sends) and reuses the cookie jar for every later call.
  2. GETs every /api/ operation in the spec except the excluded and forbidden ones. Path and required query
     parameters come from answers already recorded. When nothing resolves, the operation is recorded as skipped
     and not sent.
  3. Seed flows, the only POST/PUT/PATCH/DELETE calls. Each flow names its objects "recorder*", cleans up in a
     finally block, and uses only the writes in SEED_WRITES.

Output is deterministic (sorted keys, 2-space indent, no timestamps): one JSON file per recorded request, named by
method and path, plus index.json. Each file is {"step", "request", "status", "contentType", "body"}. Strings under a
secret key name (REDACT_KEYS) become "<redacted>"; numbers, booleans and null keep their type (see redact()). Exit 1
only when the login fails.
"""
import argparse
import http.client
import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
RECORDER = "testbed/tools/record_rest.py"
DEFAULT_SPEC = os.path.join(REPO, "docs", "protocol", "dashboard-openapi.json")
DOCKERFILE = os.path.join(REPO, "testbed", "hermes", "Dockerfile")
SEED_CONFIG = os.path.join(REPO, "testbed", "hermes", "seed-config.sh")

USER, PASSWORD = "tester", "testbed-password"  # testbed/docker-compose.yml, as in the REST tests
PACING_SECONDS = 0.1
TIMEOUT_SECONDS = 30
MAX_429_RETRIES = 3
MAX_RETRY_AFTER = 60
MAX_TEXT_BYTES = 256 * 1024
REDACTED = "<redacted>"
# Secret names, case-insensitive. Bare "key", "value" and "oauth" are not secret names on their own.
SECRET_NAMES = r"api[_-]?key|secret|token|password|passwd|credential|cookie|authorization|private[_-]?key"
REDACT_KEYS = re.compile(SECRET_NAMES, re.IGNORECASE)
REDACT_TEXT = re.compile(r"(" + SECRET_NAMES + r")([\"']?\s*[:=]\s*)([^\s,;\"'}]+)", re.IGNORECASE)

# Excluded by the testbed rules. A prefix also excludes its bare path (for example /api/files).
EXCLUDED_PREFIXES = ("/api/fs/", "/api/files/", "/api/git/", "/api/media/", "/api/ops/", "/api/local-models/",
                     "/api/audio/speak", "/api/config/raw", "/api/cron/blueprints/instantiate",
                     "/api/chat/image-upload")

# Never sent, with any method. Matched against the path template.
FORBIDDEN = [
    (r"^/api/gateway(/|$)", "forbidden: /api/gateway/*"),
    (r"^/api/ops(/|$)", "forbidden: /api/ops/*"),
    (r"^/api/env/reveal$", "forbidden: /api/env/reveal"),
    (r"^/api/pairing/(approve|revoke|clear-pending)$", "forbidden: pairing writes"),
    (r"^/api/messaging/.+/test$", "forbidden: messaging tests"),
    (r"^/api/providers/oauth/[^/]+/(start|submit|poll)(/|$)", "forbidden: provider OAuth start, submit or poll"),
    (r"^/api/mcp/.+/auth(/|$)", "forbidden: /api/mcp/*/auth"),
    (r"^/api/mcp/oauth/callback/", "not sent: OAuth callback (needs the provider's code and state)"),
    (r"^/api/tools/computer-use/permissions/grant$", "forbidden: computer-use permission grant"),
    (r"^/api/curator/run$", "forbidden: /api/curator/run"),
    (r"^/api/memory/reset$", "forbidden: /api/memory/reset"),
    (r"^/api/memory/provider$", "forbidden: /api/memory/provider"),
    (r"^/api/model/set$", "forbidden: /api/model/set"),
    (r"^/api/skills/hub/(install|uninstall|update)$", "forbidden: skills hub writes"),
    (r"^/api/sessions/(bulk-delete|prune|empty|import)$", "forbidden: session bulk writes"),
    (r"^/api/profiles/import$", "forbidden: profile import"),
    (r"^/api/profiles/[^/]+/export$", "forbidden: profile export"),
    (r"/activate(/|$)", "forbidden: .../activate (never called)"),
    (r"/switch(/|$)", "forbidden: .../switch (never called)"),
    (r"/dispatch(/|$)", "forbidden: .../dispatch (never called)"),
]

# The only writes ever sent, as (method, path template). Each one is sent only inside a seed flow.
SEED_WRITES = {
    ("PUT", "/api/env"),
    ("DELETE", "/api/env"),
    ("POST", "/api/webhooks"),
    ("DELETE", "/api/webhooks/{name}"),
    ("POST", "/api/providers/custom-endpoints"),
    ("POST", "/api/providers/custom-endpoints/validate"),
    ("DELETE", "/api/providers/custom-endpoints/{endpoint_id}"),
    ("POST", "/api/mcp/servers"),
    ("POST", "/api/mcp/servers/{name}/test"),
    ("DELETE", "/api/mcp/servers/{name}"),
    ("POST", "/api/plugins/kanban/boards"),
    ("DELETE", "/api/plugins/kanban/boards/{slug}"),
    ("POST", "/api/plugins/kanban/tasks"),
    ("POST", "/api/plugins/kanban/tasks/{task_id}/comments"),
    ("PATCH", "/api/plugins/kanban/tasks/{task_id}"),
    ("DELETE", "/api/plugins/kanban/tasks/{task_id}"),
    ("POST", "/api/credentials/pool"),
    ("DELETE", "/api/credentials/pool/{provider}/{index}"),
}

# Where a path or required query parameter gets its value: (recorded list answer, fields to read, server-made id).
# A server-made id is shown by its parameter name in file names, so names stay the same from run to run.
SOURCES = {
    "profile": ("/api/profiles", ("name",), False),
    "toolset": ("/api/tools/toolsets", ("name",), False),
    "memory_provider": ("/api/memory", ("name", "provider"), False),
    "skill": ("/api/skills", ("name",), False),
    "session": ("/api/sessions", ("id", "session_id"), True),
    "cron_job": ("/api/cron/jobs", ("id", "job_id"), True),
    "learning_node": ("/api/learning/graph", ("id",), True),
}

# Why a template with no resolvable value is not sent, by path prefix. Other templates get a generic reason.
NOT_RESOLVED = [
    ("/api/plugins/kanban/runs/", "no run id: the seeded task is never dispatched (dispatch is forbidden)"),
    ("/api/plugins/kanban/attachments/", "no attachment id: the seeded task has none"),
    ("/api/messaging/", "no pairing id: onboarding needs a pairing that a person starts"),
    ("/api/actions/", "no action name: the spec does not list actions"),
    ("/api/mcp/oauth/flows/", "no OAuth flow id: no flow is started (OAuth is not driven)"),
]

ENV_KEY = "RECORDER_TEST_VAR"
BOARD = "recorder"
HOOK = "recorder-hook"
ENDPOINT = "recorder-endpoint"
MCP = "recorder-mcp"
PROVIDER = "recorder"
TASK_PATH = "/api/plugins/kanban/tasks/{task_id}"
KANBAN_WITH_TASK = [  # (method, template, step): run only after the seeded task exists
    ("GET", TASK_PATH, "kanban.task.seeded"),
    ("GET", TASK_PATH + "/log", "kanban.log.seeded"),
    ("GET", TASK_PATH + "/attachments", "kanban.attachments.seeded"),
    ("POST", TASK_PATH + "/comments", "kanban.comment"),
    ("PATCH", TASK_PATH, "kanban.update"),
]


class Blocked(Exception):
    """A request the testbed rules forbid. Raised before anything is sent."""


class LoginFailed(Exception):
    """The one login did not return 200."""


def skip_reason(template):
    """Why a path template is never sent, or None."""
    for prefix in EXCLUDED_PREFIXES:
        if template == prefix.rstrip("/") or template.startswith(prefix):
            return f"excluded: {prefix} (testbed rules)"
    for pattern, reason in FORBIDDEN:
        if re.search(pattern, template):
            return reason
    return None


def is_kanban_task(template):
    return template.startswith(TASK_PATH)


def api_get_templates(spec):
    return sorted(path for path, item in spec["paths"].items() if path.startswith("/api/") and "get" in item)


def required_query(spec, template):
    params = spec["paths"][template]["get"].get("parameters", [])
    return [p["name"] for p in params if p.get("in") == "query" and p.get("required")]


def fill(template, values):
    return re.sub(r"\{(\w+)\}", lambda m: urllib.parse.quote(str(values[m.group(1)]), safe=""), template)


def display_path(template, values, dynamic):
    return re.sub(r"\{(\w+)\}", lambda m: m.group(1) if m.group(1) in dynamic else str(values[m.group(1)]), template)


def source_of(template, name):
    if name == "session_id":
        return "session"
    if name == "job_id":
        return "cron_job"
    if template.startswith("/api/profiles/") and name == "name":
        return "profile"
    if template.startswith("/api/tools/toolsets/") and name == "name":
        return "toolset"
    if template.startswith("/api/memory/providers/") and name in ("name", "provider"):
        return "memory_provider"
    if template == "/api/skills/content" and name == "name":
        return "skill"
    if template == "/api/learning/node" and name == "id":
        return "learning_node"
    if template == "/api/sessions/{session_id}/messages/around" and name == "row_id":
        return "message_row"
    return None


LIST_KEYS = ("items", "sessions", "profiles", "toolsets", "skills", "providers", "jobs", "boards", "servers",
             "endpoints", "webhooks", "entries", "nodes", "data", "results")


def items_of(body):
    """The list of records in an answer: the body itself, or the first non-empty list inside it."""
    if isinstance(body, list):
        return body
    if not isinstance(body, dict):
        return []
    lists = [body[k] for k in LIST_KEYS if isinstance(body.get(k), list)]
    lists += [v for k, v in body.items() if isinstance(v, list) and k not in LIST_KEYS]
    for candidate in lists:
        if candidate:
            return candidate
    return []


def first_field(body, *fields):
    for item in items_of(body):
        if isinstance(item, dict):
            for field in fields:
                value = item.get(field)
                if isinstance(value, (int, str)) and not isinstance(value, bool) and value != "":
                    return value
        elif isinstance(item, str) and item:
            return item
    return None


def find_id(node, depth=0):
    """The first "id" in an answer (at the top, or one or two levels down), or None."""
    if not isinstance(node, dict):
        return None
    value = node.get("id")
    if isinstance(value, (int, str)) and not isinstance(value, bool) and value != "":
        return value
    if depth < 2:
        for child in node.values():
            found = find_id(child, depth + 1)
            if found is not None:
                return found
    return None


def id_for_name(body, name):
    for item in items_of(body):
        if isinstance(item, dict) and item.get("name") == name:
            return find_id(item)
    return None


def index_of(body, provider):
    for item in items_of(body):
        if isinstance(item, dict) and item.get("provider") == provider and isinstance(item.get("index"), int):
            return item["index"]
    return None


def lookup(template, name, answers):
    """(value, server_made) for a path or query parameter, from the recorded answers; None when nothing resolves."""
    source = source_of(template, name)
    if source == "message_row":
        for list_template, fields in (("/api/sessions/{session_id}/timeline", ("row_id", "id")),
                                      ("/api/sessions/{session_id}/messages", ("id", "row_id"))):
            value = first_field(answers.get(list_template), *fields)
            if value is not None:
                return str(value), True
        return None
    if source is None:
        return None
    list_template, fields, server_made = SOURCES[source]
    body = answers.get(list_template)
    value = first_field(body, *fields)
    if value is None and isinstance(body, dict):
        value = next((body[f] for f in fields if isinstance(body.get(f), str) and body.get(f)), None)
    return None if value is None else (str(value), server_made)


def not_resolved(template, name):
    for prefix, reason in NOT_RESOLVED:
        if template.startswith(prefix):
            return reason
    source = source_of(template, name)
    if source == "message_row":
        return f"not sent: '{name}' not found in the timeline or messages of the first session"
    if source in SOURCES:
        return f"not sent: '{name}' not found in the recorded {SOURCES[source][0]} answer"
    return f"not sent: no recorded answer gives '{name}'"


def resolve(spec, template, answers):
    """(values, server_made, query, None) for a template, or (None, None, None, reason) when a value is missing."""
    values, server_made, query = {}, set(), {}
    for name in re.findall(r"\{(\w+)\}", template):
        found = lookup(template, name, answers)
        if found is None:
            return None, None, None, not_resolved(template, name)
        values[name], is_server_made = found
        if is_server_made:
            server_made.add(name)
    for name in required_query(spec, template):
        found = lookup(template, name, answers)
        if found is None:
            return None, None, None, not_resolved(template, name)
        query[name] = found[0]
    return values, server_made, query, None


def resolve_ref(spec, schema):
    while isinstance(schema, dict) and "$ref" in schema:
        schema = spec.get("components", {}).get("schemas", {}).get(schema["$ref"].rsplit("/", 1)[-1], {})
    return schema if isinstance(schema, dict) else {}


def warn_schema(spec, method, template, body):
    """Print a warning when a body does not match the spec's request schema. The request is still sent."""
    op = spec["paths"].get(template, {}).get(method.lower(), {})
    content = op.get("requestBody", {}).get("content", {}).get("application/json", {})
    schema = resolve_ref(spec, content.get("schema", {}))
    props = set(schema.get("properties", {}))
    unknown = sorted(set(body) - props)
    missing = sorted(set(schema.get("required", [])) - set(body))
    if unknown or missing:
        print(f"WARN {method} {template}: keys not in the spec schema {unknown}; required but missing {missing}")


def redact(node, hits, hidden=False):
    """A copy of node with secret strings replaced, keys and shape kept. A key matching REDACT_KEYS hides the strings
    below it: a non-empty string becomes "<redacted>", while numbers, booleans and null keep their type. Objects and
    lists keep their shape and are walked. An env-style "value" is hidden only when its object's "key" or "name"
    matches REDACT_KEYS. Matched key names are added to hits."""
    if isinstance(node, dict):
        env_secret = any(isinstance(node.get(k), str) and REDACT_KEYS.search(node[k]) for k in ("key", "name"))
        out = {}
        for key, child in node.items():
            name = str(key)
            matched = bool(REDACT_KEYS.search(name)) or (name.lower() == "value" and env_secret)
            if matched:
                hits.add(name)
            out[key] = redact(child, hits, hidden or matched)
        return out
    if isinstance(node, list):
        return [redact(child, hits, hidden) for child in node]
    if hidden and isinstance(node, str) and node:
        return REDACTED
    return node


def scrub_text(text):
    return REDACT_TEXT.sub(lambda m: m.group(1) + m.group(2) + REDACTED, text)


def content_type(headers):
    return (headers.get("Content-Type") or "").split(";")[0].strip().lower()


def parse_body(mime, raw):
    """The parsed JSON answer, or {"text": ...} (scrubbed, capped) when the answer is not JSON."""
    text = raw.decode("utf-8", errors="replace")
    if "json" in mime or text.lstrip()[:1] in ("{", "["):
        try:
            return json.loads(text)
        except ValueError:
            pass
    if len(raw) > MAX_TEXT_BYTES:
        return {"text": scrub_text(raw[:MAX_TEXT_BYTES].decode("utf-8", errors="replace")), "truncated": True}
    return {"text": scrub_text(text)}


def retry_after_seconds(headers):
    try:
        return max(0.0, float(headers.get("Retry-After", 1)))
    except (TypeError, ValueError):
        return 1.0


def is_success(status):
    return status is not None and 200 <= status < 300


def dump(obj):
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def fake_llm_url():
    """The fake LLM URL seed-config.sh gives the dashboard (FAKE_LLM_URL overrides it)."""
    if os.environ.get("FAKE_LLM_URL"):
        return os.environ["FAKE_LLM_URL"]
    with open(SEED_CONFIG, encoding="utf-8") as f:
        match = re.search(r"\$\{FAKE_LLM_URL:-([^}]+)\}", f.read())
    return match.group(1) if match else "http://fake-llm:8700/v1"


def read_upstream(path):
    with open(path, encoding="utf-8") as f:
        match = re.search(r"^ARG HERMES_REF=(\S+)\s*$", f.read(), re.MULTILINE)
    if not match:
        raise SystemExit(f"no ARG HERMES_REF in {path}")
    return match.group(1)


def clear_previous(out_dir):
    """Remove the files a previous run's index.json lists, and that index. Nothing else in out_dir is touched."""
    index_path = os.path.join(out_dir, "index.json")
    try:
        with open(index_path, encoding="utf-8") as f:
            previous = json.load(f)
    except (OSError, ValueError):
        return
    for entry in previous.get("entries", []):
        name = entry.get("file")
        if name and os.path.basename(name) == name:
            try:
                os.remove(os.path.join(out_dir, name))
            except OSError:
                pass
    os.remove(index_path)


class Client:
    """Cookie-jar HTTP client. login() runs once; every later call reuses the session cookies."""

    def __init__(self, base):
        self.base = base.rstrip("/")
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        self.last_sent = 0.0

    def send(self, method, target, body=None):
        pause = PACING_SECONDS - (time.monotonic() - self.last_sent)
        if pause > 0:
            time.sleep(pause)
        data = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {"Content-Type": "application/json"} if data is not None else {}
        request = urllib.request.Request(self.base + target, data=data, method=method, headers=headers)
        try:
            with self.opener.open(request, timeout=TIMEOUT_SECONDS) as response:
                return response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.headers, error.read()
        finally:
            self.last_sent = time.monotonic()  # the pause counts from the end of each answer

    def call(self, method, target, body=None, retry_429=True):
        status, headers, raw = self.send(method, target, body)
        retries = 0
        while retry_429 and status == 429 and retries < MAX_429_RETRIES:
            time.sleep(min(MAX_RETRY_AFTER, retry_after_seconds(headers)))
            status, headers, raw = self.send(method, target, body)
            retries += 1
        return status, headers, raw


class Recorder:
    def __init__(self, client, out_dir, upstream, spec):
        self.client = client
        self.out_dir = out_dir
        self.upstream = upstream
        self.spec = spec
        self.entries = []
        self.used_names = set()  # lower-cased file names already written
        self.answers = {}  # path template -> parsed body of its first 200 answer (not redacted; used to fill paths)
        self.redacted_keys = set()
        self.in_flow = False

    def login(self):
        body = {"provider": "basic", "username": USER, "password": PASSWORD, "next": ""}
        try:
            status, headers, raw = self.client.call("POST", "/auth/password-login", body, retry_429=False)
        except (OSError, http.client.HTTPException) as error:
            raise LoginFailed(f"{type(error).__name__}: {error}")
        mime = content_type(headers)
        self.record("login", "POST", "/auth/password-login", "/auth/password-login", {}, body, status, mime,
                    parse_body(mime, raw))
        if status != 200:
            raise LoginFailed(f"HTTP {status}")

    def request(self, step, method, template, values=None, server_made=(), query=None, body=None):
        """Send one request and record its answer. Returns (status, parsed body), or (None, None) if no answer came."""
        values = dict(values or {})
        server_made = set(server_made)
        query = dict(query or {})
        if method != "GET" and (not self.in_flow or (method, template) not in SEED_WRITES):
            raise Blocked(f"{method} {template} is not an allowed seed write")
        reason = skip_reason(template)
        if reason:
            raise Blocked(f"{method} {template}: {reason}")
        path = fill(template, values)
        if body is not None:
            warn_schema(self.spec, method, template, body)
        target = path + ("?" + urllib.parse.urlencode(sorted(query.items())) if query else "")
        try:
            status, headers, raw = self.client.call(method, target, body)
        except (OSError, http.client.HTTPException) as error:
            self.skip(step, method, path, f"no answer: {type(error).__name__}: {error}")
            return None, None
        mime = content_type(headers)
        parsed = parse_body(mime, raw)
        if status == 200:
            self.answers.setdefault(template, parsed)
        self.record(step, method, path, display_path(template, values, server_made), query, body, status, mime,
                    parsed)
        return status, parsed

    def record(self, step, method, path, name_path, query, body, status, mime, parsed):
        stem = re.sub(r"[^A-Za-z0-9._-]+", "_", name_path.strip("/").replace("/", "_"))
        name = self.free_name(f"{method}_{stem}", step.rsplit(".", 1)[-1])
        answer = {
            "step": step,
            "request": {
                "method": method,
                "path": path,
                "query": {k: str(v) for k, v in sorted(query.items())},
                "body": None if body is None else redact(body, self.redacted_keys),
            },
            "status": status,
            "contentType": mime,
            "body": redact(parsed, self.redacted_keys),
        }
        with open(os.path.join(self.out_dir, name), "w", encoding="utf-8") as f:
            f.write(dump(answer))
        self.entries.append({"file": name, "step": step, "method": method, "path": path, "status": status})
        print(f"{method} {path} {status}")

    def free_name(self, base, suffix):
        name = f"{base}.json"
        if name.lower() in self.used_names:
            name = f"{base}.{suffix}.json"
        n = 2
        while name.lower() in self.used_names:
            name = f"{base}.{suffix}{n}.json"
            n += 1
        self.used_names.add(name.lower())
        return name

    def skip(self, step, method, path, reason):
        self.entries.append({"file": None, "step": step, "method": method, "path": path, "status": None,
                             "skipped": reason})
        print(f"SKIP {method} {path}: {reason}")

    def run_flow(self, flow):
        self.in_flow = True
        try:
            flow(self)
        finally:
            self.in_flow = False

    def write_index(self, out_dir):
        entries = sorted(self.entries,
                         key=lambda e: (e["file"] is None, e["file"] or "", e["method"], e["path"], e["step"]))
        with open(os.path.join(out_dir, "index.json"), "w", encoding="utf-8") as f:
            f.write(dump({"upstream": self.upstream, "recorder": RECORDER, "entries": entries}))


def seed_env(rec):
    try:
        rec.request("env.set", "PUT", "/api/env", body={"key": ENV_KEY, "value": "recorder"})
        rec.request("env.seeded", "GET", "/api/env")
    finally:
        rec.request("env.delete", "DELETE", "/api/env", body={"key": ENV_KEY})


def seed_webhooks(rec):
    try:
        rec.request("webhooks.create", "POST", "/api/webhooks", body={
            "name": HOOK, "description": "recorder fixture", "events": [], "skills": [],
            "prompt": "recorder fixture", "deliver": "log", "deliver_only": False})
        rec.request("webhooks.seeded", "GET", "/api/webhooks")
    finally:
        rec.request("webhooks.delete", "DELETE", "/api/webhooks/{name}", values={"name": HOOK})


def seed_custom_endpoints(rec):
    body = {"name": ENDPOINT, "base_url": fake_llm_url(), "model": "fake-model", "discover_models": False}
    endpoint_id = None
    try:
        _, created = rec.request("custom-endpoint.create", "POST", "/api/providers/custom-endpoints", body=body)
        endpoint_id = find_id(created)
        _, listing = rec.request("custom-endpoint.seeded", "GET", "/api/providers/custom-endpoints")
        endpoint_id = endpoint_id or id_for_name(listing, ENDPOINT)
        rec.request("custom-endpoint.validate", "POST", "/api/providers/custom-endpoints/validate", body=body)
    finally:
        # The last resort is the name: a wrong id only gets a 404 answer, and nothing else is touched.
        rec.request("custom-endpoint.delete", "DELETE", "/api/providers/custom-endpoints/{endpoint_id}",
                    values={"endpoint_id": endpoint_id or ENDPOINT}, server_made={"endpoint_id"})


def seed_mcp(rec):
    try:
        rec.request("mcp.create", "POST", "/api/mcp/servers", body={"name": MCP, "command": "true", "args": []})
        rec.request("mcp.test", "POST", "/api/mcp/servers/{name}/test", values={"name": MCP})
        rec.request("mcp.seeded", "GET", "/api/mcp/servers")
    finally:
        rec.request("mcp.delete", "DELETE", "/api/mcp/servers/{name}", values={"name": MCP})


def seed_kanban(rec):
    query = {"board": BOARD}
    task_id = None
    try:
        rec.request("kanban.board-create", "POST", "/api/plugins/kanban/boards",
                    body={"slug": BOARD, "name": BOARD, "switch": False})
        rec.request("kanban.seeded", "GET", "/api/plugins/kanban/board", query=query)
        status, created = rec.request("kanban.task-create", "POST", "/api/plugins/kanban/tasks", query=query,
                                      body={"title": "recorder task", "body": "recorder fixture"})
        task_id = find_id(created) if is_success(status) else None
        for method, template, step in KANBAN_WITH_TASK:
            if task_id is None:
                rec.skip(step, method, template, "not sent: the seeded task was not created")
            else:
                rec.request(step, method, template, values={"task_id": task_id}, server_made={"task_id"},
                            query=query, body=kanban_body(step))
    finally:
        if task_id is None:
            rec.skip("kanban.task-delete", "DELETE", TASK_PATH, "not sent: the seeded task was not created")
        else:
            rec.request("kanban.task-delete", "DELETE", TASK_PATH, values={"task_id": task_id},
                        server_made={"task_id"}, query=query)
        rec.request("kanban.board-delete", "DELETE", "/api/plugins/kanban/boards/{slug}", values={"slug": BOARD},
                    query={"delete": "true"})


def kanban_body(step):
    if step == "kanban.comment":
        return {"body": "recorder comment", "author": "recorder"}
    if step == "kanban.update":
        return {"status": "todo"}
    return None


def seed_credentials(rec):
    created, index = False, None
    try:
        status, _ = rec.request("credentials.create", "POST", "/api/credentials/pool",
                                body={"provider": PROVIDER, "api_key": "recorder-key", "label": "recorder"})
        created = is_success(status)
        _, listing = rec.request("credentials.seeded", "GET", "/api/credentials/pool")
        index = index_of(listing, PROVIDER) if created else None
    finally:
        template = "/api/credentials/pool/{provider}/{index}"
        if created:
            rec.request("credentials.delete", "DELETE", template,
                        values={"provider": PROVIDER, "index": 0 if index is None else index})
        else:
            rec.skip("credentials.delete", "DELETE", template, "not sent: the create did not succeed")


SEED_FLOWS = (seed_env, seed_webhooks, seed_custom_endpoints, seed_mcp, seed_kanban, seed_credentials)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Record REST answers from the pinned testbed dashboard.")
    parser.add_argument("--base", default="http://127.0.0.1:9119")
    parser.add_argument("--out", required=True, help="output folder (created if missing)")
    parser.add_argument("--spec", default=DEFAULT_SPEC)
    parser.add_argument("--upstream", help="upstream commit (default: ARG HERMES_REF in testbed/hermes/Dockerfile)")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    upstream = args.upstream or read_upstream(DOCKERFILE)
    with open(args.spec, encoding="utf-8") as f:
        spec = json.load(f)
    os.makedirs(args.out, exist_ok=True)
    clear_previous(args.out)
    rec = Recorder(Client(args.base), args.out, upstream, spec)
    try:
        rec.login()
    except LoginFailed as error:
        print(f"login failed: {error}", file=sys.stderr)
        return 1

    plain, braced = [], []
    for template in api_get_templates(spec):
        reason = skip_reason(template)
        if reason:
            rec.skip("enumerate", "GET", template, reason)
        elif is_kanban_task(template):
            continue  # recorded by seed_kanban, with the task it creates
        elif "{" in template:
            braced.append(template)
        else:
            plain.append(template)
    for template in plain:
        rec.request("enumerate", "GET", template)
    braced.sort(key=lambda t: (t.endswith("/messages/around"), t))  # after the timeline and messages answers
    for template in braced:
        values, server_made, query, reason = resolve(spec, template, rec.answers)
        if reason:
            rec.skip("enumerate", "GET", template, reason)
        else:
            rec.request("enumerate", "GET", template, values=values, server_made=server_made, query=query)
    for flow in SEED_FLOWS:
        rec.run_flow(flow)

    rec.write_index(args.out)
    recorded = sum(1 for e in rec.entries if e["file"])
    skipped = len(rec.entries) - recorded
    errors = sum(1 for e in rec.entries if e["status"] is not None and e["status"] >= 400)
    print(f"recorded {recorded} answers, {skipped} skipped, {errors} with an error status; "
          f"index at {os.path.join(args.out, 'index.json')}")
    print("redacted keys: " + ", ".join(sorted(rec.redacted_keys)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
