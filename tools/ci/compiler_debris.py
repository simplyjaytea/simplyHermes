"""Recognises the stray files the Swift compiler writes into the package root (tools/ci/prepush.sh removes them).

The compiler writes files with binary or one-letter names, which real project files never have. A file is debris when
its name has a byte outside printable ASCII, or when it has no dot and is at most two characters long. Any other
untracked file in the root is the developer's, and the sweep leaves it alone.
"""

from __future__ import annotations


def is_compiler_debris(name: bytes) -> bool:
    if not name or b"/" in name:
        return False
    if any(byte < 0x20 or byte > 0x7E for byte in name):
        return True
    return b"." not in name and len(name) <= 2
