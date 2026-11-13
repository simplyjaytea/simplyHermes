#!/usr/bin/env python3
"""Writes Sources/HermesKit/Acknowledgements/acknowledgements.json: every third-party package a built app contains,
with its license text and NOTICE file, for Settings › About › Acknowledgements (board row 132).

Source of the package list: tools/acknowledgements/app-graph.resolved, SwiftPM's exact resolution of the app's own
package set (this package plus project.yml's app-only MLX and swift-transformers packages). Make it with a Swift
toolchain that can read mlx-swift's manifest (6.3 or later; 6.4.2 on Linux works, no Mac needed):

  mkdir /tmp/appgraph && cd /tmp/appgraph   # a Package.swift that depends on this repo by path and on
                                            # project.yml's packages at project.yml's requirements
  cp <repo>/Package.resolved .              # start from the committed lock, so shared packages keep their versions
  swift package resolve && cp Package.resolved <repo>/tools/acknowledgements/app-graph.resolved

Walking manifests by hand over-lists: SwiftPM leaves out dependencies a package only declares behind traits or for
other platforms. Packages not in the lock are still walked from project.yml (APP_ONLY_ROOTS) as a fallback.

Build-time tools that never ship in the app are left out, each with a reason (BUILD_ONLY). Test-only packages too.

Uses the GitHub API through the `gh` CLI (public repositories, no account data). Usage:
  tools/acknowledgements/generate.py [--resolved path/to/Package.resolved] [--check]
--check exits 1 when the committed file differs from what would be written.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Sources/HermesKit/Acknowledgements/acknowledgements.json"
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
TABLE_HEADER = "| Package | License | Used by |"

# Packages in a build that never ship inside the app.
BUILD_ONLY = {
    "swift-syntax": "compiler plugin for mlx-swift-lm's macros; runs at build time only",
    "swift-docc-plugin": "documentation build plugin",
    "swift-snapshot-testing": "tests only",
}

APP_ONLY_ROOTS = [  # project.yml: (url, requirement)
    ("https://github.com/ml-explore/mlx-swift-lm", 'exact: "3.32.3"'),
    ("https://github.com/ml-explore/mlx-swift", 'upToNextMinor(from: "0.32.3")'),
    ("https://github.com/huggingface/swift-transformers", 'exact: "1.3.5"'),
]

PACKAGE_RE = re.compile(r'\.package\(\s*url:\s*"([^"]+)"\s*,\s*([^)]*)\)')


def gh(path: str) -> dict | list | None:
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def slug(url: str) -> str:
    match = re.search(r"github\.com/([^/]+/[^/]+?)/?$", url)
    if not match:
        raise SystemExit(f"not a GitHub URL: {url}")
    return match.group(1).removesuffix(".git")


def identity(url: str) -> str:
    return slug(url).split("/")[1].lower()


def parse(version: str) -> tuple[int, int, int] | None:
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", version)
    return tuple(int(part) for part in match.groups()) if match else None


def tags(repo: str) -> list[tuple[tuple[int, int, int], str]]:
    found = []
    page = 1
    while True:
        batch = gh(f"repos/{repo}/tags?per_page=100&page={page}") or []
        for tag in batch:
            version = parse(tag["name"])
            if version:
                found.append((version, tag["name"]))
        if len(batch) < 100:
            return found
        page += 1


def pick(repo: str, requirement: str) -> str | None:
    """The tag SwiftPM would pick on its own: the newest one the requirement allows. Shared constraints between
    packages are not modelled, so this can be newer than the app's real resolution."""
    bounds = [parse(v) for v in re.findall(r'"(\d+\.\d+\.\d+)"', requirement)]
    if not bounds or bounds[0] is None:
        return None
    low = bounds[0]
    if "exact" in requirement:
        allowed = lambda v: v == low  # noqa: E731
    elif "..<" in requirement and len(bounds) > 1 and bounds[1]:
        high = bounds[1]
        allowed = lambda v: low <= v < high  # noqa: E731
    elif "upToNextMinor" in requirement:
        allowed = lambda v: low <= v < (low[0], low[1] + 1, 0)  # noqa: E731
    else:  # from: up to the next major version
        allowed = lambda v: low <= v < (low[0] + 1, 0, 0)  # noqa: E731
    candidates = [(version, name) for version, name in tags(repo) if allowed(version)]
    return max(candidates)[1] if candidates else None


