#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT_DIR/src"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/BatteryLimit.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$BUILD_DIR"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
SYSROOT_FLAGS=()
if [[ -n "$SDKROOT" ]]; then
    SYSROOT_FLAGS=(-isysroot "$SDKROOT")
fi

COMMON_FLAGS=(-fobjc-arc -Wall -Wextra -Wpedantic -mmacosx-version-min=15.0 "${SYSROOT_FLAGS[@]}")

for source in PowerUIChargeLimit BLAdapterController BLBatteryState BLBatteryStatusDisplay BLSettings; do
    clang "${COMMON_FLAGS[@]}" -c "$SRC_DIR/$source.m" \
        -o "$BUILD_DIR/$source.o"
done

clang "${COMMON_FLAGS[@]}" "$SRC_DIR/battery-limit-cli.m" \
    "$BUILD_DIR/PowerUIChargeLimit.o" \
    "$BUILD_DIR/BLAdapterController.o" \
    "$BUILD_DIR/BLBatteryState.o" \
    "$BUILD_DIR/BLSettings.o" \
    -framework Foundation -framework IOKit \
    -o "$BUILD_DIR/battery-limit"

clang "${COMMON_FLAGS[@]}" "$SRC_DIR/BatteryLimitApp.m" \
    "$BUILD_DIR/PowerUIChargeLimit.o" \
    "$BUILD_DIR/BLAdapterController.o" \
    "$BUILD_DIR/BLBatteryState.o" \
    "$BUILD_DIR/BLBatteryStatusDisplay.o" \
    "$BUILD_DIR/BLSettings.o" \
    -framework AppKit -framework Foundation -framework IOKit \
    -o "$APP_DIR/Contents/MacOS/BatteryLimit"

clang -Wall -Wextra -Wpedantic -O2 "${SYSROOT_FLAGS[@]}" \
    "$ROOT_DIR/smc-helper/battery-limit-smc.c" \
    -framework IOKit \
    -o "$BUILD_DIR/battery-limit-smc"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing is enough for a locally built personal utility. No developer
# certificate or network access is required.
codesign --force --deep --sign - "$APP_DIR" >/dev/null

plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

printf 'Built CLI: %s\n' "$BUILD_DIR/battery-limit"
printf 'Built app: %s\n' "$APP_DIR"
printf 'Built SMC helper: %s\n' "$BUILD_DIR/battery-limit-smc"
