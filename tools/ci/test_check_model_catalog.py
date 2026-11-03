"""Tests for check_model_catalog.py, with planted catalogs and listings. No network: fetchers are passed in or patched."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import check_model_catalog as check

GOOD = "a" * 64
OTHER = "b" * 64

CATALOG = f"""
OnDeviceModel(
    id: "m1",
    repository: "org/repo",
    revision: "abc123",
    files: [
        OnDeviceModelFile("model.safetensors", 1_000, sha256: "{GOOD}"),
        OnDeviceModelFile("config.json", 12, sha256: "{GOOD}"),
    ]
)
"""

LISTING = {
    "sha": "abc123",
    "siblings": [
        {"rfilename": "model.safetensors", "lfs": {"size": 1000, "sha256": GOOD}},
        {"rfilename": "config.json", "size": 12},
    ],
}


def model_from(text: str) -> check.PinnedModel:
    return check.parse_catalog(text)[0]


def run_check(listing: dict, digest: str | None, text: str = CATALOG) -> list[str]:
    problems: list[str] = []
    stats = {"files": 0, "lfs": 0, "plain": 0}
    check.check_model(model_from(text), listing, problems, stats, lambda repo, rev, path: digest)
    return problems


class ParseTests(unittest.TestCase):
    def test_reads_lfs_and_plain_files(self) -> None:
        model = model_from(CATALOG)
        self.assertEqual((model.id, model.repository, model.revision), ("m1", "org/repo", "abc123"))
        self.assertEqual([(f.path, f.bytes) for f in model.files], [("model.safetensors", 1000), ("config.json", 12)])

    def test_an_empty_catalog_is_an_error(self) -> None:
        with self.assertRaises(check.CatalogError):
            check.parse_catalog("nothing here")


class PlainFileTests(unittest.TestCase):
    def test_a_matching_plain_file_passes(self) -> None:
        self.assertEqual(run_check(LISTING, GOOD), [])

    def test_a_planted_plain_file_hash_mismatch_is_reported(self) -> None:
        problems = run_check(LISTING, OTHER)
        self.assertEqual(len(problems), 1)
        self.assertIn("config.json", problems[0])
        self.assertIn("downloaded bytes", problems[0])

    def test_a_plain_file_that_is_not_downloadable_is_reported(self) -> None:
        problems = run_check(LISTING, None)
        self.assertEqual(len(problems), 1)
        self.assertIn("config.json", problems[0])
        self.assertIn("not downloadable", problems[0])

    def test_a_plain_file_with_no_catalog_sha256_is_reported(self) -> None:
        text = CATALOG.replace(f', sha256: "{GOOD}"),\n    ]', "),\n    ]")
        problems = run_check(LISTING, GOOD, text)
        self.assertTrue(any("file has no sha256 in the catalog" in p for p in problems), problems)

    def test_plain_files_are_counted_separately_from_lfs(self) -> None:
        problems: list[str] = []
        stats = {"files": 0, "lfs": 0, "plain": 0}
        check.check_model(model_from(CATALOG), LISTING, problems, stats, lambda *_: GOOD)
        self.assertEqual(stats, {"files": 2, "lfs": 1, "plain": 1})


class LfsFileTests(unittest.TestCase):
    def test_a_planted_lfs_sha_mismatch_is_still_reported(self) -> None:
        listing = {
            **LISTING,
            "siblings": [{"rfilename": "model.safetensors", "lfs": {"size": 1000, "sha256": OTHER}}, LISTING["siblings"][1]],
        }
        problems = run_check(listing, GOOD)
        self.assertTrue(any("repository LFS sha256" in p for p in problems), problems)


class MissingCommitTests(unittest.TestCase):
    """A commit that is not in the repository is a mismatch (exit 1), not a failed check (exit 2)."""

    def _catalog_path(self) -> Path:
        handle = tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False)
        handle.write(CATALOG)
        handle.close()
        return Path(handle.name)

    def test_a_missing_commit_exits_1_and_says_so(self) -> None:
        out = io.StringIO()
        err = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = check.main(
                ["--catalog", str(self._catalog_path())],
                listing_for=lambda repo, rev: None,
                digest_of=lambda *_: GOOD,
            )
        self.assertEqual(code, 1)
        self.assertIn("commit abc123 is not in org/repo", out.getvalue())

    def test_a_clean_catalog_exits_0(self) -> None:
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            code = check.main(
                ["--catalog", str(self._catalog_path())],
                listing_for=lambda repo, rev: LISTING,
                digest_of=lambda *_: GOOD,
            )
        self.assertEqual(code, 0)

    def test_fetch_listing_returns_none_on_404(self) -> None:
        error = urllib.error.HTTPError("url", 404, "Not Found", {}, None)
        with mock.patch.object(check.urllib.request, "urlopen", side_effect=error):
            self.assertIsNone(check.fetch_listing("org/repo", "abc123"))

    def test_fetch_listing_still_raises_other_errors(self) -> None:
        error = urllib.error.HTTPError("url", 500, "Server Error", {}, None)
        with mock.patch.object(check.urllib.request, "urlopen", side_effect=error):
            with self.assertRaises(urllib.error.HTTPError):
                check.fetch_listing("org/repo", "abc123")

    def test_an_unreachable_hub_exits_2(self) -> None:
        def unreachable(repo: str, rev: str) -> dict:
            raise urllib.error.URLError("no route")

        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            code = check.main(["--catalog", str(self._catalog_path())], listing_for=unreachable, digest_of=lambda *_: GOOD)
        self.assertEqual(code, 2)
        self.assertIn("cannot reach the hub", err.getvalue())


class DigestTests(unittest.TestCase):
    def test_fetch_digest_hashes_the_downloaded_bytes(self) -> None:
        class FakeResponse(io.BytesIO):
            def __enter__(self) -> "FakeResponse":
                return self

            def __exit__(self, *args: object) -> None:
                return None

        body = b"hello catalog"
        import hashlib

        with mock.patch.object(check.urllib.request, "urlopen", return_value=FakeResponse(body)):
            self.assertEqual(check.fetch_digest("org/repo", "abc123", "config.json"), hashlib.sha256(body).hexdigest())


if __name__ == "__main__":
    unittest.main()
