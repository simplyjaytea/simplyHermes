#!/usr/bin/env bash
# Merge gate for simplyHermes PRs (plan section 7). Merges PR <N> into main with a merge commit only when:
#   - the PR is open, targets main, is not a draft and has no merge conflict, and
#   - each of the 4 CI jobs has the conclusion `success` on the PR's exact head commit. A skipped, cancelled,
#     pending or missing job fails the gate, so a draft's skipped App job never counts.
# The merge passes --match-head-commit, so GitHub refuses it if the head moved after the check.
# Review and QA stay human gates: run this only after Gilfoyle's review (and Moss's QA for user-facing changes).
#
# Usage: tools/ci/merge_gate.sh [--dry-run] <PR number>
#   --dry-run  check everything and print the verdict, but don't merge.
# Exit status: 0 merged (or would merge), 1 gate refused, 2 usage or lookup error.
set -euo pipefail

REQUIRED_JOBS=("Changed files" "Packages (Linux)" "Testbed smoke (Docker)" "App (Xcode 27, simulator)")
REPO="${GH_REPO:-simplyjaytea/simplyHermes}"

dry_run=0
pr=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    -h | --help) sed -n '2,12p' "$0"; exit 0 ;;
    *) pr="$arg" ;;
  esac
done
if ! [[ "$pr" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 [--dry-run] <PR number>" >&2
  exit 2
fi

refusals=()
refuse() { refusals+=("$1"); }

# One tab-separated line: state, draft, base, head, mergeable, title. Needs only gh (its built-in --jq), no jq.
IFS=$'\t' read -r state draft base sha mergeable title < <(gh pr view "$pr" --repo "$REPO" \
  --json state,isDraft,baseRefName,headRefOid,mergeable,title \
  --jq '[.state, (.isDraft|tostring), .baseRefName, .headRefOid, .mergeable, .title] | @tsv') || exit 2
[ -n "${sha:-}" ] || { echo "could not read PR #$pr" >&2; exit 2; }
echo "PR #$pr: $title"
echo "head $sha"

[ "$state" = "OPEN" ] || refuse "PR is $state, not OPEN"
[ "$base" = "main" ] || refuse "PR targets $base, not main"
[ "$draft" = "false" ] || refuse "PR is a draft (mark it ready: only the merge candidate runs the App job)"
[ "$mergeable" != "CONFLICTING" ] || refuse "PR has merge conflicts with main"

# Every check run on this exact commit as "id<TAB>name<TAB>status<TAB>conclusion<TAB>url". Reruns create newer check
# runs (higher id), so the newest one per job name wins.
runs=$(gh api --paginate "repos/$REPO/commits/$sha/check-runs?per_page=100" \
  --jq '.check_runs[] | [(.id|tostring), .name, .status, (.conclusion // "none"), .html_url] | @tsv') || exit 2
for job in "${REQUIRED_JOBS[@]}"; do
  latest=$(awk -F'\t' -v n="$job" '$2 == n' <<< "$runs" | sort -t$'\t' -k1,1n | tail -n 1)
  if [ -z "$latest" ]; then
    refuse "$job: no run on $sha"
    echo "  $job: missing"
    continue
  fi
  IFS=$'\t' read -r _ _ status conclusion url <<< "$latest"
  echo "  $job: $status/$conclusion $url"
  if [ "$status" != "completed" ]; then
    refuse "$job: still $status"
  elif [ "$conclusion" != "success" ]; then
    refuse "$job: $conclusion (only success passes; skipped does not)"
  fi
done

if [ "${#refusals[@]}" -gt 0 ]; then
  echo "REFUSED: PR #$pr does not pass the merge gate:"
  printf '  - %s\n' "${refusals[@]}"
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  echo "PASS (dry run): PR #$pr would be merged at $sha with a merge commit."
  exit 0
fi

gh pr merge "$pr" --repo "$REPO" --merge --match-head-commit "$sha"
merge_sha=$(gh pr view "$pr" --repo "$REPO" --json mergeCommit --jq '.mergeCommit.oid')
echo "MERGED: PR #$pr at head $sha, merge commit $merge_sha"
