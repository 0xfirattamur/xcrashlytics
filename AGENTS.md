# xcrashlytics for AI Agents

Machine-readable Firebase Crashlytics investigation. Always use `--format json` or `--format ndjson`; never scrape text output.

## Investigation loop

```bash
xcrashlytics issues "<feature-or-error>" --format json     # find candidate issues
xcrashlytics show FB-ISSUE_ID --format json                # issue detail + latest frames
xcrashlytics events FB-ISSUE_ID --latest --app-frames-only --format json   # compact stack
xcrashlytics blame --since 7d --top 20 --format json       # hot files/symbols across issues
```

Narrowing by user: `xcrashlytics issues --user-id USER_ID --events-per-issue 10 --format json`, then `xcrashlytics events FB-ISSUE_ID --user-id USER_ID --format json`.

A user-pasted console link works as an id: `xcrashlytics show '<https://console.firebase.google.com/…/issues/…>' --format json`. It resolves against the profile whose bundle id matches the link. A console `sessionEventKey` also works as the event part: `FB-ISSUE_ID/events/<sessionEventKey>`.

Setup: `xcrashlytics init --scan` discovers every app in the repo. If it reports no active profile, run `xcrashlytics use <profile>`.

## Local Xcode crashes (iOS)

`issues --xcode` and `groups --xcode` add crash reports the Xcode Organizer has already downloaded to `~/Library/Developer/Xcode/Products/<bundle-id>/Crashes/` — read from disk only, no Apple connection. App-extension profiles also scan the containing app's directory (`com.example.app.widget` → `com.example.app`), where Xcode files extension reports. Their ids are `XC-<id>` and work with `show` and `open`. Requirements: the active profile must carry a bundle id (`init --bundle-id`), and the Organizer must have been opened at least once so reports exist on disk. `--crash-directory <path>` (repeatable, also on `show` and `open`) scans explicit directories instead and needs no bundle id.

## Output contract

- Every JSON success is `{"schemaVersion": 1, "data": …, "warnings": [...]}`. Read results from `data`, and check `schemaVersion`.
- `warnings[]` entries are `{code, message, path?}`. Codes: `XCODE_PARSE_FAILED`, `XCODE_SCAN_FAILED`, `SEARCH_TRUNCATED`, `SCAN_TRUNCATED`, `EVENT_NOT_RESOLVED`. A warning means the result may be partial; the command still succeeded.
- `--format ndjson` (issues, events, blame) emits one compact record per line, each with `schemaVersion`. Warnings go to stderr, never stdout.
- Ids are canonical: `FB-<issue>`, `FB-<issue>/events/<event>`, `XC-<incident>`. Pass them back verbatim. Raw ids are in `providerId` / `firebaseIssueId` / `firebaseEventId`.
- Within `schemaVersion` 1, fields are only added, never renamed or removed.
- Empty search results include a `data.hint` field; when a wider scan could help it contains the exact rerun command (e.g. `--search-limit 1000`, `--all`).
- `events --user-id` scans up to max(--limit, 50) events per issue and reports the depth as `data.scannedEvents`. `events --since` scans up to 2000 per issue and warns `SCAN_TRUNCATED` when it hits that cap.

## Errors

Failures with `--format json`/`ndjson` print one JSON object to stdout:

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
| `AUTH_EXPIRED` | 2 | stored token revoked/expired | tell the user to run `firebase login --reauth` |
| `RATE_LIMITED` | 3 | retries exhausted | back off, retry later, or lower `--concurrency` |
| `CONFIG_MISSING` | 4 | no appId, or no bundle id for Xcode crash commands | run the `xcrashlytics init` command from the `hint` field |
| `BAD_INPUT` | 5 | malformed id/flag value | fix the argument; the message says what is wrong |
| `API_ERROR` | 6 | Firebase API failure | usually transient; retry once, then surface |
| `INTERNAL` | 1 | unexpected error | surface to the user |

Exit code 64 is ArgumentParser's parse-time error (unknown flag, missing argument) — usage text on stderr.

## Keeping payloads small

Frame filter flags imply `--frames-only`: `--app-frames-only`, `--no-system-frames`, `--crashing-thread-only`. Blame defaults (`--issue-limit 30 --events-per-issue 1`) are tuned for quick loops; raise them only for deep scans.
