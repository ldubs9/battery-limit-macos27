#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DEST="${HOME}/Applications/BatteryLimit.app"
CLI_DEST="${HOME}/Applications/battery-limit"
PLIST_PATH="${HOME}/Library/LaunchAgents/com.ecc.BatteryLimit.plist"
HELPER_DEST="/usr/local/libexec/battery-limit-smc"
LABEL="com.ecc.BatteryLimit"
SKIP_HELPER=0

usage() {
    cat <<'USAGE'
Usage: ./install.sh [--skip-helper]

Builds Battery Limit, installs it to ~/Applications/BatteryLimit.app, and
registers it as a per-user launch agent.

By default it also installs the narrowly scoped CHIE SMC helper and sudoers
rules needed by force discharge. Use --skip-helper only when an existing
compatible helper (such as the legacy battery helper) is already installed.
USAGE
}

for argument in "$@"; do
    case "$argument" in
        --skip-helper) SKIP_HELPER=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    esac
done

"$ROOT_DIR/build.sh"

mkdir -p "${HOME}/Applications"
rm -rf "$APP_DEST"
ditto "$ROOT_DIR/build/BatteryLimit.app" "$APP_DEST"
install -m 755 "$ROOT_DIR/build/battery-limit" "$CLI_DEST"

if [[ "$SKIP_HELPER" -eq 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        printf 'sudo is required to install the SMC helper.\n' >&2
        exit 1
    fi

    sudo install -d -m 755 "$(dirname "$HELPER_DEST")"
    sudo install -o root -g wheel -m 755 "$ROOT_DIR/build/battery-limit-smc" "$HELPER_DEST"

    SUDOERS_TEMP="$(mktemp "${TMPDIR:-/tmp}/battery-limit-sudoers.XXXXXX")"
    trap 'rm -f "$SUDOERS_TEMP"' EXIT
    cat >"$SUDOERS_TEMP" <<EOF
# Battery Limit: only the fixed CHIE adapter-control operations are allowed.
ALL ALL = (root) NOPASSWD: $HELPER_DEST --key CHIE --read, $HELPER_DEST --key CHIE --write 00, $HELPER_DEST --key CHIE --write 08
EOF
    sudo visudo -cf "$SUDOERS_TEMP" >/dev/null
    sudo install -o root -g wheel -m 440 "$SUDOERS_TEMP" /etc/sudoers.d/battery-limit
else
    printf 'Skipping helper installation as requested.\n'
fi

mkdir -p "$(dirname "$PLIST_PATH")"
python3 - "$PLIST_PATH" "$APP_DEST/Contents/MacOS/BatteryLimit" <<'PY'
import plistlib
import sys
from pathlib import Path

plist_path = Path(sys.argv[1])
program = sys.argv[2]
plist = {
    "Label": "com.ecc.BatteryLimit",
    "ProgramArguments": [program],
    "RunAtLoad": True,
    "ProcessType": "Interactive",
    "LimitLoadToSessionType": "Aqua",
    "StandardOutPath": str(Path.home() / "Library/Logs/BatteryLimit.log"),
    "StandardErrorPath": str(Path.home() / "Library/Logs/BatteryLimit.error.log"),
}
plist_path.write_bytes(plistlib.dumps(plist, fmt=plistlib.FMT_XML, sort_keys=False))
PY

mkdir -p "${HOME}/Library/Logs"
USER_ID="$(id -u)"
launchctl bootout "gui/$USER_ID" "$PLIST_PATH" 2>/dev/null || true
pkill -f "$ROOT_DIR/build/BatteryLimit.app/Contents/MacOS/BatteryLimit" 2>/dev/null || true
launchctl bootstrap "gui/$USER_ID" "$PLIST_PATH"
launchctl enable "gui/$USER_ID/$LABEL" 2>/dev/null || true

printf '\nInstalled app: %s\n' "$APP_DEST"
printf 'Installed CLI: %s\n' "$CLI_DEST"
printf 'LaunchAgent: %s\n' "$PLIST_PATH"
printf 'The menu-bar app will launch at login.\n'
printf 'Open it in Finder with: open "%s"\n' "$APP_DEST"
printf '\nForce-discharge CLI: %s\n' "$CLI_DEST"
