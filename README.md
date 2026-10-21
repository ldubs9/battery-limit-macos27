# Battery Limit for macOS 27

A small native menu-bar utility and CLI for macOS 27 (Tahoe) charge limits, with an optional force-discharge loop for Macs whose firmware exposes the `CHIE` adapter-control SMC key.

This project was built for and verified on:

- macOS `27.0.1`, build `26A434`
- MacBook Air `Mac16,12`, Apple M4
- native PowerUI charge-limit support for `80, 85, 90, 95, 100`

## Why this exists

The older `battery` app controls charging through legacy SMC keys such as `CH0B`, `CH0C`, and `CHTE`. On this macOS 27 firmware those keys are unavailable or entitlement-gated, while macOS's private `PowerUISmartChargeClient` service still works. Battery Limit uses that native service for the normal charge limit instead of pretending that the old SMC path succeeded.

The optional force-discharge mode uses a separate, narrowly scoped `CHIE` helper. When enabled:

1. If the Mac is plugged in and the battery is **above** the configured native limit, the helper disables adapter power so the Mac runs from its battery.
2. When the battery reaches **at or below** the configured limit, adapter power is restored.
3. The app polls every 15 seconds and restores adapter power when force discharge is disabled or the app exits normally.

This is deliberately not a general SMC utility. The helper only accepts `CHIE` and the two known values `00` (adapter enabled) and `08` (adapter disabled). Unsupported hardware fails closed.

## Install and launch at login

From a checked-out copy of this repository:

```bash
./install.sh
```

The installer:

- builds the CLI, menu-bar app, and SMC helper;
- installs the app at `~/Applications/BatteryLimit.app`;
- installs the helper at `/usr/local/libexec/battery-limit-smc`;
- installs a narrowly scoped `/etc/sudoers.d/battery-limit` rule for the helper;
- registers `~/Library/LaunchAgents/com.ecc.BatteryLimit.plist`, so the menu-bar app launches at login.

The helper installation asks for administrator approval because it changes low-level adapter-control state. No password is stored by this project.

If the legacy `battery` helper is already installed and its sudoers rules allow `CHIE -r`, `CHIE -w 00`, and `CHIE -w 08`, install without adding a second helper:

```bash
./install.sh --skip-helper
```

### Finding the app

The app is a menu-bar-only utility, so it has no Dock window. It is located at:

```text
~/Applications/BatteryLimit.app
```

Open it directly with:

```bash
open ~/Applications/BatteryLimit.app
```

Or in Finder use **Go → Home → Applications → BatteryLimit**. Its controls appear under the battery icon/text in the menu bar.

Check the login item with:

```bash
launchctl print "gui/$(id -u)/com.ecc.BatteryLimit"
```

Remove the login item without deleting the app with:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.ecc.BatteryLimit.plist"
```

## Use

The installer places the CLI beside the app:

```bash
CLI="$HOME/Applications/battery-limit"
"$CLI" status
"$CLI" limits
"$CLI" set 80
"$CLI" disable
```

The menu-bar app exposes 80%, 85%, 90%, 95%, and Disable (100%). The native limit is persisted by macOS's PowerUI service.

### Force discharge

Enable the automatic above-limit discharge loop:

```bash
"$CLI" force-discharge enable
```

Or select **Force discharge above limit** in the menu-bar menu. Inspect state with:

```bash
"$CLI" force-discharge status
"$CLI" status
```

Disable it and restore adapter control:

```bash
"$CLI" force-discharge disable
```

Force discharge requires a native or legacy CHIE helper and an explicit passwordless sudoers rule. If the menu says **install SMC helper**, run `./install.sh` or use `--skip-helper` only when a compatible legacy helper is already configured.

Do not run this together with the old `battery maintain` daemon. Stop the old daemon first and verify that it has restored adapter control before switching tools; two loops must not write the same power state.

## Build and test

This uses the Apple Command Line Tools; full Xcode is not required.

```bash
./build.sh
./tests/test.sh
```

Artifacts:

- `build/battery-limit` — CLI
- `build/BatteryLimit.app` — native menu-bar app
- `build/battery-limit-smc` — restricted CHIE helper

The build creates an ad-hoc local signature. It does not install anything, change SMC state, or modify launch agents. The test suite performs only read-only PowerUI and battery queries; it does not write `CHIE`.

## Limitations and safety

- Native charge limits are limited to values exposed by macOS; on the verified Mac this is 80–100% in 5% steps.
- The PowerUI framework and AppleSMC user-client are private Apple interfaces and may change in a future macOS update.
- Force discharge can make the Mac run from its battery while physically plugged in. Use it only when you understand the resulting power behavior.
- The helper is intentionally hardware-specific and refuses arbitrary SMC keys or values.
- If the app is terminated abnormally while force discharge is active, run `force-discharge disable` to restore adapter control.
- This is personal-use software, not notarized or distributed through the Mac App Store.

## License

The project code is released under the MIT License. See [LICENSE](LICENSE).
