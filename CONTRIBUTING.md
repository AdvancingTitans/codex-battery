# Contributing

Keep Codex Battery a small, native Codex quota indicator. Bug reports, translations, accessibility improvements and focused fixes are welcome.

1. Open an issue before proposing a new product feature.
2. Build with `./build.sh` on macOS with Xcode Command Line Tools.
3. Run `python3 scripts/check-project.py` and `./scripts/verify-release.sh`.
4. For visual changes, inspect `--preview` in light and dark appearance and include the actual output.
5. Keep the keys and format placeholders in all three `Resources/*.lproj/Localizable.strings` files aligned. Update all README variants when behavior changes.

PRs should explain the user-visible behavior, relevant checks and any limits. Do not include tokens, authentication files, personal usage snapshots or machine-specific paths. New dependencies need a concrete justification.

## Languages

The interface follows macOS preferred languages. English strings are the fallback keys; Simplified Chinese and Japanese ship as native `.strings` resources. Native-speaker improvements are welcome.

## Release

`VERSION` is the version source. See [release verification](docs/DEVELOPMENT.md). The tag workflow publishes the exact tested CI artifact only after both architectures pass. Verify the public download with a clean extraction and authenticated smoke check.
