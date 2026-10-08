---
name: Bug report
about: Report a problem with xcrashlytics
title: "[bug] "
labels: bug
assignees: ''
---

## Environment

- `xcrashlytics --version`:
- macOS version:
- Xcode version (if relevant):

## What did you do?

Steps to reproduce.

```bash
xcrashlytics <command> ...
```

## What did you expect?

## What happened?

Paste the full output. For a failing command, re-run it with `--format json` and paste the JSON error object it prints on stdout (it has a `code`, a `message` and often a `hint`).

```bash
xcrashlytics <command> ... --format json
```
