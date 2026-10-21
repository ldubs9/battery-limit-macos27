# Verification record

Target: MacBook Air `Mac16,12`, Apple M4, macOS `27.0.1` build `26A434`.

## Root-cause evidence

- The legacy `battery` CLI reported `smc charging unknown` on this firmware.
- Read-only probes showed the legacy charge keys used by the old app (`CH0B`, `CH0C`, `CHTE`, `bfF0`, `bfD0`, and `bfE0`) were unavailable.
- The live `PowerUISmartChargeClient` service reported support and advertised `80, 85, 90, 95, 100`.
- The native implementation therefore uses PowerUI for the normal limit and does not claim that the legacy SMC charge loop succeeded.

## Force-discharge implementation

- `BLAdapterController` supports the verified legacy helper path and the new restricted helper at `/usr/local/libexec/battery-limit-smc`.
- The new helper accepts only `CHIE` reads and `CHIE` writes of `00` or `08`; arbitrary keys and values are rejected before opening AppleSMC.
- The menu-bar app polls battery state every 15 seconds. With force discharge enabled, it disables adapter control when the battery is above the configured limit and restores adapter control at or below the limit.
- Normal app termination restores adapter control if this process disabled it.

No force-discharge write was performed during verification, so the machine's adapter state was not changed by the test suite.

## Build and test evidence

Commands:

```text
./build.sh
./tests/test.sh
bash -n build.sh install.sh tests/test.sh
```

Observed results:

```text
PASS: CLI help, native read-only status, force-discharge status, limits, and input guards
PASS: app bundle plist and ad-hoc signature
shell_syntax=ok
codesign=ok
```

The resulting CLI, helper, and app are arm64 Mach-O binaries. The app bundle has a valid plist and an ad-hoc signature.

Direct read-only verification on the target:

```text
Battery Limit status
macOS: 27.0.1
PowerUI supported: yes
Available limits: 80%, 85%, 90%, 95%, 100%
Current limit: 80% (enabled)
CHIE adapter control: enabled (/usr/local/co.palokaj.battery/smc)
```

The new helper's direct read returned `00`. An invalid `CHIE` write value (`09`) was rejected with exit status 2; no SMC write was attempted.

## Local installation

The app was copied to:

```text
/Users/Luca_1/Applications/BatteryLimit.app
```

The CLI was installed and read back successfully from:

```text
/Users/Luca_1/Applications/battery-limit
```

The per-user launch-agent plist was created and linted successfully at:

```text
/Users/Luca_1/Library/LaunchAgents/com.ecc.BatteryLimit.plist
```

The menu-bar app process was observed running from the installed path. The plist has `RunAtLoad=true`; macOS will load it automatically at the next user login. The current session was started manually with `open`; launchd bootstrap was not run during this verification.
