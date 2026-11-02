#!/usr/bin/env bash
# Merge gate for simplyHermes PRs (plan section 7). Merges PR <N> into main with a merge commit only when:
#   - the PR is open, targets main, is not a draft and has no merge conflict, and
#   - each of the 4 CI jobs has the conclusion `success` on the PR's exact head commit. A skipped, cancelled,
#     pending or missing job fails the gate, so a draft's skipped App job never counts.
#   - main is green: the newest push run on main is for main's current head and every job in it is `success`.
#     A red, cancelled or still-running main refuses (plan section 7: a red main comes before any new merge).
# The merge passes --match-head-commit, so GitHub refuses it if the head moved after the check.
# Review and QA stay human gates: run this only after Gilfoyle's review (and Moss's QA for user-facing changes).
#
# Usage: tools/ci/merge_gate.sh [--dry-run] [--red-main-ok "<who approved, and why>"] <PR number>
#   --dry-run      check everything and print the verdict, but don't merge.
#   --red-main-ok  merge although main is not green. Only for a merge that Janet approved as the fix for red main;
#                  the reason is printed and must be quoted in the board row.
# Exit status: 0 merged (or would merge), 1 gate refused, 2 usage or lookup error.
set -euo pipefail

REQUIRED_JOBS=("Changed files" "Packages (Linux)" "Testbed smoke (Docker)" "App (Xcode 27, simulator)")
REPO="${GH_REPO:-simplyjaytea/simplyHermes}"

dry_run=0
red_main_ok=""
pr=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --red-main-ok)
      shift
      red_main_ok="${1:-}"
      # A reason is who approved and why. A blank one, or a flag that follows by mistake (`--red-main-ok --dry-run`),
      # is refused before anything else runs, so a dry run can never turn into a merge.
      trimmed="${red_main_ok//[[:space:]]/}"
      if [ -z "$trimmed" ] || [[ "$red_main_ok" == -* ]]; then
        echo "--red-main-ok needs a reason: who approved, and why (got '${red_main_ok}')" >&2
        exit 2
      fi
      ;;
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
    *) pr="$1" ;;
  esac
  shift
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

# Main must be green: the newest push run of the CI workflow on main, for main's current head, with every job `success`.
main_head=$(gh api "repos/$REPO/commits/main" --jq '.sha') || exit 2
main_run="" main_run_sha="" main_status="" main_conclusion=""
IFS=$'\t' read -r main_run main_run_sha main_status main_conclusion < <(gh run list --repo "$REPO" --branch main \
  --event push --workflow CI --limit 1 --json databaseId,headSha,status,conclusion \
  --jq '.[0] // empty | [(.databaseId|tostring), .headSha, .status, (.conclusion // "none")] | @tsv') || true
echo "main ${main_head:0:7}: push run ${main_run:-none} ${main_status:-}/${main_conclusion:-}"
main_problem=""
if [ -z "${main_run:-}" ]; then
  main_problem="main has no push run"
elif [ "$main_run_sha" != "$main_head" ]; then
  main_problem="main's newest push run ($main_run) is for ${main_run_sha:0:7}, not main's head ${main_head:0:7}"
elif [ "$main_status" != "completed" ]; then
  main_problem="main's push run $main_run is still $main_status"
elif [ "$main_conclusion" != "success" ]; then
  main_problem="main's push run $main_run is $main_conclusion"
fi
if [ -n "$main_problem" ]; then
  if [ -n "$red_main_ok" ]; then
    echo "MAIN NOT GREEN, merging anyway (--red-main-ok): $main_problem. Approved: $red_main_ok"
  else
    refuse "$main_problem (a red main comes before any new merge)"
  fi
fi

if [ "${#refusals[@]}" -gt 0 ]; then
  echo "REFUSED: PR #$pr does not pass the merge gate:"
  printf '  - %s\n' "${refusals[@]}"
  exit 1
fi

if [ "$dry_run" -eq 1 ]; then
  echo "PASS (dry run): PR #$pr would be merged at $sha with a merge commit."
  exit 0
fi

# Main must not have moved since it was checked: a push that landed in between was not part of the green check.
main_now=$(gh api "repos/$REPO/commits/main" --jq '.sha') || exit 2
if [ "$main_now" != "$main_head" ]; then
  echo "REFUSED: main moved from ${main_head:0:7} to ${main_now:0:7} during the check. Run the gate again."
  exit 1
fi

gh pr merge "$pr" --repo "$REPO" --merge --match-head-commit "$sha"
merge_sha=$(gh pr view "$pr" --repo "$REPO" --json mergeCommit --jq '.mergeCommit.oid')
echo "MERGED: PR #$pr at head $sha, merge commit $merge_sha"
# The merge commit's first parent is the main it landed on. If that is not the main the gate checked, say so.
parent=$(gh api "repos/$REPO/commits/$merge_sha" --jq '.parents[0].sha' 2>/dev/null || true)
if [ -n "$parent" ] && [ "$parent" != "$main_head" ]; then
  echo "WARNING: main moved to ${parent:0:7} just before the merge; the gate checked ${main_head:0:7}."
fi
