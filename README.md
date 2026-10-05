<div align="center">

# xcrashlytics

**Crashlytics for AI coding agents.**

Search production crashes, inspect stack traces, and identify hot files without opening the Firebase Console.

[![CI](https://github.com/0xfirattamur/xcrashlytics/actions/workflows/ci.yml/badge.svg)](https://github.com/0xfirattamur/xcrashlytics/actions/workflows/ci.yml)
[![Downloads](https://img.shields.io/github/downloads/0xfirattamur/xcrashlytics/total?label=downloads&color=success)](https://github.com/0xfirattamur/xcrashlytics/releases)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-F05138.svg?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENCE)

</div>

`xcrashlytics` is a macOS CLI for inspecting Firebase Crashlytics issues, events, stacks, and hot files without opening the Firebase console.

It gives developers and AI coding agents a fast path from “production crash” to “file worth opening”:

```bash
xcrashlytics issues "checkout" --format json
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json
xcrashlytics blame --since 7d --top 10 --format json
```

The output is structured for agents, readable in the terminal, and safe to pipe into scripts.

It is built for:

- Developers who want fast, readable crash output in the terminal.
- AI coding agents that need stable JSON while investigating bugs.

Firebase commands work for iOS, Android, macOS, and other Firebase Crashlytics apps. iOS projects can also include the Xcode Organizer's local crash reports (App Store / TestFlight `.crash` logs, already symbolicated) for grouping against Firebase issues.

If this saves you time investigating production crashes, [star the repository](https://github.com/0xfirattamur/xcrashlytics).

<details>
<summary><strong>📖 Table of contents</strong></summary>

- [Install](#install)
- [Authentication](#authentication)
- [Setup](#setup)
- [Quickstart](#quickstart)
- [Agent Usage](#agent-usage)
- [Commands](#commands) — [`issues`](#issues) · [`events`](#events) · [`show`](#show) · [`blame`](#blame) · [`groups`](#groups) · [`open`](#open)
- [Platform Notes](#platform-notes)
- [Privacy](#privacy)
- [Stability](#stability)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [Trademark](#trademark)
- [License](#license)

</details>

## Install

```bash
brew tap 0xfirattamur/xcrashlytics https://github.com/0xfirattamur/xcrashlytics
brew trust 0xfirattamur/xcrashlytics
brew install xcrashlytics
```

> [!IMPORTANT]
> `brew trust` is a required step, not an optional one. Homebrew requires every
> third-party tap to be trusted before it will load a formula
> (`HOMEBREW_REQUIRE_TAP_TRUST` defaults to `true`), so skipping it fails the
> install with `Error: ... is not trusted`. You only need to run it once — trust
> is recorded per-machine in `~/.homebrew/trust.json`, keyed by the tap's remote
> URL.[^tap-trust]

### Single-line installer

Install the latest checksum-verified release into `~/.local/bin`:

```bash
curl -fsSL https://raw.githubusercontent.com/0xfirattamur/xcrashlytics/main/scripts/install.sh | sh
```

The installer resolves the latest release, downloads the universal binary and
its SHA-256 file, verifies the archive, and installs the CLI.

### Direct download

Download the universal binary and checksum from the [latest GitHub release](https://github.com/0xfirattamur/xcrashlytics/releases/latest):

```bash
VERSION="v0.1.0"
curl -fL -o xcrashlytics.tar.gz \
  "https://github.com/0xfirattamur/xcrashlytics/releases/download/${VERSION}/xcrashlytics-${VERSION}-macos-universal.tar.gz"
curl -fL -o xcrashlytics.tar.gz.sha256 \
  "https://github.com/0xfirattamur/xcrashlytics/releases/download/${VERSION}/xcrashlytics-${VERSION}-macos-universal.tar.gz.sha256"
shasum -a 256 -c xcrashlytics.tar.gz.sha256
tar -xzf xcrashlytics.tar.gz
mkdir -p "$HOME/.local/bin"
install -m 755 xcrashlytics "$HOME/.local/bin/xcrashlytics"
```

The release binary is universal for Apple Silicon and Intel Macs. Releases are
not code-signed or notarized; verify the checksum before installing.

From source:

```bash
git clone https://github.com/0xfirattamur/xcrashlytics.git
cd xcrashlytics
swift build -c release
```

Prebuilt binaries are available on [GitHub releases](https://github.com/0xfirattamur/xcrashlytics/releases).

> [!NOTE]
> Binaries are not code-signed or notarized. Homebrew is the supported install path and runs without Gatekeeper friction[^gatekeeper]. If you download a binary directly from the releases page in a browser, clear the quarantine flag once: `xattr -dr com.apple.quarantine ./xcrashlytics`.

## Authentication

`xcrashlytics` uses your existing Firebase CLI login.

```bash
npm install -g firebase-tools
firebase login
```

> [!TIP]
> The tool reuses the token stored by `firebase-tools`. It does not require `gcloud`, a custom OAuth app, or a backend service.

## Setup

Run this inside your app repository to find every `GoogleService-Info.plist` / `google-services.json` and write one profile per app, bundle id included:

```bash
xcrashlytics init --scan
```

`--scan` skips build outputs and vendored copies (`.build`, `DerivedData`, `Pods`, `node_modules`, `build`). It keeps an existing active profile, activates the app when it finds exactly one, and otherwise asks you to pick with `xcrashlytics use <profile>` — it never guesses among several apps.

Or name one profile by hand:

```bash
xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --bundle-id com.example.app
xcrashlytics init --app-id 1:1234567890:android:abcdef --profile release
```

Either way `init` writes `.xcrashlytics.json`:

```json
{
  "activeProfile": "release",
  "profiles": {
    "release": { "appId": "1:1234567890:ios:abcdef", "bundleId": "com.example.app" }
  }
}
```

Commands read this config from the current directory, so run them from the repo root.

> [!TIP]
> The file holds Firebase app ids only — no secrets — so commit it and the whole
> team (and CI) shares the setup. Authentication stays in `firebase login`.

Add more environments by running `init` again with a different profile, then switch between them:

```bash
xcrashlytics init --app-id 1:1234567890:ios:staging --profile staging
xcrashlytics use staging
```

`use <name>` only switches between profiles already in the config; run `init --scan` again to pick up new Firebase config files.

## Quickstart

Firebase-only flow:

```bash
xcrashlytics issues --limit 20
xcrashlytics issues "checkout" --format json
xcrashlytics show FB-ISSUE_ID --format json
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json
xcrashlytics blame --top 20 --since 7d --format json
```

iOS with local Xcode crashes:

```bash
xcrashlytics issues --xcode --limit 20
xcrashlytics groups --xcode --format text
xcrashlytics issues "blur detection" --xcode --format json
```

> [!IMPORTANT]
> Local Xcode crashes come from the Xcode Organizer's store at
> `~/Library/Developer/Xcode/Products/<bundle-id>/Crashes/`. Xcode downloads
> App Store and TestFlight crash reports into it when you open the Organizer
> (<kbd>Window</kbd> → <kbd>Organizer</kbd> → <kbd>Crashes</kbd>) — the tool only reads those local files and
> never talks to Apple. Open the Organizer once after a release so fresh
> crashes are on disk, and set the profile's bundle id with
> `init --bundle-id` — every Xcode crash command (`issues --xcode`, `groups --xcode`,
> `show XC-…`, `open XC-…`) refuses to run without one, unless you pass an explicit
> `--crash-directory`. App extensions are covered: Xcode stores their reports
> under the containing app (`com.example.app.widget` → `com.example.app`), so
> that directory is scanned too and only reports with the extension's bundle id
> are kept.

JSON output is suitable for scripts and agent calls:

```bash
xcrashlytics issues "blur" --format json
```

## Agent Usage

See [AGENTS.md](./AGENTS.md) for the full agent contract: error codes, exit codes, and JSON stability guarantees.

Recommended investigation loop:

```bash
xcrashlytics issues "<feature-or-error>" --format json
xcrashlytics issues --user-id USER_ID --events-per-issue 10 --format json
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json
xcrashlytics events FB-ISSUE_ID --user-id USER_ID --format json
xcrashlytics blame --since 7d --top 20 --format json
```

> [!WARNING]
> Use JSON or NDJSON[^ndjson]. Do not scrape text output — only the structured formats are stability-guaranteed.

## Commands

### `issues`

List and search Firebase Crashlytics issues.

```bash
xcrashlytics issues --limit 20
xcrashlytics issues "blur detection" --limit 20
xcrashlytics issues "blur detection" --search-limit 500 --format json
xcrashlytics issues --match BlurDetectionService --type EXC_BAD_ACCESS --min-events 10
xcrashlytics issues --app-version 6.16.0
xcrashlytics issues --since-version 6.16.0
xcrashlytics issues --file BlurDetectionService.swift
xcrashlytics issues --symbol 'BlurDetectionService.classifyWithML(_:)'
xcrashlytics issues --since 24h --format json
xcrashlytics issues --domain com.metrickit.diagnostics.cpu
xcrashlytics issues --user-info-key reason="cpu spike"
xcrashlytics issues --user-id USER_ID --events-per-issue 10 --format json
xcrashlytics issues --since 7d --by-day --format json
xcrashlytics issues "com.metrickit.diagnostics.cpu" --format json
xcrashlytics issues "blur" --format ndjson
xcrashlytics issues --xcode --format json
```

Text output is compact:

```text
FB-I1   EXC_BAD_ACCESS   v6.16.0   Crash in Checkout   42 events / 12 users
```

<details>
<summary>JSON output is agent-readable — <em>click to expand</em></summary>

```json
{
  "query": "blur detection",
  "limit": 20,
  "searchLimit": 200,
  "fetchedIssuesCount": 200,
  "matchedIssuesCount": 2,
  "relatedGroups": [
    {
      "issueIds": ["FB-I1", "FB-I7"],
      "reason": "same crash signature"
    }
  ],
  "issues": [
    {
      "id": "FB-I1",
      "firebaseIssueId": "I1",
      "title": "[Core] BlurDetectionService.swift - BlurDetectionService.classifyWithML(_:)",
      "exceptionType": "EXC_BAD_ACCESS",
      "file": "BlurDetectionService.swift",
      "topAppSymbol": "BlurDetectionService.classifyWithML(_:)",
      "appVersion": "6.16.0",
      "eventsCount": 42,
      "impactedUsersCount": 12
    }
  ]
}
```

</details>

Search behavior:

- Bare `issues` fetches and displays `--limit` issues.
- Queries and filters fetch a wider search window by default, then display the first `--limit` matches.
- Reverse-DNS-like queries such as `com.metrickit.diagnostics.cpu` search latest event metadata when issue fields do not match.
- `--domain` and `--user-info-key key` or `--user-info-key key=value` filter latest event metadata.
- `--user-id USER_ID` accepts the raw Firebase user id and filters sampled events. Increase `--events-per-issue` for a deeper issue search.
- `--by-day` adds per-issue daily event counts for displayed issues.
- `--format ndjson` emits one compact issue JSON object per line, each with `"schemaVersion": 1` (also supported by `events` and `blame`).
- `--search-limit N` controls how many Firebase issues are fetched before filtering.
- `--all` searches up to 2000 Firebase issues.
- Empty JSON search results include a `hint` when the fetched window may be too small, and do not suggest widening after all fetched issues are exhausted.
- `relatedGroups` gives compact same-signature hints without quadratic candidate-pair output.
- When `--xcode` is enabled and local crashes look unsymbolicated, JSON output includes a `symbolicationHint`.
- `--crash-directory <path>` (repeatable) scans explicit Xcode crash directories instead of the bundle-id default, and needs no bundle id.

### `events`

List Firebase sample events and frames for one or more issues.

```bash
xcrashlytics events FB-I1 --limit 10
xcrashlytics events FB-I1 --since 7d --format json
xcrashlytics events FB-I1 --format json
xcrashlytics events FB-I1,FB-I2 --latest --frames-only --format json
xcrashlytics events --issues FB-I1,FB-I2 --latest --app-frames-only --format json
xcrashlytics events FB-I1 --crashing-thread-only --format json
xcrashlytics events FB-I1 --no-system-frames --format json
xcrashlytics events FB-I1 --user-id USER_ID --format json
xcrashlytics events FB-I1 --format ndjson
```

Event JSON includes app version/build, device model, OS version, event time, memory/storage when Firebase provides it, hashed user id, and frames.

Frame filter flags imply `--frames-only`:

- `--app-frames-only`
- `--no-system-frames`
- `--crashing-thread-only`

This keeps agent stack payloads small and avoids system-frame noise.

### `show`

Show one crash or Firebase event, by id or by a link pasted from the Firebase console.

```bash
xcrashlytics show FB-I1
xcrashlytics show FB-I1 --format json
xcrashlytics show FB-I1/events/E1 --format json
xcrashlytics show XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
xcrashlytics show 'https://console.firebase.google.com/project/my-app/crashlytics/app/ios:com.example.app/issues/3aed…?sessionEventKey=…' --format json
```

Firebase issue ids include issue detail plus latest event frames when available. Firebase event ids show that event's frames and metadata under the same names `events` uses (`appBuild`, `processState`, memory and storage bytes, …), plus the issue's aggregates; when the event carries no exception type, the issue's is used. The event part may be the API event id or a `sessionEventKey` copied from the console. Xcode ids read the Organizer's local `.crash` reports; `--crash-directory <path>` (repeatable) scans explicit directories instead of the profile's.

Console links carry the app's bundle id, not its Firebase app id, so `show` queries the profile whose `bundleId` matches the link — not necessarily the active one — and refuses links for apps it has no profile for. A `sessionEventKey` in the link selects that event when it is among the newest 100 — the key's suffix after the last `_` is tried as the event id; otherwise the issue is shown with an `EVENT_NOT_RESOLVED` warning. Only `https://console.firebase.google.com` links are accepted.

For Firebase ids, the same frame filters as `events` trim the displayed frames: `--app-frames-only`, `--no-system-frames`, `--crashing-thread-only`.

### `blame`

Aggregate top blamed Firebase files and symbols across recent sampled events.

```bash
xcrashlytics blame --top 20 --since 7d --format json
xcrashlytics blame --issue-limit 100 --events-per-issue 5 --concurrency 6
xcrashlytics blame --top 20 --since 7d --format ndjson
```

<details>
<summary>Example JSON — <em>click to expand</em></summary>

```json
{
  "items": [
    {
      "file": "BlurDetectionService.swift",
      "line": 42,
      "symbol": "BlurDetectionService.classifyWithML(_:)",
      "eventCount": 12,
      "users": 5,
      "exampleIssueId": "FB-I1",
      "exampleEventId": "FB-I1/events/E1",
      "topIssueIds": ["FB-I1", "FB-I7"]
    }
  ]
}
```

</details>

Defaults are tuned for quick agent loops:

- `--issue-limit 30`
- `--events-per-issue 1`
- `--concurrency 6`

Increase those values only when you need a deeper scan.

### `groups`

Group related Firebase issues and optional local Xcode crashes.

```bash
xcrashlytics groups --format text
xcrashlytics groups --firebase-limit 100 --format json
xcrashlytics groups FB-I1 --format json
xcrashlytics groups --xcode --format json
xcrashlytics groups --limit 10 --format json
```

Firebase-only projects group Firebase issues with other Firebase issues. iOS projects can add `--xcode` to include local crash reports. `--limit N` caps the number of groups shown, and `--crash-directory <path>` (repeatable) scans explicit Xcode crash directories without a bundle id.

### `open`

Open the source of a crash in Xcode.

```bash
xcrashlytics open FB-I1
xcrashlytics open FB-I1/events/E1
xcrashlytics open XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
```

Both id kinds open the crashing source line in Xcode via `xed`. Crash frames carry file names only, so run from the app's repo root — the file is resolved inside the current directory, and ambiguous or missing files are an error rather than a guess. Xcode ids fall back to opening the raw report when no source location is available, and accept `--crash-directory` like `show`.

## Platform Notes

Android projects use Firebase commands directly. There is no Android Studio local crash source in the core design.

iOS projects can combine Firebase with local Xcode crash reports through `issues --xcode` and `groups --xcode`. The local reports are the ones the Xcode Organizer has already downloaded — the tool reads them from disk and has no connection to Apple's crash service.

## Privacy

> [!CAUTION]
> Crash reports may contain sensitive data.

- Raw Firebase user ids are not emitted in normal output.
- Raw Firebase user ids can be passed as filter input with `--user-id`.
- User ids are hashed when included.
- Raw Firebase payloads are not printed by default.
- Saved snapshots are not required for normal use.

## Stability

Every `--format json` success is an envelope; errors use the same `schemaVersion`:

```json
{ "schemaVersion": 1, "data": { "issues": [] }, "warnings": [] }
{ "schemaVersion": 1, "error": { "code": "BAD_INPUT", "message": "…", "hint": "…" } }
```

- `data` holds the command's result: `issues`, `events`, `groups`, and `blame` return an object; `show` returns the crash itself.
- `warnings` lists non-fatal problems as `{ "code", "message", "path"? }` — e.g. `XCODE_PARSE_FAILED`, `XCODE_SCAN_FAILED`, `SEARCH_TRUNCATED`, `SCAN_TRUNCATED`, `EVENT_NOT_RESOLVED`. With JSON they are only in the envelope; with text and NDJSON they go to stderr.
- NDJSON lines are records, each with its own `"schemaVersion": 1`; stdout never carries warnings.
- Ids are canonical everywhere: `FB-<issue>`, `FB-<issue>/events/<event>`, `XC-<incident>`. Raw provider ids are in `providerId` / `firebaseIssueId` / `firebaseEventId`.

Within `schemaVersion` 1, fields are only added, never renamed or removed. Error codes and exit codes are stable.

> [!WARNING]
> The tool talks to Google's `v1alpha`[^v1alpha] Crashlytics API, which is unversioned and undocumented — if Google changes it, commands may break until a new release adapts.

## Configuration

Top-level keys in `.xcrashlytics.json`:

| Key | Meaning |
| --- | --- |
| `appId` | Optional fallback Firebase app id, used when no active profile is set. Android and iOS app ids both work. |
| `activeProfile` | Optional active profile name selected by `xcrashlytics use <profile>`. |
| `profiles` | Named Firebase app profiles, written by `init --scan` or `init --profile`. |

Each entry under `profiles` holds:

| Key | Meaning |
| --- | --- |
| `appId` | Firebase app id for that environment/platform. |
| `bundleId` | App bundle id. Scopes Xcode Organizer crash scanning to `~/Library/Developer/Xcode/Products/<bundleId>`, plus the containing app's directory for app extensions. iOS-only; optional. |
| `sourcePath` | Optional path the profile was discovered from, e.g. `Staging/GoogleService-Info.plist` or `app/google-services.json`. |

> [!TIP]
> `init --scan` fills `bundleId` from each `GoogleService-Info.plist` / `google-services.json`; with manual setup pass `init --bundle-id`. Every `--xcode` command needs it unless you pass `--crash-directory`.

## Contributing

Contributions are welcome. Useful issues and PRs include:

- the command you ran
- the output you expected
- whether the output is for humans, agents, or both
- why the Firebase console or a one-off script was not enough

## Trademark

Firebase and Crashlytics are trademarks of Google LLC. This project is not affiliated with, endorsed by, or sponsored by Google.

## License

MIT. See [LICENCE](./LICENCE).

[^gatekeeper]: macOS quarantines files downloaded via a browser and blocks unsigned ones on first run. Homebrew *formula* installs are exempt — they aren't quarantined — so an unsigned CLI runs fine.
[^tap-trust]: Only taps under the `Homebrew` org are trusted implicitly, so there is no way for a third-party tap to be pre-approved on your behalf — trusting it is a local, per-machine decision. Undo it any time with `brew untrust 0xfirattamur/xcrashlytics`.
[^ndjson]: Newline-delimited JSON — one compact JSON object per line. Streams well and is trivial to parse line-by-line in scripts and agents.
[^v1alpha]: An early, pre-stable Google API tier. It carries no compatibility guarantee and can change without notice.
