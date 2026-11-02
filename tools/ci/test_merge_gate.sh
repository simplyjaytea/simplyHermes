#!/usr/bin/env bash
# Tests for tools/ci/merge_gate.sh against a fake `gh` (no network). Each case sets the fake's answers, runs the gate,
# and checks the exit code and whether a merge was attempted. Run: bash tools/ci/test_merge_gate.sh
set -uo pipefail

gate="$(cd "$(dirname "$0")" && pwd)/merge_gate.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

# The fake gh. Behaviour comes from files in $work: pr, checks, mainrun, mainhead (one line per call: the first call
# answers the gate's check, later calls answer the re-read before the merge). It records merges in $work/merged and
# the run-list arguments in $work/runlist-args.
cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
w="$FAKE_WORK"
case "$1 $2" in
  "pr view")
    if [[ " $* " == *" mergeCommit "* ]]; then echo "merge123"; else cat "$w/pr"; fi ;;
  "pr merge") echo "$*" >> "$w/merged" ;;
  "api --paginate") cat "$w/checks" ;;
  "run list") echo "$*" > "$w/runlist-args"; cat "$w/mainrun" ;;
  api\ *)
    case "$2" in
      */commits/main)
        n=$(cat "$w/mainhead-calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$w/mainhead-calls"
        sed -n "${n}p" "$w/mainhead" | grep . || tail -n 1 "$w/mainhead" ;;
      */commits/merge123) echo "${FAKE_PARENT:-mainhead1}" ;;
      *) echo "unexpected api $2" >&2; exit 9 ;;
    esac ;;
  *) echo "unexpected gh $*" >&2; exit 9 ;;
esac
FAKE
chmod +x "$work/bin/gh"

green_checks=$'10\tChanged files\tcompleted\tsuccess\tu\n11\tPackages (Linux)\tcompleted\tsuccess\tu\n12\tTestbed smoke (Docker)\tcompleted\tsuccess\tu\n13\tApp (Xcode 27, simulator)\tcompleted\tsuccess\tu'
failures=0

# case <name> <expected exit> <expect merge: yes|no> <mainrun line or empty> <mainhead lines> -- <gate args...>
case_() {
  local name=$1 want=$2 merge=$3 mainrun=$4 mainhead=$5
  shift 6
  rm -f "$work/merged" "$work/mainhead-calls" "$work/runlist-args"
  printf 'OPEN\tfalse\tmain\tprhead1\tMERGEABLE\tFake PR\n' > "$work/pr"
  printf '%s\n' "$green_checks" > "$work/checks"
  # Like gh: one line per run, newline-terminated; nothing at all for an empty list.
  if [ -n "$mainrun" ]; then printf '%s\n' "$mainrun" > "$work/mainrun"; else : > "$work/mainrun"; fi
  printf '%s\n' "$mainhead" > "$work/mainhead"
  local out code
  out=$(FAKE_WORK="$work" PATH="$work/bin:$PATH" bash "$gate" "$@" 2>&1)
  code=$?
  local merged=no
  [ -s "$work/merged" ] && merged=yes
  if [ "$code" != "$want" ] || [ "$merged" != "$merge" ]; then
    echo "FAIL $name: exit $code (want $want), merged $merged (want $merge)"
    echo "$out" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

green=$'900\tmainhead1\tcompleted\tsuccess'
red=$'900\tmainhead1\tcompleted\tfailure'

case_ "green main merges" 0 yes "$green" mainhead1 -- 7
case_ "green main, dry run does not merge" 0 no "$green" mainhead1 -- --dry-run 7
case_ "red main refuses" 1 no "$red" mainhead1 -- 7
case_ "cancelled main refuses" 1 no $'900\tmainhead1\tcompleted\tcancelled' mainhead1 -- 7
case_ "running main refuses" 1 no $'900\tmainhead1\tin_progress\tnone' mainhead1 -- 7
case_ "stale main run refuses" 1 no $'899\toldhead0\tcompleted\tsuccess' mainhead1 -- 7
case_ "no main run refuses" 1 no "" mainhead1 -- 7
case_ "red main with a reason merges" 0 yes "$red" mainhead1 -- --red-main-ok "Janet: the fix for red main" 7
case_ "--red-main-ok --dry-run is refused, never merges (M1)" 2 no "$red" mainhead1 -- --red-main-ok --dry-run 7
case_ "--red-main-ok with a blank reason is refused (m1)" 2 no "$red" mainhead1 -- --red-main-ok "   " 7
case_ "--red-main-ok with no reason is refused" 2 no "$red" mainhead1 -- 7 --red-main-ok
case_ "main moved before the merge refuses (m4)" 1 no "$green" $'mainhead1\nmainhead2' -- 7

# m2: the gate asks only for the CI workflow's runs.
case_ "run list is filtered to the CI workflow (m2)" 0 no "$green" mainhead1 -- --dry-run 7
if ! grep -q -- "--workflow CI" "$work/runlist-args"; then
  echo "FAIL run list is not filtered to the CI workflow: $(cat "$work/runlist-args")"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures merge gate test(s) failed"
  exit 1
fi
echo "all merge gate tests passed"
