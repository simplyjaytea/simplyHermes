#!/usr/bin/env bash
# Local checks to run before a push: format lint and swiftlint on the Swift files this branch changed, then the
# Linux build and tests (HermesKit and HermesSSH). Makes no network calls except what `swift package` needs, and never
# pushes.
#
# The tests build into a scratch directory outside the repo (--scratch-path). The compiler still writes stray files
# into the package root, so the script removes the ones its own build created when it exits.
#
# Usage: tools/ci/prepush.sh [--lint-only] [--base <ref>]
#   --base       the ref to diff against for the changed-file list (default origin/main)
#   --lint-only  skip the build and tests
#
# Set HERMES_TOOLCHAIN_ENV to a script that puts Swift 6.1 and the sqlite paths on PATH. When it is unset, the script
# uses the server default if that file exists, and otherwise the Swift already on PATH.
set -euo pipefail

BASE="origin/main"
LINT_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE="${2:?--base needs a ref}"; shift 2 ;;
        --lint-only) LINT_ONLY=1; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENV_SH="${HERMES_TOOLCHAIN_ENV:-/var/lib/openbot/OpenBot/Shared/toolchain/env.sh}"
if [ -f "$ENV_SH" ]; then
    # shellcheck disable=SC1090
    source "$ENV_SH"
fi

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "prepush: base ref '$BASE' not found. Run git fetch first, or pass --base." >&2
    exit 2
fi

# Swift files this branch changed, including uncommitted edits, that still exist. The diff starts at the merge base,
# so changes that landed on the base after this branch started are not counted.
# (A while-read loop instead of mapfile: macOS ships bash 3.2, which has no mapfile.)
MERGE_BASE="$(git merge-base "$BASE" HEAD)"
FILES=()
while IFS= read -r f; do
    [ -f "$f" ] && FILES+=("$f")
done < <({ git diff --name-only --diff-filter=ACMR "$MERGE_BASE" -- Sources Tests App; git ls-files --others --exclude-standard -- Sources Tests App; } | grep -E '\.swift$' || true)

echo "prepush: ${#FILES[@]} changed Swift file(s) against $BASE"

if [ "${#FILES[@]}" -gt 0 ]; then
    echo "prepush: swift format lint --strict"
    swift format lint --strict "${FILES[@]}"
    echo "prepush: swiftlint --strict"
    swiftlint lint --strict "${FILES[@]}"
else
    echo "prepush: no Swift files changed, skipping format lint and swiftlint"
fi

if [ "$LINT_ONLY" -eq 1 ]; then
    echo "prepush: lint passed (--lint-only, build and tests skipped)"
    exit 0
fi

# The Swift compiler writes stray files with binary or one-letter names into the package root while it builds.
# --scratch-path does not stop that. On exit, remove the untracked files in the root that this run created: any that
# were not there before the build started. Files that were already there are left alone.
SNAPSHOT="$(mktemp)"
git ls-files --others --exclude-standard -z > "$SNAPSHOT"
remove_compiler_debris() {
    # Two sweeps: the second, about 2 seconds later, catches a file the compiler writes after the first one.
    local pass
    for pass in 1 2; do
        python3 -I - "$SNAPSHOT" "$ROOT" <<'PY' || true
import os, subprocess, sys
snapshot, root = sys.argv[1], sys.argv[2]
os.chdir(root)
before = set(open(snapshot, "rb").read().split(b"\0"))
listing = subprocess.run(
    ["git", "ls-files", "--others", "--exclude-standard", "-z"], capture_output=True, check=True
).stdout
removed = 0
for name in listing.split(b"\0"):
    # Only untracked files directly in the package root, that were not there before the build started.
    if not name or b"/" in name or name in before or not os.path.isfile(name):
        continue
    os.remove(name)
    removed += 1
print(f"prepush: removed {removed} stray root file(s) created by the build")
PY
        if [ "$pass" -eq 1 ]; then sleep 2; fi
    done
    rm -f "$SNAPSHOT"
}
trap remove_compiler_debris EXIT

SCRATCH="${HERMES_PREPUSH_SCRATCH:-${TMPDIR:-/tmp}/hermes-prepush-$(basename "$ROOT")}"
echo "prepush: swift build --build-tests (scratch: $SCRATCH)"
swift build --build-tests --scratch-path "$SCRATCH"
echo "prepush: swift test (scratch: $SCRATCH)"
swift test --scratch-path "$SCRATCH"
echo "prepush: all checks passed"
