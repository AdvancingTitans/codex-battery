# Development & release verification

## Build

```sh
./build.sh
python3 scripts/check-project.py
./scripts/verify-release.sh
```

`VERSION` drives the app version and archive name. `build.sh` compiles both `arm64-apple-macos13.0` and `x86_64-apple-macos13.0`, combines them with `lipo`, copies the three localization bundles and MIT license, applies an ad-hoc signature, and runs parser / threshold / localization checks. It produces `dist/CodexBattery-<VERSION>-universal.zip` and `dist/SHA256SUMS`.

macOS 13 is the deployment target; it is not a claim that every macOS version has been tested on physical hardware. See the release notes for the actual verification environments.

## Diagnostic entry points

After extracting the archive into `.build/check/`:

```sh
".build/check/Codex Battery.app/Contents/MacOS/CodexBattery" --self-test
".build/check/Codex Battery.app/Contents/MacOS/CodexBattery" --check
".build/check/Codex Battery.app/Contents/MacOS/CodexBattery" --preview /tmp/codex-battery-preview.png
```

`--check` makes two real quota reads over one connection and needs an already authenticated CLI. Offline CI never requires an account or secrets. `--settings` opens the actual settings dialog. To inspect a localization, launch an app instance with `-AppleLanguages '(en)'`, `'(zh-Hans)'` or `'(ja)'`.

## Images

README quota illustrations come from `--preview`, which uses the same `batteryImage` function as the live status item. Values are example inputs, not a live account snapshot. Settings screenshots are captured from the app itself. The social card composes the preview:

```sh
swift scripts/render-marketing.swift docs/assets/thresholds.png docs/assets/social-preview.png
```

## Publish a version

1. Update `VERSION`, changelog, exact README download URLs and release notes.
2. Push a reviewed commit and wait for both CI architectures to pass.
3. Tag that exact commit (`v<VERSION>`). Download its `release-macos-15` workflow artifact.
4. Run the project checks, verify signatures / architecture / checksums, and do an authenticated smoke test outside the checkout.
5. Publish that exact ZIP and `SHA256SUMS` in a GitHub Release, without rebuilding the artifact locally.
6. Download the public release again and verify the checksum and smoke test.

The app owns no hosted backend and has no auto-update service. Upgrades are manual. Apple notarization and Homebrew distribution are future options, not current installation promises.
