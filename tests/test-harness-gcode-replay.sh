#!/usr/bin/env bash
# Forge F1(b): replay G-code through Marlin's REAL Planner (harness-real --gcode)
# and compare the result with an independent Python model
# (tests/replay_reference.py, no Marlin code).
#  1. hand-written fixture: every block (steps, length, nominal speed) matches
#     the model, and no block has a junction/exit rate above its nominal rate;
#  2. generated diagnostics plates (the real forge_diag emission, 3 nozzle
#     variants): block count and total steps per axis match the model;
#  3. negative checks: wrong X steps/mm, an edited move and an unsupported
#     command (G2) are all caught.
# Host simulation only: no stepper ISR, no heaters, no time. Not hardware
# validation.
set -u
TREE="${1:?usage: test-harness-gcode-replay.sh <marlin-tree containing Marlin/>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
REF="$ROOT/tests/replay_reference.py"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }

bash "$ROOT/harness/build-real.sh" "$TREE" "$OUT" >"$OUT/build.log" 2>&1
rc=$?; [ $rc = 0 ] || sed 's/^/  build: /' "$OUT/build.log"
chk $rc "real planner harness builds"
[ $rc = 0 ] || { echo "RESULT: $fails failure(s)"; exit 1; }
H="$OUT/harness-real"

# --- 1. fixture vs model, block by block
"$H" --gcode "$FIX/replay-small.gcode" --blocks >"$OUT/fix.txt"; chk $? "fixture replays (exit 0)"
python3 "$REF" "$FIX/replay-small.gcode" >"$OUT/fix.ref"
grep -c '^rblock ' "$OUT/fix.txt" | grep -qx 19; chk $? "fixture produced 19 blocks"
diff <(grep '^rblock ' "$OUT/fix.txt") <(grep '^rblock ' "$OUT/fix.ref") >"$OUT/fix.diff"
chk $? "every block (steps, mm, nominal speed) equals the independent model"
sed 's/^/  /' "$OUT/fix.diff" | head -10
diff <(grep '^replay steps=' "$OUT/fix.txt") <(grep '^replay steps=' "$OUT/fix.ref") >/dev/null
chk $? "total steps per axis equal the model"
grep -qx 'replay rate_violations=0' "$OUT/fix.txt"; chk $? "no block has initial/final rate above its nominal rate"
grep -q 'unsupported=0' "$OUT/fix.txt"; chk $? "no unsupported command in the fixture"

