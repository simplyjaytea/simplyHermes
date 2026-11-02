#!/usr/bin/env python3
"""AT-4a(b): no assistant message may be built outside the files that turn real model output into rows.

Every assistant row must come from Hermes (gateway events, reduced in the transcript reducer) or from the on-device
model's answer (the local chat controller). This fails when Release code anywhere else builds an assistant row:
`kind: .assistant` (ShellMessage) or `.assistant(...)` (TranscriptItem content). Code inside `#if DEBUG` (previews,
sample data, UI-test seams) is allowed. Views that only draw an existing message (`MessageBubble(role:)`) are not rows.

Usage: check_assistant_rows.py [ROOT ...]   (default: Sources App/HermesApp)
"""

import pathlib
import re
import sys

# The only Release files allowed to build assistant rows, and why.
PRODUCERS = {
    "Sources/HermesKit/Transcript/TranscriptReducer+Turn.swift",  # gateway events
    "Sources/HermesKit/OfflineChat/OfflineChatController.swift",  # on-device model output
}

ROW = re.compile(r"kind:\s*\.assistant\b|(?<![\w.])\.assistant\(")
PATTERN_MATCH = re.compile(r"\b(case|if case|guard case)\b")


def violations(path: pathlib.Path):
    debug_depth = 0  # how many enclosing #if blocks are DEBUG-only
    stack = []  # one bool per open #if: True when it is a DEBUG-only block
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        code = line.split("//", 1)[0].strip()
        if code.startswith("#if"):
            # Only a condition that requires DEBUG hides code from Release: `DEBUG || X` and `!DEBUG` do not.
            flat = code.replace(" ", "")
            is_debug = re.search(r"\bDEBUG\b", code) is not None and "!DEBUG" not in flat and "||" not in flat
            stack.append(is_debug)
            debug_depth += is_debug
            continue
        if code.startswith("#else") or code.startswith("#elseif"):
            # The other branch of a DEBUG block is Release code.
            if stack and stack[-1]:
                stack[-1] = False
                debug_depth -= 1
            continue
        if code.startswith("#endif"):
            if stack and stack.pop():
                debug_depth -= 1
            continue
        if debug_depth or not ROW.search(code) or PATTERN_MATCH.search(code):
            continue
        yield number, line.strip()


def main(roots):
    repo = pathlib.Path.cwd()
    found = 0
    for root in roots:
        for path in sorted((repo / root).rglob("*.swift")):
            rel = path.relative_to(repo).as_posix()
            if rel in PRODUCERS:
                continue
            for number, text in violations(path):
                print(f"{rel}:{number}: assistant row built outside a model-output producer: {text}")
                found += 1
    if found:
        print(f"::error::{found} assistant row(s) built outside #if DEBUG and outside {sorted(PRODUCERS)} (AT-4a).")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["Sources", "App/HermesApp"]))
