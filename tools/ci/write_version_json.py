#!/usr/bin/env python3
"""Writes version.json for the in-app App update banner, checked against the rules AppUpdateChecker applies.

The app ignores a feed it can't trust, so a bad file fails here instead of hiding the banner on every phone:
- version: non-empty string, display only.
- build: whole number above 0, written as a JSON integer (the checker rejects "3").
- installURL: https, on GitHub's release hosts or a host in HermesAppUpdateInstallHosts (project.yml).
- notes: optional; the banner shows the first non-empty line.

Usage: write_version_json.py --version V --build N --install-url URL [--notes TEXT] [--project project.yml] --out FILE
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.parse

# Hosts the checker always accepts (GitHub's release download redirects), plus its default Signulous hosts.
GITHUB_HOSTS = {"github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"}
DEFAULT_INSTALL_HOSTS = {"www.signulous.com", "signulous.com"}


def install_hosts(project: pathlib.Path) -> set:
    """GitHub's hosts plus HermesAppUpdateInstallHosts from project.yml, or the checker's defaults without it."""
    hosts = set(DEFAULT_INSTALL_HOSTS)
    if project.is_file():
        match = re.search(r"^\s*HermesAppUpdateInstallHosts:\s*\"?([^\"\n]*)\"?\s*$", project.read_text(), re.M)
        if match and match.group(1).strip():
            hosts = set(match.group(1).split())
    return GITHUB_HOSTS | hosts


def build_feed(version: str, build: str, install_url: str, notes: str, hosts: set) -> dict:
    """Returns the feed, or raises ValueError naming the field the app would reject."""
    if not version.strip():
        raise ValueError("version is empty")
    if not re.fullmatch(r"[0-9]+", build) or int(build) <= 0:
        raise ValueError(f"build must be a whole number above 0, not {build!r}")
    url = urllib.parse.urlsplit(install_url)
    if url.scheme != "https":
        raise ValueError(f"installURL must use https: {install_url}")
    if (url.hostname or "").lower() not in hosts:
        raise ValueError(f"installURL host {url.hostname!r} is not one the app accepts: {sorted(hosts)}")
    text = notes.strip() or f"simplyHermes {version} is available."
    return {"version": version, "build": int(build), "installURL": install_url, "notes": text}


def main(argv) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--install-url", required=True)
    parser.add_argument("--notes", default="")
    parser.add_argument("--project", default="project.yml")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    try:
        feed = build_feed(args.version, args.build, args.install_url, args.notes, install_hosts(pathlib.Path(args.project)))
    except ValueError as error:
        print(f"::error::version.json not written: {error}")
        return 1
    pathlib.Path(args.out).write_text(json.dumps(feed, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