# --- 2. real diagnostics plates: generate with the real forge_diag, replay each
W="$OUT/pg"; mkdir -p "$W"; cp -R "$ROOT/harness/." "$W/"
mkdir -p "$W/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$W/src/e3v3se/"
read -r -a CXXCMD <<<"${CXX:-c++}"
( cd "$W" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/plate-gen" ) >"$OUT/plate-build.log" 2>&1
rc=$?; [ $rc = 0 ] || sed 's/^/  plate build: /' "$OUT/plate-build.log"
chk $rc "diagnostics plate generator builds from the patched tree"
"$OUT/plate-gen" "$OUT/plate" >/dev/null 2>&1; chk $? "diagnostics plates generated (nozzle 0.4, 0.2, 0.8)"
for v in 40 20 80; do
  g="$OUT/plate.$v.gcode"
  [ -s "$g" ] || { chk 1 "plate $v exists"; continue; }
  "$H" --gcode "$g" >"$OUT/p$v.txt"; rc=$?
  chk $rc "plate $v replays through the real planner (exit 0)"
  python3 "$REF" "$g" --totals >"$OUT/p$v.ref"
  exp_blocks=$(sed -n 's/^replay moves=.* blocks=\([0-9]*\)$/\1/p' "$OUT/p$v.ref")
  got_blocks=$(sed -n 's/^replay file=.* blocks=\([0-9]*\) ignored.*/\1/p' "$OUT/p$v.txt")
  [ -n "$exp_blocks" ] && [ "$exp_blocks" = "$got_blocks" ]; chk $? "plate $v block count equals the model ($got_blocks vs $exp_blocks)"
  diff <(grep '^replay steps=' "$OUT/p$v.txt") <(grep '^replay steps=' "$OUT/p$v.ref") >/dev/null
  chk $? "plate $v total steps per axis equal the model ($(grep '^replay steps=' "$OUT/p$v.txt"))"
  grep -qx 'replay rate_violations=0' "$OUT/p$v.txt"; chk $? "plate $v has no rate above nominal"
  grep -q 'unsupported=0' "$OUT/p$v.txt"; chk $? "plate $v has no unsupported command"
done

# --- 3. negative checks
# 3a. wrong X steps/mm reaches the real planner and is caught by the model
"$H" --steps-x 81 --gcode "$FIX/replay-small.gcode" --blocks >"$OUT/neg1.txt"
n=$(diff <(grep '^rblock ' "$OUT/neg1.txt") <(grep '^rblock ' "$OUT/fix.ref") | grep -c '^<')
[ "$n" -gt 0 ]; chk $? "wrong X steps/mm (81) is caught ($n blocks differ from the model)"
# 3b. a motion-breaking edit (one move shifted 1 mm) is caught against the golden model
sed 's/^G1 X60 Y60 E4.5 F1800$/G1 X61 Y60 E4.5 F1800/' "$FIX/replay-small.gcode" >"$OUT/edited.gcode"
cmp -s "$OUT/edited.gcode" "$FIX/replay-small.gcode"; chk $([ $? = 1 ]; echo $?) "edit was applied to the fixture copy"
"$H" --gcode "$OUT/edited.gcode" --blocks >"$OUT/neg2.txt"
n=$(diff <(grep '^rblock ' "$OUT/neg2.txt") <(grep '^rblock ' "$OUT/fix.ref") | grep -c '^<')
[ "$n" -gt 0 ]; chk $? "edited move (X61 instead of X60) is caught ($n blocks differ from the golden model)"
# 3c. unsupported motion command fails closed
"$H" --gcode "$FIX/replay-unsupported.gcode" >"$OUT/neg3.txt"; rc=$?
[ $rc = 3 ]; chk $? "unsupported G2 arc makes the replay exit 3 (got $rc)"
grep -qx 'unsupported line 5: G2' "$OUT/neg3.txt"; chk $? "unsupported command is named with its line number"

# --- 4. parser edge cases (CodeRabbit review of F1b): same reading in harness and model
# Speeds are not compared here: the 4-step segment is shorter than the minimum
# segment time, so the planner's own slowdown applies.
"$H" --gcode "$FIX/replay-parse.gcode" --blocks >"$OUT/parse.txt"; chk $? "parser edge-case fixture replays (exit 0)"
grep -qx 'replay file=replay-parse.gcode lines=15 moves=5 rejected=0 blocks=4 ignored=1 unsupported=0' "$OUT/parse.txt"; chk $? "M117 text is ignored, not parsed (5 moves, 4 blocks, 1 ignored)"
python3 "$REF" "$FIX/replay-parse.gcode" >"$OUT/parse.ref"; chk $? "model reads the parser edge-case fixture"
diff <(grep '^rblock ' "$OUT/parse.txt" | sed 's/ nominal_speed=.*//') <(grep '^rblock ' "$OUT/parse.ref" | sed 's/ nominal_speed=.*//') >"$OUT/parse.diff"
chk $? "X10E2, G1X20, M117 text and a 1-step deferral give the same blocks in harness and model"
sed 's/^/  /' "$OUT/parse.diff" | head -10
grep -c '^rblock ' "$OUT/parse.txt" | grep -qx 4; chk $? "parser fixture produced 4 blocks (5 moves, one 1-step move deferred)"
grep -q '^rblock 0 steps=800,0,0,1430 ' "$OUT/parse.txt"; chk $? "X10E2 is X=10 with E=2 (800 X steps, 1430 E steps)"
python3 - "$OUT/long.gcode" <<'PY'
import sys
open(sys.argv[1], 'w').write('G28\nG90\nG1 X10 F600 ;' + ' ' * 1500 + 'G1 X100 F600\nG1 X20 F600\n')
PY
"$H" --gcode "$OUT/long.gcode" >"$OUT/long.txt"
grep -q 'moves=2 ' "$OUT/long.txt"; chk $? "a comment longer than the read buffer is not replayed as a move (2 moves)"
"$H" --gcode "$OUT" >"$OUT/dir.txt" 2>&1; rc=$?
[ $rc != 0 ]; chk $? "a read error is not reported as success (exit $rc)"

echo "NOTE: host simulation of the real planner; no hardware validation."
[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]
