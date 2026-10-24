#!/bin/bash
# GoatTech Forge - regression guards for upstream defects already fixed at the
# selected pins. Source-traced only (no runtime reproduction). If a pin ever
# moves to a commit without the fix, this fails before the build ships.
# Usage: test-upstream-fixes.sh <marlin_tree>
set -u
T="$1"
D="$T/Marlin/src/lcd/dwin/creality/dwin.cpp"
pass=0; fail=0
chk() { if [ "$2" -eq 0 ]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi }

# navaismo/Marlin_bugfix_2.1_E3V3SE#53 (source-traced): pre-fix confirm handler
# re-derived the file via the stale select_file.now index, printing a different
# file than the preview. Fixed pins print the stashed short name instead.
grep -q 'card.openAndPrintFile(my_short_fn)' "$D"
chk "#53: confirm handler prints stashed my_short_fn" $?
grep -q "Don't re-derive it from select_file.now" "$D"
chk "#53: stale-index warning comment present" $?
! grep -q 'openAndPrintFile(card.filename)' "$D"
chk "#53: no stale-index print path remains" $?

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
