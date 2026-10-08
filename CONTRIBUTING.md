# Contributing

Thanks for your interest in `xcrashlytics`.

## Build from source

Requires macOS 15+ and Xcode 16+ (Swift 6.0 toolchain).

```bash
git clone https://github.com/0xfirattamur/xcrashlytics.git
cd xcrashlytics
make bootstrap   # installs the pinned SwiftLint via mise
make ci          # lint, tests, release build: what CI runs
swift run xcrashlytics --help
```

Without [mise](https://mise.jdx.dev), `make` uses the `swiftlint` on your PATH;
CI uses the version pinned in `.mise.toml`.

To test a local build through the brew-installed `xcrashlytics` on your PATH:

```bash
make install   # builds release, overwrites the brew keg binary
```

`brew reinstall xcrashlytics` restores the released version.

## Project layout

The package has one executable target and one test target. Folders organize
responsibilities; they are not separate Swift modules.

```text
Sources/xcrashlytics/
  Cli/             # ArgumentParser commands, option groups, AppContainer (composition root)
  Application/     # Ports/, Services/, Requests/, Results/ (use cases)
  Domain/          # Crash, Crashlytics, Frames, Grouping, Search, Time,
                   # Versioning, Configuration (entities and pure policies)
  Infrastructure/  # Crashlytics, Xcode, Configuration, Symbolication,
                   # Platform (adapters: REST client, parsers, file/process/HTTP)
  Presentation/    # JSON, Text, Markdown renderers and the JSON envelope
Tests/xcrashlyticsTests/
  Cli/ Application/ Domain/ Infrastructure/ Presentation/   # mirror the layers
  Golden/          # byte-exact output goldens (Golden/Fixtures)
  Support/         # shared test doubles and fixtures
  Fixtures/        # crash reports and recorded Firebase responses
```

Dependency rule: Domain depends on nothing; Application on Domain;
Presentation on Application and Domain; Infrastructure on Application (ports)
and Domain; Cli on everything. Only Cli imports ArgumentParser. Domain and Application types never encode
themselves: JSON shapes are explicit payload types in Presentation/JSON. One type per
file, named after the type; extensions live in `Type+Topic.swift`.
`scripts/check-layers.sh` checks the rule (`make ci` runs it with `--strict`,
so violations fail the build).

Use `@testable import xcrashlytics` in tests. Production declarations default
to internal visibility; they do not need `public` for tests to exercise them.

### Adding or changing a command

Every command follows one path: `Cli/Commands/XCommand` parses and validates
options into `Application/Requests/XRequest`, calls `XService` (a struct with
`let` dependencies typed by ports in `Application/Ports`), gets an
`Application/Results/XResult`, and hands it to `Presentation/Presenters/XPresenter`,
which renders text/JSON/NDJSON. `ResultEmitter` is the only writer of success
output, `FailurePresenter` the only writer of failures. `AppContainer` wires
everything; commands never touch the file store, HTTP client or console.

### Naming

- Types are nouns with a role suffix: `…Service`, `…Repository`, `…Client`,
  `…Parser`, `…Mapper`, `…Presenter`, `…Renderer`, `…Payload`, `…Request`, `…Result`.
- Ports are named by role, implementations by technology: `FileStore` /
  `DiskFileStore`, `SubprocessExecutor` / `FoundationSubprocessExecutor`,
  `HTTPClient` / `URLSessionHTTPClient`, `CrashlyticsClient` / `RESTCrashlyticsClient`.
- `Crashlytics…` names the service and its data; `Firebase…` only platform
  pieces (console links, app discovery, firebase-tools login).
- No abbreviations (`ctx`, `fs`, `tmp`, `info`); booleans read `is…`/`has…`;
  Swift acronym casing (`JSON`, `HTTP`, `SDK`, `DSYM`).
- Test doubles: `Fake…` (working implementation), `Stub…` (canned answers),
  `Spy…` (records calls), `Fixed…` (deterministic values).

### Comments

Comments explain why, never what: invariants, ordering constraints, privacy
reasons. Live Crashlytics API behaviour gets a `// Crashlytics quirk:` line.
At most three lines; `///` only on port requirements and non-obvious API. No
file headers, no history words ("now", "previously"); Git records history.

### Golden tests

`Tests/xcrashlyticsTests/Golden` pins the exact stdout, stderr, exit code and
HTTP requests of every command and format. A refactor must leave them
byte-identical. Only an intended output change may re-record them:
`XCRASHLYTICS_RECORD_GOLDENS=1 swift test --filter Golden`, then review the diff.

## Workflow

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- TDD: failing test first, then minimal implementation, then commit.
- Run `make ci` before pushing.
- Use `swift test --enable-code-coverage` to measure coverage. A high percentage
  does not replace assertions for important edge cases or a real CLI smoke run.
- Test doubles used by concurrent code must synchronize shared mutable state;
  `@unchecked Sendable` alone does not make them thread-safe.
- Open a PR against `main`. CI must be green.
- Releasing:
  1. Set `version` in `Sources/xcrashlytics/Cli/XcrashlyticsCommand.swift` and
     `VERSION` in the README's direct-download example.
  2. `make ci`, then `swift build -c release --arch arm64 --arch x86_64`.
  3. Merge to `main` and wait for green CI on that commit.
  4. Push a `vMAJOR.MINOR.PATCH` tag. The release workflow runs the tests,
     fails if the binary's `--version` does not match the tag, publishes the
     universal tarball and its `.sha256`, and commits the Homebrew formula
     update to `main`. Tags with a `-suffix` publish a prerelease and skip
     the formula. Do not edit `Formula/xcrashlytics.rb` by hand unless that
     job reports a failed push.

## Filing issues

Use the templates in `.github/ISSUE_TEMPLATE/`. Include:

- macOS version, Xcode version, `xcrashlytics --version`
- The failing command, run with `--format json`, and its output
- Steps to reproduce
- Expected vs actual behavior

## Code of conduct

Be kind and assume good intent.
