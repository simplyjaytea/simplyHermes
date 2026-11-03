#!/usr/bin/env python3
"""Checks the on-device model catalog's pins against the Hugging Face hub.

For every model in the catalog it asks the public API for the pinned commit and compares what it finds with the
catalog:

- the commit exists, and the repository lists the pinned files at that commit (a commit that is not there is a
  mismatch, exit 1, not a failed check);
- each file's size matches the catalog's `bytes`;
- for LFS files, the LFS sha256 matches the catalog's `sha256`;
- for non-LFS files, the API has no sha256, so the file is downloaded at the pinned commit and its sha256 is compared
  with the catalog's. The app verifies every file's sha256, so a file the check only sized could pass here and still
  fail on a phone.

A catalog entry with no sha256 is reported. Prints one line per mismatch on stdout and exits 1 when there is any. A
summary goes to stderr. Exits 2 when the catalog cannot be read or the hub cannot be reached. It sends no token and no
user data: it reads public files only.

Usage: tools/ci/check_model_catalog.py [--catalog PATH]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

DEFAULT_CATALOG = "Sources/HermesKit/OnDeviceModels/OnDeviceModelCatalog.swift"
API = "https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true"
RAW = "https://huggingface.co/{repo}/resolve/{revision}/{path}"
USER_AGENT = "simplyHermes-catalog-check"
TIMEOUT_SECONDS = 30
CHUNK = 1 << 16

HEX64 = re.compile(r"^[0-9a-f]{64}$")
MODEL_START = re.compile(r"OnDeviceModel\(")
FIELD_ID = re.compile(r'\bid:\s*"([^"]+)"')
FIELD_REPO = re.compile(r'repository:\s*"([^"]+)"')
FIELD_REVISION = re.compile(r'revision:\s*"([^"]+)"')
FILE_ENTRY = re.compile(
    r'OnDeviceModelFile\(\s*"([^"]+)"\s*,\s*([\d_]+)\s*(?:,\s*sha256:\s*"([^"]*)"\s*)?\)'
)

# Lists the files at a commit: returns the API's JSON, or None when the commit is not in the repository.
ListingFetcher = Callable[[str, str], Optional[dict]]
# Hashes a file at a commit: returns its sha256 as hex, or None when the file is not at that commit.
DigestFetcher = Callable[[str, str, str], Optional[str]]


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


def fetch_listing(repo: str, revision: str) -> Optional[dict]:
    """The hub's listing of a commit. None when the commit is not there (HTTP 404); other errors propagate."""
    url = API.format(repo=urllib.parse.quote(repo, safe="/"), revision=urllib.parse.quote(revision, safe=""))
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def fetch_digest(repo: str, revision: str, path: str) -> Optional[str]:
    """The sha256 of a file at a commit, computed from its bytes. None when the file is not there (HTTP 404)."""
    url = RAW.format(
        repo=urllib.parse.quote(repo, safe="/"),
        revision=urllib.parse.quote(revision, safe=""),
        path=urllib.parse.quote(path, safe="/"),
    )
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            while chunk := response.read(CHUNK):
                digest.update(chunk)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise
    return digest.hexdigest()


def check_model(
    model: PinnedModel,
    listing: dict,
    problems: list[str],
    stats: dict,
    digest_of: DigestFetcher = fetch_digest,
) -> None:
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
            continue
        stats["plain"] += 1
        if pinned.sha256 is None:
            problems.append(f"MISMATCH {model.id} {pinned.path}: file has no sha256 in the catalog")
            continue
        if not HEX64.match(pinned.sha256):
            problems.append(f"MISMATCH {model.id} {pinned.path}: catalog sha256 is not 64 lowercase hex digits")
            continue
        actual = digest_of(model.repository, model.revision, pinned.path)
        if actual is None:
            problems.append(f"MISMATCH {model.id} {pinned.path}: not downloadable at {model.revision}")
        elif actual != pinned.sha256:
            problems.append(
                f"MISMATCH {model.id} {pinned.path}: catalog sha256 {pinned.sha256}, downloaded bytes {actual}"
            )


def run(
    models: list[PinnedModel],
    listing_for: ListingFetcher = fetch_listing,
    digest_of: DigestFetcher = fetch_digest,
) -> tuple[list[str], dict]:
    """Checks every model. Returns the mismatch lines and the counts. Network errors propagate to the caller."""
    problems: list[str] = []
    stats = {"files": 0, "lfs": 0, "plain": 0}
    for model in models:
        listing = listing_for(model.repository, model.revision)
        if listing is None:
            problems.append(f"MISMATCH {model.id}: commit {model.revision} is not in {model.repository}")
            continue
        check_model(model, listing, problems, stats, digest_of)
    return problems, stats


def main(
    argv: list[str],
    listing_for: ListingFetcher = fetch_listing,
    digest_of: DigestFetcher = fetch_digest,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", default=DEFAULT_CATALOG, help="path to OnDeviceModelCatalog.swift")
    args = parser.parse_args(argv)

    try:
        models = parse_catalog(Path(args.catalog).read_text(encoding="utf-8"))
    except (OSError, CatalogError) as error:
        print(f"check_model_catalog: cannot read the catalog: {error}", file=sys.stderr)
        return 2

    try:
        problems, stats = run(models, listing_for, digest_of)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"check_model_catalog: cannot reach the hub: {error}", file=sys.stderr)
        return 2

    for line in problems:
        print(line)
    print(
        f"check_model_catalog: {len(models)} models, {stats['files']} files "
        f"({stats['lfs']} LFS compared by sha256, {stats['plain']} non-LFS downloaded and compared by sha256), "
        f"{len(problems)} mismatch(es)",
        file=sys.stderr,
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
