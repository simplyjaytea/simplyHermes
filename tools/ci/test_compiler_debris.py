"""Tests for compiler_debris.py: the sweep removes compiler debris and nothing a developer put in the root."""

from __future__ import annotations

import unittest

from compiler_debris import is_compiler_debris


class CompilerDebrisTests(unittest.TestCase):
    def test_binary_and_one_letter_names_are_debris(self) -> None:
        # Names the compiler wrote into the package root during earlier Linux runs.
        for name in [b"\x01.\xca\xaa\x05", b"\x03\x80\xd6\x01\x06", b"l", b"~\xcc", b"t\x0fl\x1e\xc8`", b"w~\xdc~\x05"]:
            with self.subTest(name=name):
                self.assertTrue(is_compiler_debris(name))

    def test_a_developer_file_in_the_root_is_not_debris(self) -> None:
        for name in [b"NOTES.md", b"scratch.txt", b"Makefile", b"README", b"todo.json", b".env.local", b"a.b"]:
            with self.subTest(name=name):
                self.assertFalse(is_compiler_debris(name))

    def test_a_name_with_a_space_is_not_debris(self) -> None:
        self.assertFalse(is_compiler_debris(b"meeting notes.txt"))

    def test_a_path_is_never_debris(self) -> None:
        self.assertFalse(is_compiler_debris(b"tools/ci/x"))

    def test_an_empty_name_is_not_debris(self) -> None:
        self.assertFalse(is_compiler_debris(b""))


if __name__ == "__main__":
    unittest.main()
