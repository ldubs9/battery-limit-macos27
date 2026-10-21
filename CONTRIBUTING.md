# Contributing

Battery Limit controls real charging and adapter state. Changes must fail closed and must not silently write arbitrary SMC keys.

Before opening a pull request:

```bash
./tests/test.sh
```

Please include the exact macOS version, build, Mac model, and whether the test used native PowerUI or a CHIE helper. Do not include battery serial numbers, sudo credentials, or private machine logs.
