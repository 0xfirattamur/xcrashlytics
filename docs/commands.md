# Command reference

Full reference for every `xcrashlytics` command. For the short version, see the [README](../README.md). For the JSON contract and error handling for agents, see [AGENTS.md](../AGENTS.md).

## Contents

- [Setup details](#setup-details)
- [Common questions](#common-questions)
- [Commands](#commands): [`issues`](#issues) · [`events`](#events) · [`show`](#show) · [`export`](#export) · [`breakdown`](#breakdown) · [`blame`](#blame) · [`groups`](#groups) · [`open`](#open) · [`init`](#init) · [`use`](#use)
- [Output formats and stability](#output-formats-and-stability)
- [Privacy](#privacy)
- [Configuration](#configuration)
- [Platform notes and limits](#platform-notes-and-limits)

## Setup details

`xcrashlytics` uses your existing Firebase CLI login. It reads the token that `firebase-tools` stores in `~/.config/configstore/firebase-tools.json` (`$XDG_CONFIG_HOME` is honored). It needs no `gcloud` and no custom OAuth app.

`init` writes `.xcrashlytics.json` in the current directory. It holds Firebase app ids only, no secrets, so you can commit it. Run all other commands from the repo root. See [`init`](#init) and [Configuration](#configuration) for profiles and extensions.

Install notes:

- The installer puts the latest release in `~/.local/bin`, with a SHA-256 check and no `sudo`. It needs no Homebrew tap, and macOS does not quarantine files that `curl` downloads.
- Add `~/.local/bin` to your `PATH` if it is not there yet.
- Pin a release: `curl -fsSL https://raw.githubusercontent.com/0xfirattamur/xcrashlytics/main/scripts/install.sh | XCRASHLYTICS_VERSION=v0.2.0 sh`.
- The Firebase CLI is needed for login: `brew install firebase-cli` (or `npm install -g firebase-tools`).
- The release binary is universal (Apple Silicon and Intel). It is not code-signed or notarized, so check the checksum.
- If you download it in a browser, macOS quarantines it: run `xattr -dr com.apple.quarantine ./xcrashlytics` once. The installer and Homebrew do not trigger this.

## Common questions

Add `--format json` when a script or an agent reads the output. Ids look like `FB-<issue>` (Firebase) or `XC-<uuid>` (local Xcode crash).

| You want to know | Run |
| --- | --- |
| What is crashing most? | `xcrashlytics issues --limit 20` |
| What happened over the last month? | `xcrashlytics issues --since 30d` |
| Is there a crash about a feature or error? | `xcrashlytics issues "blur detection"` |
| Only fatal crashes in one version? | `xcrashlytics issues --type FATAL --app-version 6.16.0` |
| What does the stack look like? | `xcrashlytics events FB-ISSUE_ID --latest --app-frames-only` |
| Everything about one crash, with its message? | `xcrashlytics show FB-ISSUE_ID` |
| Which versions, OS versions, or devices? | `xcrashlytics breakdown FB-ISSUE_ID --by version` (or `os`, `device`) |
| How is the whole app doing per version? | `xcrashlytics breakdown --by version` |
| Which crashes hit one user? | `xcrashlytics issues --user-id USER_ID` |
| What did the `fatalError` say? | `xcrashlytics show FB-ISSUE_ID` (`Crash:` line; `crashMessage` in JSON) |
| Which files crash the most? | `xcrashlytics blame --since 7d --top 20` |
| Which issues share a cause? | `xcrashlytics groups` |
| How do I share a crash? | `xcrashlytics export FB-ISSUE_ID --output crash.md` |
| I have a Firebase console link | `xcrashlytics show 'https://console.firebase.google.com/…'` |
| Open the crashing line in Xcode? | `xcrashlytics open FB-ISSUE_ID` (from the repo root) |
| What crashed in TestFlight / App Store (local Xcode reports)? | `xcrashlytics issues --xcode` |
| Vendor frames show only addresses | `xcrashlytics events FB-ISSUE_ID --latest --dsym path/to/dSYMs` |

## Commands

All commands read `.xcrashlytics.json` from the current directory. `--since` takes `24h`, `7d`, `2w`, `30m`, and so on, up to `90d` (the Crashlytics limit); `all` means `90d`. A larger window is `BAD_INPUT`. Every command also takes `--version` and `-h/--help`.

### `issues`

List and search Crashlytics issues, ranked by impact over a window (default 7 days).

```bash
xcrashlytics issues --limit 20
xcrashlytics issues "blur detection" --since 30d
xcrashlytics issues --type FATAL --min-events 10 --app-version 6.16.0
xcrashlytics issues --file BlurService.swift
xcrashlytics issues --user-info-key reason="cpu spike"
xcrashlytics issues --since 7d --by-day --format json
xcrashlytics issues --xcode --format ndjson
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<query>` | | Text to find in title, subtitle, module, file, or symbol. |
| `--match TEXT` | | Case-insensitive substring filter on the same fields. |
| `--type TYPE` | | Error type, case-insensitive: `FATAL`, `NON_FATAL`, `ANR`, `EXC_BAD_ACCESS`, … Also matches the exception type of local crashes. |
| `--min-events N` | | Only issues with at least N events. |
| `--app-version V` | | Only events of version `V` (`6.16.0`, or `6.16.0 (937)` for one build). |
| `--since-version V` | | Only events of versions at or above `V`. |
| `--file NAME` / `--symbol NAME` | | Exact match on the issue's top file or symbol. |
| `--domain TEXT` | | Match error domain fields and subtitles. |
| `--user-info-key K[=V]` | | Match event `customKeys`/`userInfo`. Repeatable. |
| `--user-id ID` | | Only issues with a sampled event of this user (raw Firebase id). |
| `--events-per-issue N` | 50 | Events scanned per issue for `--user-id`. |
| `--since` | `7d` | Window for counts and ranking. |
| `--by-day` | off | Add exact events per UTC day for the displayed issues. |
| `--limit N` | 20 | Issues to show (and, separately, Xcode crashes). |
| `--search-limit N` / `--all` | | Firebase issues fetched before filtering (at most 2000; `--all` = 2000). |
| `--xcode` | off | Also list local Xcode Organizer crashes. |
| `--crash-directory PATH` | | Scan this Xcode crash directory instead of the bundle-id default. Repeatable; implies `--xcode`. |
| `--format` | `text` | `text`, `json`, or `ndjson`. |

- Bare `issues` fetches `--limit` issues. With a query or filter, a wider window is fetched first (raise it with `--search-limit` or `--all`), then the first `--limit` matches are shown. An empty JSON result has a `hint` that says when a wider scan could help.
- `--app-version` and `--since-version` are exact filters: ranking and counts then cover only events of those versions. JSON lists them as `matchedVersions`. If none match, the `hint` names the versions seen in the window.
- `firstSeenVersion` and `lastSeenVersion` are the versions of the first and the most recent event. They are not a range. The last-seen version can be lower than the first. For the real range use [`breakdown`](#breakdown) or `show`.
- Non-fatal issues are titled at the Crashlytics SDK's `recordError` frame, so `file` and `topAppSymbol` are empty. [`export`](#export) and [`blame`](#blame) name the app code that recorded the error.
- With `--xcode`, local crashes use the same filters and their own `--limit`.

<details>
<summary>Example output</summary>

```text
FB-I1   FATAL   first seen 6.14.2 · last seen 6.16.0   [ExampleApp] BlurService.swift - BlurService.classify(_:)   42 events / 12 users   last event 2026-06-14
```

```json
{
  "data": {
    "fetchedIssuesCount": 5,
    "issues": [
      {
        "id": "FB-I1",
        "source": "firebase",
        "firebaseIssueId": "I1",
        "title": "[ExampleApp] BlurService.swift - BlurService.classify(_:)",
        "errorType": "FATAL",
        "exceptionType": "FATAL",
        "file": "BlurService.swift",
        "topAppSymbol": "BlurService.classify(_:)",
        "module": "ExampleApp",
        "signal": "SIGABRT",
        "subtitle": "Fatal error: Array index out of range",
        "appVersion": "6.16.0",
        "firstSeenVersion": "6.14.2",
        "lastSeenVersion": "6.16.0",
        "eventsCount": 42,
        "impactedUsersCount": 12,
        "lastSeenAt": "2026-06-14T09:30:00Z"
      }
    ],
    "limit": 20,
    "matchedIssuesCount": 5,
    "relatedGroups": [{ "issueIds": ["FB-I1", "FB-I5"], "reason": "same crash signature" }],
    "searchLimit": 20,
    "window": { "since": "2026-06-08T12:00:00Z", "until": "2026-06-15T12:00:00Z" }
  },
  "schemaVersion": 1,
  "warnings": []
}
```

With a query, `data` also has `query`. `exceptionType` repeats `errorType` for Firebase issues. With `--by-day`, each issue gets `dailyEvents` (UTC days, empty days omitted).

</details>

### `events`

List sample events and stack frames for one or more issues.

```bash
xcrashlytics events FB-I1 --limit 10
xcrashlytics events FB-I1 --latest --app-frames-only --format json
xcrashlytics events FB-I1,FB-I2 --latest --crashing-thread-only
xcrashlytics events FB-I1 --user-id USER_ID --since 30d --format json
xcrashlytics events FB-I1 --latest --breadcrumbs --format json
xcrashlytics events FB-I1 --latest --dsym path/to/dSYMs --format json
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<issue-id>` / `--issues A,B` | | One or more issue ids, comma-separated. |
| `--limit N` | 10 | Events per issue. Not combinable with `--latest`. |
| `--latest` | off | Only the newest event. |
| `--since` | newest events of the last `90d` | Only events inside this window. |
| `--user-id ID` | | Only events of this user (raw Firebase id). |
| `--frames-only` | off | Only frame data (plus `crashInfo`, `crashMessage`, `exception`, `crashedThread`). |
| `--app-frames-only` | off | Only app frames. Implies `--frames-only`. |
| `--no-system-frames` | off | Drop redacted, deduplicated, and system/SDK frames. Implies `--frames-only`. |
| `--crashing-thread-only` | off | Only the crashed thread's frames. Implies `--frames-only`. |
| `--breadcrumbs` | off | Include Analytics breadcrumbs (can be hundreds of entries). Ignored with frame-only output. |
| `--dsym PATH` | | `.dSYM` bundle, or a directory searched for them. Repeatable. |
| `--format` | `text` | `text`, `json`, or `ndjson`. |

- An event has app version and build, device, OS, time, hashed user id, memory and storage (when Firebase has them), and frames. Frame `index` is the position in the original stack, also after filtering.
- It also has what explains the crash: `crashMessage` (a Swift `fatalError` text, or `<type>: <message>` for an exception), `crashInfo`, `exception {type, message}`, `customKeys` (`{}` when empty), `logs` (`[]` when empty), and `crashedThread`.
- `--app-frames-only` drops system, Crashlytics SDK, library-less, and third-party frames. Frames of your profile's `appLibraries` count as app frames.
- If a filter removes every frame, JSON says why (`noFramesReason`, `appFramesAbsent`, `crashedLibrary`) and text prints `(no app frames in this event; crashed in <library>)`. `--crashing-thread-only` on an event without a crashed thread (typical for non-fatals) warns `NO_CRASHED_THREAD`.
- `--dsym` fills in `symbol`, `file`, and `line` from the dSYM and keeps Crashlytics' name as `firebaseSymbol`. Events carry no binary UUIDs, so the dSYM cannot be checked against the crashed build: you get `DSYM_UNVERIFIED`. Use the dSYM of the build that crashed.
- `--user-id` scans up to 50 events per issue (or `--limit` if higher). JSON reports `scanDepth` and `scannedEvents`. `SCAN_TRUNCATED` means older events in the window may match too.

### `show`

Show one crash: an issue with its latest event, a single event, or a local Xcode crash. It takes an id or a Firebase console link.

```bash
xcrashlytics show FB-I1
xcrashlytics show FB-I1/events/E1 --format json
xcrashlytics show FB-I1 --app-frames-only
xcrashlytics show XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
xcrashlytics show 'https://console.firebase.google.com/project/p/crashlytics/app/ios:com.example.app/issues/ISSUEID' --format json
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<id>` | required | `FB-<issue>`, `FB-<issue>/events/<event>`, `XC-<uuid>`, or a console link (quote it). |
| `--app-frames-only` / `--no-system-frames` / `--crashing-thread-only` | off | Same frame filters as [`events`](#events). Firebase ids only; with `XC-` ids they warn `FRAME_FILTER_IGNORED`. |
| `--breadcrumbs` | off | Include breadcrumbs in JSON (Firebase only). |
| `--dsym PATH` | | Symbolicate frames, as in [`events`](#events). Repeatable. |
| `--crash-directory PATH` | | `XC-` ids: scan this directory instead of the profile's. Repeatable. |
| `--format` | `text` | `text` or `json`. `ndjson` is `BAD_INPUT`. |

- An issue id shows issue details (`errorType`, `state`), the version range (`Range:` line, `versionRange` in JSON), and the newest event of the last 90 days. An event id shows that event with the issue's totals.
- `show` also reports where the sampled events crashed, because an issue title names only one frame. `dominantLibraries` (`Libraries:` in text) counts the libraries on the crashed threads. `blameLibraries` (`Blamed in:`) counts the blame frames. A `[custom-keyboard]` issue whose `dominantLibraries` lead with one framework is that framework's bug.
- A console link selects the profile whose `bundleId` matches the link, not necessarily the active one. Links for apps without a profile are refused. A `sessionEventKey` in the link selects that event if it is among the newest 100; otherwise you get the issue and an `EVENT_NOT_RESOLVED` warning.
- Local `XC-` ids read the Organizer's `.crash` and `.ips` reports. See [Platform notes](#platform-notes-and-limits).

<details>
<summary>Example output (text)</summary>

```text
ID:        FB-I1
Source:    firebase
Version:   6.16.0
Exception: FATAL (SIGABRT)
Subtype:   Fatal error: Array index out of range
Crash:     BlurService.swift:77: Fatal error: Array index out of range (user [redacted])
Versions:  first seen 6.14.2 · last seen 6.16.0
Range:     6.15.0 (900) … 6.16.0 (937) (lowest/highest version with events, 90d)
Sampled:   newest 2 events, 2026-06-12 → 2026-06-14, 2 users
OS:        iOS 17.4 ×1, iOS 17.5.1 ×1
Devices:   iPhone14,5 ×1, iPhone15,2 ×1
Libraries: ExampleApp ×2 (100%), KeyboardCore ×1 (50%)
Blamed in: ExampleApp ×1 (50%)

Thread 0 (crashed):
  0  libobjc.A.dylib                   0x0000000000001900  objc_exception_throw
  3  ExampleApp                        0x0000000000001000  BlurService.classify(_:) (BlurService.swift:77)
```

</details>

### `export`

Export one crash as a report for a GitHub issue, Jira ticket, or chat: what it is, how much it hurts, and where it happens.

```bash
xcrashlytics export FB-I1 | pbcopy
xcrashlytics export FB-I1 --since 30d --output crash.md
xcrashlytics export FB-I1/events/E1 --format json
xcrashlytics export XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE --app-frames-only
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<id>` | required | Same ids as [`show`](#show), including console links. |
| `--format` | `markdown` | `markdown` or `json`. |
| `--since` | `7d` | Window for the event and user totals (Firebase issues). |
| `--output FILE` | stdout | Write the report to a file. |
| `--app-frames-only` / `--no-system-frames` / `--crashing-thread-only` | off | Trim Firebase frames, as in [`events`](#events). |
| `--crash-directory PATH` | | `XC-` ids: scan this directory instead of the profile's. Repeatable. |

- The report has: **What** (crash type, culprit file and symbol, crash message), **Impact** (event and user totals, share of the app's users, first/last seen versions), **Where it happens** (top 5 versions, OS versions, and devices, exact), **Trend** (events per UTC day), the newest **occurrence**, the **stack trace**, and a console link.
- JSON has the same content: `crash`, `impact`, `breakdown {window, versions, operatingSystems, devices}`, `versionRange`, `dailyEvents`, `sample`, `occurrence`, `frames`. If a report fails, that part falls back to the sample and you get `BREAKDOWN_UNAVAILABLE`. An issue ranked below the window's top 2000 gets `IMPACT_UNAVAILABLE` instead of totals.
- For non-fatals, the culprit is the app code that called `recordError`, not the SDK frame.
- The report never contains user ids, custom keys, logs, or breadcrumbs, so it is safe to share. See [Privacy](#privacy).

### `breakdown`

Exact events and users per app version, OS version, or device model, for one issue or the whole app. The numbers come from the Crashlytics reports over the whole window, not from sampled events.

```bash
xcrashlytics breakdown FB-I1 --by version --since 30d
xcrashlytics breakdown FB-I1 --by os --format json
xcrashlytics breakdown FB-I1 --by device --limit 10
xcrashlytics breakdown --by version --format json
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<issue>` | whole app | Same ids as [`show`](#show). |
| `--by` | required | `version`, `os`, or `device`. |
| `--since` | `7d` | Report window. |
| `--limit N` | all rows | First N rows, by events. |
| `--format` | `text` | `text` (table), `json`, or `ndjson` (one `breakdownRow` record per row). |

- With an issue id, rows are the groups with events, most events first. Each has `eventsCount`, `impactedUsersCount`, and `eventsShare` (percent of the issue's events).
- `--by version` rows add `versionUsersCount` (all users of that version) and `impactedUsersPercentage`. That answers "how many 4.1.0 users hit this" in one call. OS and device rows have no population figure.
- Without an id, rows add `crashFreeUsersPercentage` and sessions (`sessionsCount`, `totalSessionsCount`) for versions, and `usersCount` where Crashlytics has it for OS and devices.
- JSON `data` also has `dimension`, `window`, `eventsCount`, `groupCount` (before `--limit`), and for versions `versionRange {min, max}`.

### `blame`

Find the files and symbols that crash the most. It reads a few sample events of the window's top issues and counts their blamed frames.

```bash
xcrashlytics blame --top 20 --since 7d
xcrashlytics blame --issue-limit 100 --events-per-issue 5 --concurrency 6
xcrashlytics blame --format ndjson
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `--top N` | 20 | Frames to return. |
| `--since` | `7d` | Report window and event cutoff. |
| `--issue-limit N` | 30 | Issues to scan. |
| `--events-per-issue N` | 1 | Sample events per issue. |
| `--concurrency N` | 6 | Parallel event requests. |
| `--format` | `text` | `text`, `json`, or `ndjson`. |

- `eventCount` and `users` count sampled events, not Firebase totals. Raise `--issue-limit` and `--events-per-issue` only for a deeper scan. All numbers must be at least 1.
- The blamed frame is Firebase's blame frame, else a frame flagged as blamed, else the first app frame. It is never the SDK's own `recordError` frame.
- Each item has `file`, `line`, `symbol`, `binaryName`, `eventCount`, `users`, `exampleIssueId`, `exampleEventId`, and `topIssueIds`.

### `groups`

Group issues that share a culprit symbol, optionally with local Xcode crashes.

```bash
xcrashlytics groups
xcrashlytics groups --since 30d --firebase-limit 100 --format json
xcrashlytics groups FB-I1 --format json
xcrashlytics groups --xcode --limit 10
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<issue>` | | Show only the groups that contain this issue. |
| `--since` | `7d` | Firebase window for totals. |
| `--firebase-limit N` | 100 | Firebase issues to fetch. |
| `--limit N` | | Groups to show. |
| `--xcode` | off | Include local Xcode crashes. |
| `--crash-directory PATH` | | Scan this Xcode crash directory. Repeatable. |
| `--format` | `text` | `text` or `json`. |

- Local crashes are keyed by the first symbolicated frame in an app-owned image. Unsymbolicated crashes stay in their own group.
- Non-fatals titled at the SDK frame are not grouped with each other.
- `groups FB-I1` warns `ISSUE_NOT_IN_WINDOW` if the issue is not among the fetched issues.

### `open`

Open the crashing source line in Xcode (through `xed`).

```bash
xcrashlytics open FB-I1
xcrashlytics open FB-I1/events/E1
xcrashlytics open XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE
```

| Flag | Default | Meaning |
| --- | --- | --- |
| `<id>` | required | `FB-…` or `XC-…` id. |
| `--crash-directory PATH` | | `XC-` ids: scan this directory instead of the profile's. Repeatable. |

- Crash frames carry file names only. Run `open` from the app's repo root: the file is looked up inside the current directory. Missing or ambiguous files are an error, never a guess.
- `XC-` ids open the raw report when there is no source location.
- If `xed` fails, `open` fails with its output.

### `init`

Write `.xcrashlytics.json` and check the Firebase login.

```bash
xcrashlytics init --scan
xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --bundle-id com.example.app
xcrashlytics init --app-id 1:1234567890:android:abcdef --profile release
xcrashlytics init --app-id 1:1234567890:ios:abcdef --profile release --app-library KeyboardCore
```

| Flag | Meaning |
| --- | --- |
| `--scan` | Find every `GoogleService-Info.plist` and `google-services.json` under the current directory and write one profile per app, with its bundle id. |
| `--app-id ID` | Firebase app id (`GOOGLE_APP_ID`), any platform. |
| `--profile NAME` | Profile to create and activate, for example `staging` or `release`. |
| `--bundle-id ID` | App bundle id. Needed for Xcode crash commands. |
| `--app-library NAME` | First-party framework whose frames count as app frames. Repeatable. |

- `--scan` skips build outputs and vendored copies (`.build`, `DerivedData`, `Pods`, `Carthage`, `SourcePackages`, `node_modules`, `build`, `.git`). Unreadable or malformed files are skipped with a `[WARN]` line.
- It keeps an existing active profile. It activates the app if it finds exactly one. With several apps it asks you to run `use`; it never guesses.
- Profile names come from bundle ids. If one bundle id is another's plus `.<suffix>` (`com.example.app.widget` and `com.example.app`), it is an app extension: it is named by the suffix and gets `extensionOf`, and the app is named `app`. Config files that share a bundle id are environments and keep their folder names (`debug`, `release`). Re-scanning keeps the names a config already has.
- `--scan` also records the repo's framework and static-library targets as `appLibraries`. Firebase labels these first-party frameworks `THIRD_PARTY`; listing them makes their frames count as app frames. Add more with `--app-library`, for example for a framework from another repo.
- Re-running `init` keeps a profile's bundle id unless you pass a new one. `init` refuses to write the config when you are not logged in to Firebase.

### `use`

Switch the active profile: `xcrashlytics use staging`. It only switches between profiles that are already in the config. To add profiles, run `init` again (`init --scan`, or `init --app-id … --profile staging`).

## Output formats and stability

Use `--format json` or `ndjson` in scripts and agents. Text output is for people and may change; do not parse it.

- **`json`** — one envelope: `{"schemaVersion": 1, "data": …, "warnings": […]}`. Read results from `data`. For `show`, `data` is the crash itself.
- **`ndjson`** — one compact record per line, each with its own `schemaVersion`. Available for `issues`, `events`, `blame`, and `breakdown`. `issues` records have a `kind`: `issue`, `xcodeCrash`, or a final `hint`.
- **Warnings** mean the result may be partial; the command still succeeded. In JSON they are in the envelope as `{code, message, path?}`. With text and ndjson they go to stderr as `warning: CODE: message (path)`. Stdout never carries them.
- **Errors** with `json` or `ndjson` are `{"schemaVersion": 1, "error": {"code", "message", "hint"}}` on stdout. Flag parse errors are `BAD_INPUT` JSON too. Without those formats they keep ArgumentParser's usage text and exit 64.
- **Ids** are canonical: `FB-<issue>`, `FB-<issue>/events/<event>`, `XC-<incident>`. Pass them back unchanged. Raw ids are in `firebaseIssueId` and `firebaseEventId`.

| Code | Exit | Meaning |
| --- | --- | --- |
| `AUTH_REQUIRED`, `AUTH_EXPIRED`, `PERMISSION_DENIED` | 2 | Not logged in, login rejected, or the account cannot read the app. Run `firebase login` (or `--reauth`). |
| `RATE_LIMITED` | 3 | Retries after HTTP 429 ran out. Wait, or lower `--concurrency`. |
| `CONFIG_MISSING`, `CONFIG_INVALID` | 4 | No app id (or no bundle id for Xcode commands), or a malformed `.xcrashlytics.json`. |
| `BAD_INPUT`, `NOT_FOUND` | 5 | Bad id, flag, or value; or the app, issue, or event does not exist. |
| `API_ERROR` | 6 | Firebase or Google failure after retries. Usually transient. |
| `NETWORK_ERROR` | 7 | Google is unreachable. |
| `INTERNAL` | 1 | Unexpected error. |

The full code list, all warning codes, and what an agent should do for each are in [AGENTS.md](../AGENTS.md).

**Stability.** Within `schemaVersion` 1, fields are only added, never renamed or removed. Error codes and exit codes are stable.

> [!WARNING]
> The tool talks to Google's `v1alpha` Crashlytics API. That is an early, pre-stable tier with no compatibility guarantee. If Google changes it, commands can break until a new release adapts.

## Privacy

Crash reports can contain sensitive data. xcrashlytics does not print more of it than it has to:

- **User ids are never printed raw.** Events carry a hashed user id. `--user-id` takes the raw id as input only.
- **Redaction.** Custom keys named `userId`, `user_id`, `user-id`, or `uid` (any case), and values equal to the event's user id, are dropped from custom keys and breadcrumbs. The id is blanked inside log messages, crash info, and exception messages.
- **`export` is built for sharing.** It never includes user ids (not even hashed), custom keys, logs, or breadcrumbs. It does include the crash message.
- Raw Firebase payloads are not printed. The only network traffic is to Google: refreshing your `firebase login` token and calling the Crashlytics API. Xcode crash reports are read from disk only.
- Text, JSON, and `show` output can still contain stack frames, custom keys, logs, and app ids. Check them before pasting into a public place.

## Configuration

`.xcrashlytics.json` lives in the directory you run commands from. It has Firebase app ids only, so commit it.

```json
{
  "activeProfile": "release",
  "profiles": {
    "release": { "appId": "1:1234567890:ios:abcdef", "bundleId": "com.example.app" }
  }
}
```

| Key | Meaning |
| --- | --- |
| `appId` | Optional fallback Firebase app id when no profile is active. |
| `activeProfile` | Profile used by commands. Set by `use` and `init`. |
| `profiles` | Named Firebase app profiles, written by `init`. |

Each profile has:

| Key | Meaning |
| --- | --- |
| `appId` | Firebase app id of that environment or platform (iOS and Android both work). |
| `bundleId` | Optional, iOS. Scopes Xcode crash scanning to `~/Library/Developer/Xcode/Products/<bundleId>`, plus the containing app's directory for extensions. Required by every `--xcode` command unless you pass `--crash-directory`. `init --scan` fills it. |
| `sourcePath` | Optional. The config file the profile was discovered from. |
| `appLibraries` | Optional. First-party frameworks or static libraries (product names such as `KeyboardCore`) that Firebase labels third-party. Their frames count as app frames for `--app-frames-only` and `--no-system-frames` in `events`, `show`, and `export`, and for the culprit frame in `blame`. Written by `init --scan` and `init --app-library`. |
| `extensionOf` | Optional. Name of the app profile this app extension is embedded in. Written by `init --scan`. |


## Platform notes and limits

- **Android** works with all Firebase commands. There is no Android Studio local crash source.
- **Local Xcode crashes** (iOS) are the App Store and TestFlight reports that the Xcode Organizer downloaded to `~/Library/Developer/Xcode/Products/<bundle-id>/`. xcrashlytics only reads those files and never talks to Apple. Open the Organizer (Window → Organizer → Crashes) once after a release so fresh crashes are on disk.
  - It reads `.crash` and `.ips` files. Non-crash reports (hangs, diagnostics) are skipped with `XCODE_UNSUPPORTED_REPORT`.
  - Extension reports are filed under the containing app (`com.example.app.widget` → `com.example.app`). That directory is scanned too, and only reports with the extension's bundle id are kept.
  - Every Xcode crash command (`issues --xcode`, `groups --xcode`, `show XC-…`, `export XC-…`, `open XC-…`) needs a profile bundle id, or `--crash-directory`.
  - Without a Firebase app id, `issues --xcode` and `groups --xcode` return local crashes only (`FIREBASE_SKIPPED`).
- **90-day window.** Crashlytics keeps 90 days. `--since` accepts at most `90d`; `all` means `90d`.
- **Sampled data.** `blame`, `--user-id`, and the sample in `export` use sampled events. For exact totals use `issues`, `breakdown`, and `export`'s impact section.
- **Releases are not code-signed or notarized.** See [Setup details](#setup-details).
- **Paths** that start with your home directory (the Firebase login, the Organizer store) follow `$HOME`.
