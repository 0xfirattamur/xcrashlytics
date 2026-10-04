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

```
Sources/
  XCrashlyticsCore/   # library — domain logic, parsers, matchers, clients
  xcrashlytics/       # CLI executable (swift-argument-parser)
Tests/
  XCrashlyticsCoreTests/
  xcrashlyticsTests/
  Fixtures/           # sample .ips, recorded Firebase JSON, dSYMs, golden CLI output
docs/                 # architecture, schema, errors, install, versioning
```

## Workflow

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`.
- TDD: failing test first, then minimal implementation, then commit.
- Run `swift-format lint --recursive --strict Sources/ Tests/` before pushing.
- Open a PR against `main`. CI must be green.

## Filing issues

Use the templates in `.github/ISSUE_TEMPLATE/`. Include:

- macOS version, Xcode version, `xcrashlytics --version`
- Output of `xcrashlytics doctor`
- Steps to reproduce
- Expected vs actual behavior

## Code of conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). Be kind.