def tag_for(repo: str, version: str) -> str:
    for candidate in (version, f"v{version}"):
        if gh(f"repos/{repo}/git/ref/tags/{candidate}"):
            return candidate
    raise SystemExit(f"no tag {version} in {repo}")


def file_text(repo: str, path: str, ref: str) -> str | None:
    data = gh(f"repos/{repo}/contents/{path}?ref={ref}")
    if not isinstance(data, dict) or "content" not in data:
        return None
    return base64.b64decode(data["content"]).decode("utf-8", "replace")


def manifest_deps(repo: str, ref: str) -> list[tuple[str, str]]:
    text = file_text(repo, "Package.swift", ref) or ""
    deps = []
    for url, requirement in PACKAGE_RE.findall(text):
        if identity(url) in BUILD_ONLY:
            continue
        tag = pick(slug(url), requirement)
        if tag:
            deps.append((url, tag.removeprefix("v")))
    return deps


def collect(resolved: Path) -> dict[str, dict]:
    pins = json.loads(resolved.read_text())["pins"]
    packages: dict[str, dict] = {}
    queue: list[tuple[str, str, bool]] = []
    for pin in pins:
        version = pin["state"].get("version")
        if version:
            queue.append((pin["location"], version, True))
    for url, requirement in APP_ONLY_ROOTS:
        tag = pick(slug(url), requirement)
        if not tag:
            raise SystemExit(f"no tag for {url} {requirement}")
        queue.append((url, tag.removeprefix("v"), False))
    while queue:
        url, version, exact = queue.pop(0)
        name = identity(url)
        if name in BUILD_ONLY or name in packages:
            continue
        repo = slug(url)
        ref = tag_for(repo, version)
        license_data = gh(f"repos/{repo}/license?ref={ref}") or {}
        license_text = base64.b64decode(license_data.get("content", "")).decode("utf-8", "replace")
        notice = None
        for path in ("NOTICE.txt", "NOTICE"):
            notice = file_text(repo, path, ref)
            if notice:
                break
        packages[name] = {
            "name": repo.split("/")[1],
            "url": f"https://github.com/{repo}",
            "version": version,
            "versionIsExact": exact,
            "license": (license_data.get("license") or {}).get("spdx_id") or "NOASSERTION",
            "licenseText": license_text.strip(),
            "notice": notice.strip() if notice else None,
        }
        if not exact:
            queue += [(dep_url, dep_version, False) for dep_url, dep_version in manifest_deps(repo, ref)]
    return dict(sorted(packages.items()))


def notices_table(packages: dict[str, dict]) -> str:
    """THIRD_PARTY_NOTICES.md with its table rewritten from `packages`, keeping each known row's "Used by" note."""
    text = NOTICES.read_text()
    start = text.index(TABLE_HEADER)
    end = text.index("\n\n", start)
    used_by = {}
    for line in text[start:end].splitlines()[2:]:
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        match = re.search(r"\[([^\]]+)\]", cells[0])
        if match:
            used_by[match.group(1).lower()] = cells[2]
    rows = [TABLE_HEADER, "|---|---|---|"]
    for entry in sorted(packages.values(), key=lambda e: e["url"].lower()):
        repo = entry["url"].removeprefix("https://github.com/")
        license_cell = entry["license"] + (" (has NOTICE)" if entry["notice"] else "")
        note = used_by.get(repo.lower(), "app, through the on-device model packages")
        rows.append(f"| [{repo}]({entry['url']}) | {license_cell} | {note} |")
    for repo in ("pointfreeco/swift-snapshot-testing",):
        rows.append(f"| [{repo}](https://github.com/{repo}) | MIT | tests only |")
    return text[:start] + "\n".join(rows) + text[end:]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--resolved", type=Path, default=ROOT / "tools/acknowledgements/app-graph.resolved")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    data = {
        "_doc": "Generated by tools/acknowledgements/generate.py. Do not edit by hand.",
        "app": {"name": "simplyHermes", "license": "MIT", "licenseText": (ROOT / "LICENSE").read_text().strip()},
        "buildOnly": BUILD_ONLY,
        "packages": collect(args.resolved),
    }
    text = json.dumps(data, indent=1, ensure_ascii=False, sort_keys=True) + "\n"
    notices = notices_table(data["packages"])
    if args.check:
        return 0 if OUT.exists() and OUT.read_text() == text and NOTICES.read_text() == notices else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text)
    NOTICES.write_text(notices)
    print(f"{len(data['packages'])} packages -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
