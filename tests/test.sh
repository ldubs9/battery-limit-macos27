#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

"$ROOT_DIR/build.sh"

python3 - "$BUILD_DIR/battery-limit" "$BUILD_DIR/battery-limit-smc" <<'PY'
import subprocess
import sys

cli, smc_helper = sys.argv[1:]

def run(*args, expect=0):
    result = subprocess.run([cli, *args], text=True, capture_output=True)
    if result.returncode != expect:
        raise SystemExit(f"{args}: expected {expect}, got {result.returncode}: {result.stdout}{result.stderr}")
    return result.stdout + result.stderr

help_text = run("--help")
assert "battery-limit status" in help_text
assert "force-discharge enable|disable" in help_text

limits = run("limits")
assert "80%" in limits and "95%" in limits

status = run("status")
assert "PowerUI supported: yes" in status
assert "Available limits:" in status
assert "Force discharge setting:" in status

force_status = run("force-discharge", "status")
assert "Force discharge setting:" in force_status

run("set", "79", expect=1)

# The helper must reject arbitrary keys and payloads before touching AppleSMC.
rejected = subprocess.run(
    [smc_helper, "--key", "XXXX", "--read"],
    text=True,
    capture_output=True,
)
assert rejected.returncode == 2, rejected

print("PASS: CLI help, native read-only status, force-discharge status, limits, and input guards")
PY

python3 - "$BUILD_DIR/BatteryLimit.app/Contents/Info.plist" <<'PY'
import plistlib
import subprocess
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
with plist_path.open("rb") as handle:
    plist = plistlib.load(handle)
assert plist["CFBundleIdentifier"] == "com.ecc.BatteryLimit"
assert plist["CFBundleShortVersionString"] == "0.3.0"
assert plist["LSUIElement"] is True
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(plist_path.parent.parent)], check=True)
print("PASS: app bundle plist and ad-hoc signature")
PY
