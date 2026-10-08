#!/usr/bin/env bash
# Checks the layer dependency rule (see CONTRIBUTING.md "Architecture"):
#   Domain -> nothing; Application -> Domain; Presentation -> Application, Domain;
#   Infrastructure -> Application, Domain; Cli -> everything.
# Only Cli imports ArgumentParser (so Presentation never does). Violations are
# printed; the exit status is 0 unless --strict is passed (`make layers` passes it).
set -euo pipefail

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/xcrashlytics"
VIOLATIONS=0

report() {
  echo "$1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

# Top-level type names declared under one layer folder, as an ERE alternation.
type_pattern() {
  local names
  names=$(find "$SRC/$1" -name '*.swift' -print0 |
    xargs -0 grep -hE '^((public|private|fileprivate|internal|final) )*(struct|enum|class|protocol|actor|typealias) [A-Za-z0-9_]+' |
    sed -E 's/^((public|private|fileprivate|internal|final) )*(struct|enum|class|protocol|actor|typealias) ([A-Za-z0-9_]+).*/\4/' |
    sort -u | paste -sd '|' -)
  echo "($names)"
}

# check_layer <layer> <rule label> <forbidden layer>...
check_layer() {
  local layer="$1" label="$2"
  shift 2
  local forbidden
  for forbidden in "$@"; do
    local pattern
    pattern=$(type_pattern "$forbidden")
    local file
    while IFS= read -r -d '' file; do
      local hits
      hits=$(grep -nwE "$pattern" "$file" | grep -vE '^[0-9]+:[[:space:]]*//' || true)
      [ -z "$hits" ] && continue
      while IFS= read -r hit; do
        local lineno="${hit%%:*}" text="${hit#*:}"
        local used
        used=$(echo "$text" | grep -owE "$pattern" | sort -u | paste -sd ',' -)
        report "[$label] ${file#"$ROOT"/}:$lineno uses $forbidden type(s): $used"
      done <<<"$hits"
    done < <(find "$SRC/$layer" -name '*.swift' -print0 | sort -z)
  done
}

# Rule: ArgumentParser only under Cli/. Presentation is named because its presenters
# once reached for ArgumentParser types; its sources are scanned on their own.
while IFS= read -r file; do
  case "$file" in
    "$SRC/Presentation/"*) report "[presentation-imports] ${file#"$ROOT"/} imports ArgumentParser" ;;
    *) report "[argument-parser] ${file#"$ROOT"/} imports ArgumentParser outside Cli/" ;;
  esac
done < <(grep -rlE '^import ArgumentParser' "$SRC" --include='*.swift' | grep -v "^$SRC/Cli/" | sort || true)

# Rule: Domain imports Apple system frameworks only (Foundation, CryptoKit), never packages.
while IFS= read -r hit; do
  report "[domain-imports] ${hit#"$ROOT"/}"
done < <(grep -rnE '^import ' "$SRC/Domain" --include='*.swift' | grep -vE ':import (Foundation|CryptoKit)$' | sort || true)

check_layer Domain domain-deps Application Infrastructure Presentation Cli
check_layer Application application-deps Infrastructure Presentation Cli
check_layer Presentation presentation-deps Infrastructure Cli
check_layer Infrastructure infrastructure-deps Presentation Cli

if [ "$VIOLATIONS" -eq 0 ]; then
  echo "check-layers: no violations"
else
  echo "check-layers: $VIOLATIONS violation(s)"
  [ "$STRICT" -eq 1 ] && exit 1
fi
exit 0
