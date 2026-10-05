# Contributing

Thanks for your interest in `xcrashlytics`.

## Build from source

Requires macOS 15+ and Xcode 16+ (Swift 6.0 toolchain).

```bash
git clone https://github.com/0xfirattamur/xcrashlytics.git
cd xcrashlytics
swift build
swift test
swift run xcrashlytics --help
```

To test a local build through the brew-installed `xcrashlytics` on your PATH:

```bash
scripts/install-local.sh   # builds release, overwrites the brew keg binary
```

`brew reinstall xcrashlytics` restores the released version.

## Project layout

The package has one executable target and one test target. Folders organize
responsibilities; they are not separate Swift modules.

```text
Sources/xcrashlytics/
  Commands/          # argument parsing and command orchestration
  Output/            # JSON, NDJSON and text rendering
  Ingest/            # Firebase client and local Xcode crash parsing
  Processing/        # filtering, grouping and blame aggregation
  Models/            # crash, event and frame data
  Storage/           # project configuration
  System/            # filesystem, HTTP, clock and process dependencies
  Support/           # shared utilities
Tests/xcrashlyticsTests/
  Support/           # test doubles
  Fixtures/          # crash reports and recorded Firebase responses
```

Use `@testable import xcrashlytics` in tests. Production declarations default
to internal visibility; they do not need `public` for tests to exercise them.

Name model files after the types they define: `CrashEvent.swift` represents one
occurrence, while `CrashIssue.swift` represents a Firebase issue aggregate.
Reserve `DTO` for wire-format types; processing helpers operate on domain models.

`CrashlyticsClient` implements the Crashlytics REST API; `CrashlyticsAPI` is
the narrow contract used by commands and processing. `HTTPTransport` only sends
HTTP requests, with `URLSessionHTTPTransport` in production and
`MockHTTPTransport` in tests.

Comments explain contracts, edge cases, and reasons the code cannot show.
Use `///` for declaration docs and `//` for local rationale. Do not add file
headers or comments that restate a name, an assertion, or the next line; Git
records authorship and history.

## Workflow

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- TDD: failing test first, then minimal implementation, then commit.
- Run `swiftlint lint --strict`, `swift test`, and `swift build -c release` before pushing.
- Use `swift test --enable-code-coverage` to measure coverage. A high percentage
  does not replace assertions for important edge cases or a real CLI smoke run.
- Test doubles used by concurrent code must synchronize shared mutable state;
  `@unchecked Sendable` alone does not make them thread-safe.
- Open a PR against `main`. CI must be green.

## Filing issues

Use the templates in `.github/ISSUE_TEMPLATE/`. Include:

- macOS version, Xcode version, `xcrashlytics --version`
- Output of `xcrashlytics doctor`
- Steps to reproduce
- Expected vs actual behavior

## Code of conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). Be kind.
