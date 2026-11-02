#!/usr/bin/env bash
# Tests for tools/ci/sim_fallback.sh against a fake `xcrun` (no simulators needed). Run: bash tools/ci/test_sim_fallback.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/sim_fallback.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/rt270" "$work/rt271"

# The fake answers from $work/runtimes.json and $work/devices.json, refuses to create a device type the runtime does not
# list (like CoreSimulator's "Incompatible device"), and logs create calls to $work/calls.
cat > "$work/bin/xcrun" <<'FAKE'
#!/usr/bin/env bash
w="$FAKE_WORK"
shift
case "$1 $2 $3" in
  "list runtimes -j") cat "$w/runtimes.json" ;;
  "list devices available") cat "$w/devices.json" ;;
  create*)
    echo "create $3 $4" >> "$w/calls"
    if python3 -c '
import json, sys
r = next(r for r in json.load(open(sys.argv[1]))["runtimes"] if r["identifier"] == sys.argv[3])
sys.exit(0 if any(t["identifier"] == sys.argv[2] for t in r.get("supportedDeviceTypes", [])) else 1)
' "$w/runtimes.json" "$3" "$4"; then
      echo "NEW-$3"
    else
      echo "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=403): Incompatible device" >&2
      exit 1
    fi ;;
  boot*) : ;;
  bootstatus*) : ;;
  *) echo "unexpected xcrun simctl $*" >&2; exit 9 ;;
esac
FAKE
chmod +x "$work/bin/xcrun"

phone17='{"name":"iPhone 17","identifier":"com.apple.iPhone-17","productFamily":"iPhone"}'
pro18='{"name":"iPhone 18 Pro","identifier":"com.apple.iPhone-18-Pro","productFamily":"iPhone"}'
duo='{"name":"iPhone Duo","identifier":"com.apple.iPhone-Duo","productFamily":"iPhone"}'
ipad='{"name":"iPad Pro","identifier":"com.apple.iPad-Pro","productFamily":"iPad"}'

# runtimes <27.0 supported types> <27.1 bundle dir>
runtimes() {
  cat > "$work/runtimes.json" <<EOF
{"runtimes":[
 {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","name":"iOS 27.0","isAvailable":true,
  "bundlePath":"$work/rt270","supportedDeviceTypes":[$1]},
 {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1","version":"27.1","name":"iOS 27.1","isAvailable":true,
  "bundlePath":"$2","supportedDeviceTypes":[$duo,$phone17]}]}
EOF
}
devices() { printf '%s\n' "$1" > "$work/devices.json"; }
duo_on_271='"com.apple.CoreSimulator.SimRuntime.iOS-27-1":[{"udid":"DUO-271","name":"iPhone Duo CI"}]'

failures=0
# expect <name> <want exit> <want udid or -> <want created type or -> -- <mode>
expect() {
  local name=$1 want=$2 udid=$3 created=$4 mode=$6
  rm -f "$work/calls"
  local out code
  out=$(FAKE_WORK="$work" PATH="$work/bin:$PATH" GITHUB_STEP_SUMMARY=/dev/null bash "$script" "$mode" DUO-271 2>/dev/null)
  code=$?
  local got_udid got_created
  got_udid=$(sed -n 's/^udid=//p' <<< "$out")
  got_created=$(awk '{print $2}' "$work/calls" 2>/dev/null | tail -n 1)
  if [ "$code" != "$want" ] || { [ "$udid" != - ] && [ "$got_udid" != "$udid" ]; } \
    || { [ "$created" != - ] && [ "$got_created" != "$created" ]; } \
    || { [ "$created" = - ] && [ -s "$work/calls" ]; }; then
    echo "FAIL $name: exit $code (want $want), udid '$got_udid' (want $udid), created '$got_created' (want $created)"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

runtimes "$phone17" "$work/rt271"
devices "{\"devices\":{$duo_on_271}}"
expect "healthy 27.1: check passes" 0 - - -- check

# Today's failure (main run 41448899995, #102 run 41449851961): 27.1 unmounted, 27.0 does not support the Duo type,
# and 27.0 already has ready iPhones. The fallback must reuse one and never ask for a Duo.
runtimes "$phone17,$pro18,$ipad" "$work/gone"
devices "{\"devices\":{$duo_on_271,\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[{\"udid\":\"F82EF267\",\"name\":\"iPhone 17\"},{\"udid\":\"PRO18\",\"name\":\"iPhone 18 Pro\"},{\"udid\":\"IPAD1\",\"name\":\"iPad Pro\"}]}}"
expect "27.1 gone: check fails" 1 - - -- check
expect "Duo unsupported on 27.0, iPhones ready: reuses one (name order), creates nothing" 0 F82EF267 - -- pick

# Same runtime, no ready device: create from 27.0's own supported types, never the Duo.
devices "{\"devices\":{$duo_on_271}}"
expect "Duo unsupported on 27.0, no device: creates a supported iPhone" 0 NEW-com.apple.iPhone-18-Pro com.apple.iPhone-18-Pro -- pick

# A runtime that does support the Duo gets one.
runtimes "$phone17,$duo" "$work/gone"
expect "Duo supported on 27.0: creates a Duo" 0 NEW-com.apple.iPhone-Duo com.apple.iPhone-Duo -- pick

# No iPhone anywhere else: a clear failure, not a hang.
runtimes "$ipad" "$work/gone"
expect "no iPhone type on 27.0: fails" 1 - - -- pick

if [ "$failures" -gt 0 ]; then
  echo "$failures simulator fallback test(s) failed"
  exit 1
fi
echo "all simulator fallback tests passed"
