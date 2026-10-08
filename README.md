<div align="center">

# xcrashlytics

**Your production crashes. Your terminal. Your coding agent.**

[![CI](https://github.com/0xfirattamur/xcrashlytics/actions/workflows/ci.yml/badge.svg)](https://github.com/0xfirattamur/xcrashlytics/actions/workflows/ci.yml) [![Downloads](https://img.shields.io/github/downloads/0xfirattamur/xcrashlytics/total?label=downloads&color=success)](https://github.com/0xfirattamur/xcrashlytics/releases) [![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white)](https://swift.org) [![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)](https://www.apple.com/macos/) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENCE)

</div>

## Your agent has the code. Give it the crash context.

A stack trace alone doesn't tell you how widespread a crash is or which release introduced it. And your agent can't investigate evidence it hasn't seen.

**xcrashlytics is a macOS CLI for Firebase Crashlytics and local Xcode Organizer reports.** It gives you and your agent access to crash messages, app stacks, and impact reports without manually copying data out of the console.

It works with iOS, Android, macOS, and other Crashlytics apps. On iOS, it also reads reports already downloaded by Xcode.

## Start with a question

> What's crashing checkout since the last release?

The investigation has three parts:

| Find the issue | Follow the stack | Measure the impact |
| --- | --- | --- |
| Search by feature, error, or version | Read the crash message and app frames | Get exact event and user counts by version |
| `issues "checkout"` | `show FB-ISSUE_ID` | `breakdown FB-ISSUE_ID --by version` |

Use the evidence to investigate the code, then export a Markdown report to share with the team. The CLI retrieves crash evidence; it doesn't diagnose or fix the code for you.

## Connect your agent

Paste this once into your coding agent:

```text
Set up xcrashlytics in this repo using
https://raw.githubusercontent.com/0xfirattamur/xcrashlytics/main/AGENTS.md.
Install it if needed, scan the apps, and ask me for login or app selection
when required. Save the guidance in this repo's agent instructions,
then list the top 3 issues as JSON and summarize them.
```

Then ask: *“What's crashing checkout since the last release?”*

Agents use structured JSON, check warnings, and follow the [investigation contract](AGENTS.md). The same guide covers setup, authentication, and reporting tool problems without exposing your crash data.

## Or investigate directly

Prefer the terminal? The same commands work without an agent.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/0xfirattamur/xcrashlytics/main/scripts/install.sh | sh
```

It installs into `~/.local/bin`, checks the SHA-256, and needs no `sudo`. You also need the Firebase CLI: `brew install firebase-cli`.

<details>
<summary>Other ways to install: Homebrew, direct download, from source</summary>

**Homebrew.** Homebrew refuses third-party taps until you trust them, so `brew trust` is required once per machine (`HOMEBREW_REQUIRE_TAP_TRUST` defaults to `true`; undo with `brew untrust 0xfirattamur/xcrashlytics`). Skipping it fails with `Error: ... is not trusted`.

```bash
brew tap 0xfirattamur/xcrashlytics https://github.com/0xfirattamur/xcrashlytics
brew trust 0xfirattamur/xcrashlytics
brew install xcrashlytics
```

**Direct download.** Keep the release file names: the `.sha256` file names the tarball it checks.

```bash
VERSION="v0.2.0"
BASE="https://github.com/0xfirattamur/xcrashlytics/releases/download/${VERSION}"
TARBALL="xcrashlytics-${VERSION}-macos-universal.tar.gz"
curl -fLO "${BASE}/${TARBALL}"
curl -fLO "${BASE}/${TARBALL}.sha256"
shasum -a 256 -c "${TARBALL}.sha256"
tar -xzf "${TARBALL}"
mkdir -p "$HOME/.local/bin"
install -m 755 xcrashlytics "$HOME/.local/bin/xcrashlytics"
```

**From source.**

```bash
git clone https://github.com/0xfirattamur/xcrashlytics.git
cd xcrashlytics
swift build -c release    # binary: .build/release/xcrashlytics
```


</details>

More notes (pinning a release, quarantine, signing): [Setup details](docs/commands.md#setup-details).

### Connect your app

From your app repository:

```bash
firebase login
xcrashlytics init --scan
xcrashlytics issues --limit 10
```

The scan discovers your apps and writes `.xcrashlytics.json`. If it finds several, choose a profile with `xcrashlytics use <profile>`. Authentication reuses your Firebase CLI login—no `gcloud`.

## Follow the evidence

### Find what changed after a release

Search by feature or error, narrow to fatal crashes, or focus on one app version. Counts and ranking cover the window you choose—not lifetime totals.

```bash
xcrashlytics issues "checkout" --since 7d
xcrashlytics issues --type FATAL --app-version 6.16.0 --since 30d
```

Need the trend rather than just the total? Add `--by-day --format json` for daily event counts from the Crashlytics report.

### Read the failure, not just the title

`show` brings together the crash message, version range, device information, and latest stack. `events` lets you inspect individual occurrences; `--app-frames-only` keeps the app frames, including first-party libraries configured in your profile.

```bash
xcrashlytics show FB-ISSUE_ID
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json
```

For harder cases, JSON includes custom keys, logs, exception details, and crashed-thread context when available. Add `--breadcrumbs` to inspect the user's recorded steps. You can also pass a Firebase console link directly to `show`.

<details>
<summary>See an example crash detail</summary>

Excerpt using example data:

```text
$ xcrashlytics show FB-I1
Exception: FATAL (SIGABRT)
Crash:     BlurService.swift:77: Fatal error: Array index out of range (user [redacted])
Versions:  first seen 6.14.2 · last seen 6.16.0
Range:     6.15.0 (900) … 6.16.0 (937) (lowest/highest version with events, 90d)
Devices:   iPhone14,5 ×1, iPhone15,2 ×1

Thread 0 (crashed):
  3  ExampleApp                        0x0000000000001000  BlurService.classify(_:) (BlurService.swift:77)
  4  ExampleApp                        0x0000000000002000  ExampleViewController.viewDidLoad() (ExampleViewController.swift:42)
```

</details>

### Measure who is affected

Is this isolated to one release, OS version, or device? `breakdown` uses exact Crashlytics report counts over your chosen window, not estimates from a handful of events.

```bash
xcrashlytics breakdown FB-ISSUE_ID --by version --since 30d
xcrashlytics breakdown FB-ISSUE_ID --by os --since 30d
xcrashlytics breakdown FB-ISSUE_ID --by device --since 30d
```

Version rows also report all users of that version and the percentage affected. Omit the issue id for an app-wide breakdown.

### Look for the pattern behind several issues

One issue is a starting point. `blame` ranks files and symbols across sampled crash events; `groups` brings together issues with the same culprit symbol.

```bash
xcrashlytics blame --since 7d --top 20
xcrashlytics groups
```

Investigating a user's report? `issues --user-id USER_ID --format json` finds issues with matching sampled events. User scans and blame are sample-based; use `issues` and `breakdown` for exact report totals.

### Bring in Xcode reports and missing symbols

For iOS, include App Store and TestFlight crash reports already downloaded by the Xcode Organizer. Both `.crash` and `.ips` formats are supported; no Apple connection is made.

```bash
xcrashlytics issues --xcode
xcrashlytics groups --xcode
```

Local reports have `XC-` ids that work with `show`, `export`, and `open`. Open the Organizer first to download reports, or point at your own files with `--crash-directory`.

For Firebase stacks with unresolved Apple binary frames, supply the crashed build's dSYMs:

```bash
xcrashlytics events FB-ISSUE_ID --latest --dsym path/to/dSYMs --format json
```

Symbolication uses `atos` and preserves the original Firebase symbol. Firebase events carry no binary UUIDs, so the tool warns `DSYM_UNVERIFIED`: you must choose the dSYM from the correct build.

### Take the evidence back to the team

Export a Markdown report for a ticket or chat, or jump to the crashing source line in Xcode:

```bash
xcrashlytics export FB-ISSUE_ID --since 30d --output crash.md
xcrashlytics open FB-ISSUE_ID
```

The report combines the crash message, culprit, impact, daily events, version/OS/device breakdowns, and stack frames. It excludes user ids, custom keys, logs, and breadcrumbs. Still review crash messages and source details before sharing publicly.

[Explore every command and flag →](docs/commands.md)

## Built for scripts, too

Use `--format json` for structured results. Successful responses contain `schemaVersion`, `data`, and `warnings`; failures contain a stable `error.code` and an actionable hint. Check warnings before treating a result as complete.

```bash
xcrashlytics issues --since 7d --format json
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json
```

`issues`, `events`, `blame`, and `breakdown` also support line-by-line `ndjson` output. Within schema version 1, fields are only added, never renamed or removed.

[Output contract and error codes →](docs/commands.md#output-formats-and-stability)

## Privacy

- User ids are never printed raw, and `export` never includes them.
- The only network traffic is to Google. Xcode reports are read from disk.
- Output can still contain stack frames and logs. Check before pasting publicly.

Full rules: [Privacy](docs/commands.md#privacy).

## Limits

- Crashlytics keeps 90 days, so `--since` is capped at `90d`.
- `blame` and `--user-id` use sampled events. Use `issues` and `breakdown` for exact totals.
- Local Xcode crashes need a bundle id in the profile, or `--crash-directory`.
- Releases are not code-signed or notarized. Check the checksum.
- Firebase commands use Google's `v1alpha` Crashlytics API, which has no compatibility guarantee. API changes can require a CLI update.

More: [Platform notes and limits](docs/commands.md#platform-notes-and-limits).

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for setup, tests, and releases.

Found a bug or want a feature? [Open an issue](https://github.com/0xfirattamur/xcrashlytics/issues/new/choose). Reports from AI agents are welcome too. Tell us the command you ran, what you expected, and why the Firebase console or a one-off script was not enough. Leave your crash data out: issues are public.

If this tool saves you time, [star the repository](https://github.com/0xfirattamur/xcrashlytics).

## Trademark

Firebase and Crashlytics are trademarks of Google LLC. This project is not affiliated with, endorsed by, or sponsored by Google.

## License

MIT. See [LICENCE](./LICENCE).
