#!/usr/bin/env bash
# Contract tests for source-only checks. No binary or hardware evidence.
set -euo pipefail
TREE="${1:?usage: test-menu-source-contract.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fails=0
check() { if "$@"; then echo "PASS: $*"; else echo "FAIL: $*"; fails=$((fails+1)); fi; }
for script in test-menu-source.sh test-diag-menu-source.sh; do
  check bash "$ROOT/tests/$script" "$TREE" --source-only
  if bash "$ROOT/tests/$script" "$TREE" "$OUT/missing.bin" >"$OUT/missing.log" 2>&1; then
    echo "FAIL: $script accepts a missing binary"; fails=$((fails+1))
  else
    echo "PASS: $script refuses a missing binary"
  fi
done
# Copy only files the diagnostics source check reads. Mutate that scratch copy.
for p in Marlin/src/lcd/dwin/creality/{dwin.cpp,dwin.h,dwin_lcd.h}; do
  mkdir -p "$OUT/tree/$(dirname "$p")"
  cp "$TREE/$p" "$OUT/tree/$p"
done
python3 - "$OUT/tree/Marlin/src/lcd/dwin/creality/dwin.cpp" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read(); anchor='Forge Diagnostics review screen'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'\n// suggested tuning target for contract-test mutant',1)
open(p,'w').write(s)
PY
# A synthetic string fixture isolates the old combined checker. This is NOT
# compiled-binary evidence and is never used as firmware validation.
printf 'FORGDIA1.G\nForge Diagnostics\nmulti-hour\n' > "$OUT/strings.fixture"
if bash "$ROOT/tests/test-diag-menu-source.sh" "$OUT/tree" "$OUT/strings.fixture" >"$OUT/mutant.log" 2>&1; then
  echo 'FAIL: diagnostics source check accepts suggested tuning target'; fails=$((fails+1))
elif grep -q '^FAIL: no tuning-target suggestion language' "$OUT/mutant.log"; then
  echo 'PASS: diagnostics source check detects suggested tuning target'
else
  cat "$OUT/mutant.log"; echo 'FAIL: mutant failed for an unrelated reason'; fails=$((fails+1))
fi
printf 'RESULT: %s contract failure(s)\n' "$fails"
[ "$fails" = 0 ]
