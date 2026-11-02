#!/usr/bin/env python3
"""Checks the on-device model catalog's pins against the Hugging Face API.

For every model in the catalog it asks the public API for the pinned commit and compares what it finds with the
catalog:

- the commit exists, and the repository lists the pinned files at that commit;
- each file's size matches the catalog's `bytes`;
- for LFS files, the LFS sha256 matches the catalog's `sha256`, and a catalog entry with no sha256 is reported.

Non-LFS files have no sha256 in the API (only a git blob sha1), so only their sizes are compared.

Prints one line per mismatch on stdout and exits 1 when there is any. A summary goes to stderr. Exits 2 when the
catalog cannot be read or the API cannot be reached. It sends no token and no user data: it reads public metadata only.

Usage: tools/ci/check_model_catalog.py [--catalog PATH]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_CATALOG = "Sources/HermesKit/OnDeviceModels/OnDeviceModelCatalog.swift"
API = "https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true"
TIMEOUT_SECONDS = 30

HEX64 = re.compile(r"^[0-9a-f]{64}$")
MODEL_START = re.compile(r"OnDeviceModel\(")
FIELD_ID = re.compile(r'\bid:\s*"([^"]+)"')
FIELD_REPO = re.compile(r'repository:\s*"([^"]+)"')
FIELD_REVISION = re.compile(r'revision:\s*"([^"]+)"')
FILE_ENTRY = re.compile(
    r'OnDeviceModelFile\(\s*"([^"]+)"\s*,\s*([\d_]+)\s*(?:,\s*sha256:\s*"([^"]*)"\s*)?\)'
)


@dataclass
class PinnedFile:
    path: str
    bytes: int
    sha256: str | None


@dataclass
class PinnedModel:
    id: str
    repository: str
    revision: str
    files: list[PinnedFile] = field(default_factory=list)


class CatalogError(Exception):
    pass


def parse_catalog(text: str) -> list[PinnedModel]:
    """Reads the catalog's model entries. Each entry starts at `OnDeviceModel(` and runs to the next one."""
    starts = [m.start() for m in MODEL_START.finditer(text)]
    models: list[PinnedModel] = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(text)
        block = text[start:end]
        ident = FIELD_ID.search(block)
        repo = FIELD_REPO.search(block)
        revision = FIELD_REVISION.search(block)
        if not (ident and repo and revision):
            continue
        model = PinnedModel(id=ident.group(1), repository=repo.group(1), revision=revision.group(1))
        files_at = block.find("files:")
        if files_at < 0:
            continue
        for match in FILE_ENTRY.finditer(block, files_at):
            model.files.append(
                PinnedFile(
                    path=match.group(1),
                    bytes=int(match.group(2).replace("_", "")),
                    sha256=match.group(3) if match.group(3) is not None else None,
                )
            )
        models.append(model)
    if not models:
        raise CatalogError("no model entries found in the catalog")
    return models


def fetch_listing(repo: str, revision: str) -> dict:
    url = API.format(repo=urllib.parse.quote(repo, safe="/"), revision=urllib.parse.quote(revision, safe=""))
    request = urllib.request.Request(url, headers={"User-Agent": "simplyHermes-catalog-check"})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        return json.loads(response.read().decode("utf-8"))


def check_model(model: PinnedModel, listing: dict, problems: list[str], stats: dict) -> None:
    if listing.get("sha") != model.revision:
        problems.append(f"MISMATCH {model.id}: commit {model.revision} not returned for {model.repository}")
        return
    siblings = {s.get("rfilename"): s for s in listing.get("siblings", [])}
    for pinned in model.files:
        stats["files"] += 1
        sibling = siblings.get(pinned.path)
        if sibling is None:
            problems.append(f"MISMATCH {model.id} {pinned.path}: not in {model.repository} at {model.revision}")
            continue
        lfs = sibling.get("lfs")
        size = lfs.get("size") if lfs else sibling.get("size")
        if size != pinned.bytes:
            problems.append(f"MISMATCH {model.id} {pinned.path}: catalog {pinned.bytes} bytes, repository {size}")
        if lfs:
            stats["lfs"] += 1
            if pinned.sha256 is None:
                problems.append(f"MISMATCH {model.id} {pinned.path}: LFS file has no sha256 in the catalog")
            elif not HEX64.match(pinned.sha256):
                problems.append(f"MISMATCH {model.id} {pinned.path}: catalog sha256 is not 64 lowercase hex digits")
            elif lfs.get("sha256") != pinned.sha256:
                problems.append(
                    f"MISMATCH {model.id} {pinned.path}: catalog sha256 {pinned.sha256}, "
                    f"repository LFS sha256 {lfs.get('sha256')}"
                )
        else:
            stats["plain"] += 1


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", default=DEFAULT_CATALOG, help="path to OnDeviceModelCatalog.swift")
    args = parser.parse_args(argv)

    try:
        models = parse_catalog(Path(args.catalog).read_text(encoding="utf-8"))
    except (OSError, CatalogError) as error:
        print(f"check_model_catalog: cannot read the catalog: {error}", file=sys.stderr)
        return 2

    problems: list[str] = []
    stats = {"files": 0, "lfs": 0, "plain": 0}
    for model in models:
        try:
            listing = fetch_listing(model.repository, model.revision)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            print(f"check_model_catalog: cannot read {model.repository} at {model.revision}: {error}", file=sys.stderr)
            return 2
        check_model(model, listing, problems, stats)

    for line in problems:
        print(line)
    print(
        f"check_model_catalog: {len(models)} models, {stats['files']} files "
        f"({stats['lfs']} LFS with sha256 compared, {stats['plain']} non-LFS compared by size), "
        f"{len(problems)} mismatch(es)",
        file=sys.stderr,
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
