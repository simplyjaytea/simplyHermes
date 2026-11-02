#!/usr/bin/env bash
# Simulator fallback for the App job (user-approved 2026-11-02). The hosted iOS 27.1 runtime can disappear in the
# middle of a job: its image is unmounted, xcodebuild reports "Malformed bundle" and then "Unable to find a device
# matching the provided destination specifier" (exit 70), and no test runs (runs 41394939027, 41426325334).
#
# Usage: tools/ci/sim_fallback.sh check <udid>   exit 0 when the device's runtime is still usable, 1 when not
#        tools/ci/sim_fallback.sh pick <udid>    make a device on the newest other usable iOS 27.x runtime, boot it,
#                                                and print shell-quoted `udid=` `name=` `os=` lines to eval; exit 1 when there is none
# `pick` also writes the runtime it used to the job summary and a warning annotation, so a fallback run says which
# iOS it tested on.
set -euo pipefail

mode="${1:-}"
udid="${2:-}"
[ -n "$mode" ] && [ -n "$udid" ] || { echo "usage: $0 check|pick <udid>" >&2; exit 2; }

# Usable iOS 27 runtimes, newest first, as "identifier<TAB>version<TAB>name". "Usable" means simctl calls it
# available and its bundle is still on disk: the unmounted runtime fails the second test.
usable_runtimes() {
  xcrun simctl list runtimes -j | python3 -c '
import json, os, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("isAvailable") and r["identifier"].split(".")[-1].startswith("iOS-27-")
            and os.path.isdir(r.get("bundlePath", ""))]
runtimes.sort(key=lambda r: [int(n) for n in r["version"].split(".")], reverse=True)
for r in runtimes:
    print("\t".join([r["identifier"], r["version"], r["name"]]))
'
}

# The runtime identifier of a device, or nothing when simctl no longer lists the device as available.
device_runtime() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if any(d["udid"] == sys.argv[1] for d in devices):
        print(runtime)
' "$1"
}

current=$(device_runtime "$udid")

case "$mode" in
  check)
    [ -n "$current" ] && usable_runtimes | cut -f1 | grep -x -- "$current" > /dev/null
    ;;
  pick)
    # Try each other usable iOS 27 runtime, newest first. On each, reuse an available iPhone device, or create one
    # from the device types that runtime supports (a Duo when it can): a type the runtime does not support fails with
    # "Incompatible device" (main run 41448899995).
    picked=""
    while IFS=$'\t' read -r runtime version runtime_name; do
      [ -n "$runtime" ] || continue
      device=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"].get(sys.argv[1], [])
phones = [d for d in devices if "iPhone" in d["name"]]
phones.sort(key=lambda d: ("Duo" not in d["name"], d["name"]))
print(phones[0]["udid"] + "\t" + phones[0]["name"] if phones else "")
' "$runtime")
      if [ -n "$device" ]; then
        IFS=$'\t' read -r new name <<< "$device"
      else
        type=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtime = next((r for r in json.load(sys.stdin)["runtimes"] if r["identifier"] == sys.argv[1]), {})
types = [t for t in runtime.get("supportedDeviceTypes", []) if t.get("productFamily", "iPhone") == "iPhone"]
duo = [t for t in types if "duo" in t["name"].lower()]
print((duo or types)[-1]["identifier"] if (duo or types) else "")
' "$runtime")
        [ -n "$type" ] || continue
        name="iPhone CI fallback"
        new=$(xcrun simctl create "$name" "$type" "$runtime" 2>/dev/null < /dev/null) || continue
      fi
      xcrun simctl boot "$new" 2>/dev/null < /dev/null || true
      if xcrun simctl bootstatus "$new" -b >&2 < /dev/null; then
        picked=$runtime
        break
      fi
    done < <(usable_runtimes | awk -F'\t' -v skip="$current" '$1 != skip')
    if [ -z "$picked" ]; then
      echo "::error::The simulator runtime ${current:-of $udid} is unusable and no other iOS 27 runtime gave a device."
      exit 1
    fi
    message="Simulator fallback: ${current:-the picked runtime} was unusable, so tests ran on $name, $runtime_name ($runtime)."
    echo "::warning::$message" >&2
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      printf '### Simulator fallback\n%s\n' "$message" >> "$GITHUB_STEP_SUMMARY"
    fi
    # Shell-quoted, so the caller can eval the lines.
    printf 'udid=%q\nname=%q\nos=%q\n' "$new" "$name" "$version"
    ;;
  *)
    echo "usage: $0 check|pick <udid>" >&2
    exit 2
    ;;
esac
