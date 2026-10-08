# xcrashlytics for AI Agents

Machine-readable Firebase Crashlytics investigation. Always use `--format json` or `--format ndjson`; never scrape text output.

## Investigation loop

```bash
xcrashlytics issues "<feature-or-error>" --format json     # find candidate issues (last 7 days)
xcrashlytics show FB-ISSUE_ID --format json                # issue detail + latest frames
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json   # compact stack
xcrashlytics blame --since 7d --top 20 --format json       # hot files/symbols across issues
xcrashlytics breakdown FB-ISSUE_ID --by version --since 30d --format json   # exact events/users per version (also --by os|device)
```

Report window: `issues`, `blame`, `groups`, and `export` count events over an explicit window — `--since` (default `7d`, `all` = `90d`, at most `90d`, the Crashlytics limit). Ranking, `eventsCount`, and `impactedUsersCount` all cover that window, and JSON reports it as `data.window {since, until}`. To look further back, pass `--since 30d` or `--since 90d`. Event sampling (`lastSeenAt`, `--user-id`, `blame`, `export`'s sample) reads the same window; `show`, `events`, and `open` read the newest events of the last 90 days.

Issue kinds: `errorType` is `FATAL`, `NON_FATAL`, or `ANR`; `--type` matches it (or the exception type of local crashes) case-insensitively. `exceptionType` mirrors `errorType` for Firebase issues and is kept for compatibility.

Narrowing by user: `xcrashlytics issues --user-id USER_ID --format json` (scans 50 events per issue by default; raise with `--events-per-issue`), then `xcrashlytics events FB-ISSUE_ID --user-id USER_ID --format json`.

A user-pasted console link works as an id: `xcrashlytics show '<https://console.firebase.google.com/…/issues/…>' --format json`. It resolves against the profile whose bundle id matches the link. A console `sessionEventKey` also works as the event part: `FB-ISSUE_ID/events/<sessionEventKey>`. The `FB-` prefix is case-insensitive.

When the user wants a crash to share (issue tracker, chat), run `xcrashlytics export <id> --output crash.md` with any id `show` accepts. `export <id> --format json` returns the same report as data: `crash` (type, `crashMessage`, culprit file/symbol — for non-fatals the app code that called `recordError`, not the Crashlytics SDK), `impact` (Firebase totals over `--since`, plus `impactedUsersPercentage` of the app's users), `dailyEvents` (exact events per UTC day over `--since`), `breakdown {window, versions, operatingSystems, devices}` (exact top-5 spreads from the Crashlytics reports over `--since`, each row with `eventsCount`, `eventsShare`, `impactedUsersCount`; versions add `versionUsersCount` and `impactedUsersPercentage`), `versionRange {min, max}` (lowest/highest version with events), `sample` (version/OS/device spread of the newest events of that window; the fallback when a report fails), `occurrence`, and `frames`. It never includes user ids, custom keys, logs, or breadcrumbs.

`xcrashlytics breakdown [FB-ISSUE_ID] --by version|os|device [--since 30d] [--limit N]` answers "who is affected" with exact report numbers, not samples: `data.items[]` rows sorted by `eventsCount` (zero-event groups dropped) with `eventsShare` (percent of the issue's events). With an issue id, `--by version` rows add `versionUsersCount` (all users of that version) and `impactedUsersPercentage`, so "how many 4.1.0 users hit this" is one call; OS and device rows carry no population. Without an id the whole app is reported (`crashFreeUsersPercentage`, sessions). `data.versionRange {min, max}` is the lowest/highest version with events. ndjson records carry `kind: "breakdownRow"`.

Crash message and context: `events`/`show` JSON carry `crashMessage` (a Swift `fatalError`/`precondition`/`assert` text, e.g. `Foo.swift:77: Fatal error: Array index out of range`; for an NSException crash without crash info, `<type>: <message>`), `exception` (`{type, message}` of the first NSException, e.g. `CALayerInvalidGeometry`; in `show` it extends the existing `exception` object), `crashInfo` (the `crash_info_entry_N` values in order), `customKeys` (an object, `{}` when empty, without those entries), `logs` (an array of `{time, message}`, `[]` when empty) and `crashedThread` (`{title, signal, signalCode, crashAddress, queue}`). Frames-only output keeps `crashInfo`, `crashMessage`, `exception`, `crashedThread`. `--breadcrumbs` (`events`, `show`) adds `breadcrumbs`; they are large, so ask for them only when the crash needs the user's last steps. User ids are redacted everywhere: user-id-named keys and values equal to the event's user id are dropped, the id is blanked in text.

Which code crashes: `show FB-…` JSON carries `dominantLibraries` (`[{library, events, share, owner}]` over the sampled events' crashed threads, without system and SDK frames) and `blameLibraries` (blame-frame libraries). An issue titled `[ext] objectdestroyTm` whose `dominantLibraries` lead with one framework is that framework's bug, whatever the title says. `--dsym <path>` (repeatable; `.dSYM` bundles or directories of them) on `events`/`show` symbolicates frames of the dSYM's library with `xcrun atos`: frames get `symbol`/`file`/`line` from the dSYM, `firebaseSymbol` (Crashlytics' own) and `symbolicated: "dsym"`.

`firstSeenVersion` / `lastSeenVersion` are the versions of the issue's first and of its most recent event — chronological, never a range; the last-seen version can be lower than the first. `--app-version 6.16.0` (or `6.16.0 (937)`) and `--since-version 6.16.0` are exact server-side filters over the window's versions: ranking and `eventsCount`/`impactedUsersCount` then cover only events of those versions (`data.matchedVersions` lists them; if none matches, `data.hint` names the versions seen). `issues --by-day` adds daily counts from the Crashlytics report, not from sampled events (`dailyEvents`, UTC days, empty days omitted; the sum matches `eventsCount`, except on very large issues where Crashlytics' own totals can differ by a few dozen events; `dailyEventsTruncated` is always `false`). `lastSeenAt` is the newest event time inside the window.

Setup: `xcrashlytics init --scan` discovers every app in the repo and names profiles from bundle ids: an app extension (`com.x.app.widget`) is named by its suffix with `extensionOf: <app profile>`, the app is `app`; re-scanning keeps existing names. It also records the repo's framework/static-library targets as profile `appLibraries` (first-party code Crashlytics labels `THIRD_PARTY`); add more with `init --app-id … --profile … --app-library NAME`. If it reports no active profile, run `xcrashlytics use <profile>`.

## Local Xcode crashes (iOS)

`issues --xcode` and `groups --xcode` add crash reports the Xcode Organizer has already downloaded to `~/Library/Developer/Xcode/Products/<bundle-id>/` — read from disk only, no Apple connection. Both the legacy `.crash` text format and the modern `.ips` JSON format are parsed; non-crash reports (hangs, diagnostics) are skipped with `XCODE_UNSUPPORTED_REPORT`. App-extension profiles also scan the containing app's directory (`com.example.app.widget` → `com.example.app`), where Xcode files extension reports. Their ids are `XC-<id>` and work with `show`, `export`, and `open`. Requirements: the active profile must carry a bundle id (`init --bundle-id`), and the Organizer must have been opened at least once so reports exist on disk. `--crash-directory <path>` (repeatable, also on `show`, `export`, and `open`; implies `--xcode` for `issues`) scans explicit directories instead and needs no bundle id. Without any Firebase app id configured, `issues --xcode` and `groups --xcode` return local crashes only with a `FIREBASE_SKIPPED` warning.

## Output contract

- Every JSON success is `{"schemaVersion": 1, "data": …, "warnings": [...]}`. Read results from `data`, and check `schemaVersion`.
- `warnings[]` entries are `{code, message, path?}`. A warning means the result may be partial; the command still succeeded. Codes:
  - `SEARCH_TRUNCATED` — the fetched window was full and fewer than `--limit` matched; `data.hint` says how to widen.
  - `SEARCH_LIMIT_CAPPED` — `--search-limit` above 2000 was capped.
  - `SCAN_TRUNCATED` — a `--user-id` event scan (`events`, `issues`) hit its depth before covering the window or filling `--limit`.
  - `EVENT_NOT_RESOLVED` — a console link's event is not among the newest 100; the issue is shown.
  - `IMPACT_UNAVAILABLE` — export: the issue ranks below the window's top 2000; totals omitted.
  - `BREAKDOWN_UNAVAILABLE` — export: a version/OS/device report failed; that dimension of `breakdown` is absent and its spread comes from the sample. `show`: the version report failed; `versionRange` is omitted.
  - `LAST_SEEN_UNAVAILABLE` — `lastSeenAt` could not be fetched for some issues; it is omitted for them.
  - `NO_CRASHED_THREAD` — `--crashing-thread-only` on an event without a crashed thread (typical for non-fatals); no frames returned.
  - `DSYM_UNVERIFIED` — `--dsym` symbolicated frames with a dSYM whose UUID cannot be checked: Crashlytics events carry no binary image UUIDs. The symbols are right only if the dSYM is from the crashed build.
  - `DSYM_FAILED` — `--dsym`: no dSYM under a path, or `xcrun otool`/`atos` failed; `path` names it. Frames keep Crashlytics' symbols.
  - `FRAME_FILTER_IGNORED` — Firebase frame filters passed with an `XC-` id.
  - `FIREBASE_SKIPPED` — `--xcode` with no Firebase app id configured; local crashes only.
  - `ISSUE_NOT_IN_WINDOW` — `groups FB-…`: the issue is not among the fetched issues of the window.
  - `XCODE_PARSE_FAILED`, `XCODE_SCAN_FAILED`, `XCODE_UNSUPPORTED_REPORT`, `XCODE_NO_THREAD_FRAMES`, `XCODE_EXCLUDED_BY_FILTER` — local crash reading; `path` names the file or directory.
- `--format ndjson` (issues, events, blame, breakdown) emits one compact record per line, each with `schemaVersion`. `issues` records carry `kind`: `issue`, `xcodeCrash`, or a final `hint` record when there is a hint. Warnings go to stderr as `warning: CODE: message (path)`, never stdout.
- Ids are canonical: `FB-<issue>`, `FB-<issue>/events/<event>`, `XC-<incident>`. Pass them back verbatim. Raw ids are in `providerId` / `firebaseIssueId` / `firebaseEventId`. Frame `index` is the frame's position in the original stack, also after filtering.
- Within `schemaVersion` 1, fields are only added, never renamed or removed.
- Empty search results include a `data.hint` field; when a wider scan could help it contains the exact rerun command (e.g. `--search-limit 1000`, `--all`).
- `events` always sends an explicit window (the API alone only reaches back about 7 days): `--since` (at most `90d`) is applied on the server, and without `--since` the window is the 90-day maximum, so old events are reached. `events --user-id` scans up to max(`--limit`, 50) events per issue inside that window. JSON reports `data.scanDepth` (per issue) and `data.scannedEvents` (sum over issues) for those scans. `SCAN_TRUNCATED` fires only when a depth-limited `--user-id` scan read a full `scanDepth` events without filling `--limit` (older events of the window may still match).

## Errors

Failures with `--format json`/`ndjson` print one JSON object to stdout (one compact line for ndjson):

```json
{
  "error" : {
    "code" : "AUTH_REQUIRED",
    "hint" : "Run: firebase login",
    "message" : "firebase CLI is not authenticated."
  },
  "schemaVersion" : 1
}
```

| code | exit | meaning | agent action |
| --- | --- | --- | --- |
| `AUTH_REQUIRED` | 2 | firebase CLI not logged in | tell the user to run `firebase login` |
| `AUTH_EXPIRED` | 2 | stored login revoked or rejected by Google | tell the user to run `firebase login --reauth` |
| `PERMISSION_DENIED` | 2 | the signed-in account cannot read this Firebase app | tell the user to check the account (`firebase login:list`) or the profile (`xcrashlytics use`) |
| `RATE_LIMITED` | 3 | 429 retries exhausted | back off, retry later, or lower `--concurrency` |
| `CONFIG_MISSING` | 4 | no app id, or no bundle id for Xcode crash commands | run the `xcrashlytics init` command from the `hint` field |
| `CONFIG_INVALID` | 4 | `.xcrashlytics.json` is malformed, or its app id is not a Firebase app id | fix the file as the `hint` says |
| `BAD_INPUT` | 5 | malformed id, flag, or flag value (also parse errors when `--format json`/`ndjson` is given) | fix the argument; the message says what is wrong |
| `NOT_FOUND` | 5 | the app, issue, or event does not exist | check the id; list ids with `issues` |
| `API_ERROR` | 6 | Firebase or Google token service failure after retries | usually transient; retry once, then surface |
| `NETWORK_ERROR` | 7 | Google unreachable (offline, DNS, TLS, timeout) | check the connection, then retry |
| `INTERNAL` | 1 | unexpected error | surface to the user |

Without `--format json`/`ndjson`, parse-time errors (unknown flag, missing argument) keep ArgumentParser's usage text on stderr and exit 64. `init`, `use`, and `open` have no `--format`; their failures are text on stderr with the same exit codes.

## Keeping payloads small

Frame filter flags imply `--frames-only`: `--app-frames-only`, `--no-system-frames`, `--crashing-thread-only`. `--app-frames-only` drops system, Crashlytics SDK (by symbol, whichever library it is linked into), library-less, and third-party (`VENDOR`) frames; frames of the profile's `appLibraries` count as app frames. When a filter leaves no frames, `events`/`show` JSON says why (`noFramesReason`, `appFramesAbsent: true`, `crashedLibrary`; `blamedFrame` keeps the blame frame's library) — an empty `frames` with `noFramesReason` means the stack was filtered away, not missing. Blame defaults (`--issue-limit 30 --events-per-issue 1`) are tuned for quick loops; raise them only for deep scans.

## Privacy and redaction

- Raw Firebase user ids are never printed. Events carry a hashed user id. `--user-id` takes the raw id as filter input only.
- Keys named `userId`, `user_id`, `user-id` or `uid` (any case) and values equal to the event's user id are dropped from `customKeys` and breadcrumb params. The id is blanked (`[redacted]`) inside log messages, `crashInfo`, `crashMessage`, and exception messages. `--domain` and `--user-info-key` still match the full custom keys.
- `export` never includes user ids (not even hashed), custom keys, logs, or breadcrumbs. It does carry the crash message.
- Raw Firebase payloads are never printed.

## Command details

- `show`, `export`, and `breakdown` accept console links. Only `https://console.firebase.google.com` links are accepted; the link's bundle id selects the profile (not necessarily the active one), and a link for an app with no profile is refused. A `sessionEventKey` selects its event when the event is among the newest 100 (matched against the event's resource name and its suffix after the last `_`); otherwise `EVENT_NOT_RESOLVED`.
- `show` reads the issue's newest 100 events of the last 90 days. `events` without `--since` returns its `--limit` newest events (default 10) from the same 90-day window. `show` Firebase JSON also has `versionRange {min, max}` from the version report (`BREAKDOWN_UNAVAILABLE` if it fails). `show` and `groups` support text and JSON only; `--format ndjson` is `BAD_INPUT`.
- `--dsym` runs `xcrun atos -arch arm64 -o <DWARF> -l <__TEXT vmaddr> <vmaddr+address>` once per binary; each DWARF binary's name is matched to the frame `binaryName`. `__MACOSX` copies are ignored.
- `issues` with a query and filters fetches a wider search window (`--search-limit`, at most 2000, `--all` = 2000) and shows the first `--limit` matches. Terms with `.`, `_` or `=` match the issue's own fields first. Non-fatal issues are titled at the Crashlytics SDK's `recordError` frame, so their `file` and `topAppSymbol` are empty; `export` and `blame` name the app code that recorded the error. `relatedGroups` lists same-signature issue ids. With `--xcode` unsymbolicated local crashes add a `symbolicationHint`.
- `blame` counts sampled events, not Firebase totals. The blamed frame is Firebase's blame frame, else a frame flagged blamed, else the first app frame, never the SDK's `recordError` frames. All of `--top`, `--issue-limit`, `--events-per-issue`, `--concurrency` must be at least 1.
- `groups` keys local Xcode crashes by the first symbolicated frame in an app-owned image; unsymbolicated crashes stay in their own group. Non-fatals titled at the SDK frame are not grouped with each other. `groups FB-…` shows the groups containing that issue.
- `open` resolves the crash's file name inside the current directory; ambiguous or missing files are an error, never a guess. `XC-` ids fall back to opening the raw report. If `xed` or `open` fails, the command fails with its output.
- `init --scan` skips `.build`, `DerivedData`, `Pods`, `Carthage`, `SourcePackages`, `node_modules`, `build`, `.git`, and skips unreadable or malformed config files with a `[WARN]` line. It keeps an existing active profile, activates the app if it finds exactly one, and never guesses among several. Re-running `init` keeps a profile's bundle id unless a new one is passed. `use <name>` only switches between existing profiles.
- Authentication reuses the `firebase-tools` token in `~/.config/configstore/firebase-tools.json` (`$XDG_CONFIG_HOME` is honored). No `gcloud` is needed.

## Reporting problems

Bug reports and feature requests from agents are welcome. Open one when xcrashlytics returns something wrong (a misleading field, a wrong count, a crash, a confusing error) or when a missing capability forced a workaround (several calls, `jq` over a sample, manual `atos`).

1. Search first: `gh issue list --repo 0xfirattamur/xcrashlytics --search "<keywords>" --state all`. If one exists, add a comment with your case instead.
2. Draft the issue and show it to your user before creating it. Issues are public: never include their crash data, stack frames, issue/event/app/bundle ids, custom keys, logs, user ids, or source paths. Describe the shape of the problem with placeholders (`FB-<issue>`, `<AppModule>`).
3. Create it:
   ```bash
   gh issue create --repo 0xfirattamur/xcrashlytics --label bug --title "[bug] <summary>" --body-file issue.md
   gh issue create --repo 0xfirattamur/xcrashlytics --label enhancement --title "[feat] <summary>" --body-file issue.md
   ```
   Without `gh`, give your user the filled-in text and the link https://github.com/0xfirattamur/xcrashlytics/issues/new/choose.

A bug body has: `xcrashlytics --version` and macOS version; the command (ids replaced by placeholders); what you expected; what happened, with the JSON `error` object or `warnings` codes. A feature body has: the question you were answering; what you had to do instead (calls, time, workarounds); the command, flag or field that would have answered it.
