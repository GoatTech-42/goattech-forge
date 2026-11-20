#!/usr/bin/env bash
# Forge F1(b): replay G-code through Marlin's REAL Planner (harness-real --gcode)
# and compare the result with an independent Python model
# (tests/replay_reference.py, no Marlin code).
#  1. hand-written fixture: every block (steps, length, nominal speed) matches
#     the model, and no block has a junction/exit rate above its nominal rate;
#  2. generated diagnostics plates (the real forge_diag emission, 3 nozzle
#     variants): block count and total steps per axis match the model;
#  3. negative checks: wrong X steps/mm, an edited move and an unsupported
#     command (G2) are all caught;
#  4. parser edge cases read the same way by harness and model;
#  5-10. E-only G92 keeps the X/Y/Z baseline, other G92 forms and unknown
#     commands fail closed in both programs, half-step E resets, short X/Y/Z
#     segments with extrusion, the supported-command subset, and the E mode
#     after each G90/G91 and M82/M83 ordering against Marlin's own GcodeSuite.
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

# 4b. command numbers are read whole (CodeRabbit round 2): no truncation, no missing number
printf 'G90\nG1.5 X10 F600\n' >"$OUT/frac.gcode"
"$H" --gcode "$OUT/frac.gcode" >"$OUT/frac.txt"; rc=$?
[ $rc = 3 ]; chk $? "fractional command G1.5 fails closed with exit 3 (got $rc)"
grep -q 'moves=0 ' "$OUT/frac.txt"; chk $? "G1.5 is not replayed as a G1 move"
printf 'G90\nG X10 F600\n' >"$OUT/nonum.gcode"
"$H" --gcode "$OUT/nonum.gcode" >"$OUT/nonum.txt"; rc=$?
[ $rc = 3 ]; chk $? "command letter with no number fails closed with exit 3 (got $rc)"
grep -q 'moves=0 ' "$OUT/nonum.txt"; chk $? "G with no number is not replayed as G0"
python3 "$REF" "$OUT/frac.gcode" >/dev/null 2>&1; rc=$?
[ $rc = 3 ]; chk $? "model rejects G1.5 too, exit 3 (got $rc)"
python3 "$REF" "$OUT/nonum.gcode" >/dev/null 2>&1; rc=$?
[ $rc = 3 ]; chk $? "model rejects a command letter with no number, exit 3 (got $rc)"
printf 'G90\nG01 X10 F600\nG1 X20 F600\n' >"$OUT/zero.gcode"
"$H" --gcode "$OUT/zero.gcode" --blocks >"$OUT/zero.txt"; chk $? "G01 replays"
python3 "$REF" "$OUT/zero.gcode" >"$OUT/zero.ref"
diff <(grep '^rblock ' "$OUT/zero.txt" | sed 's/ nominal_speed=.*//') <(grep '^rblock ' "$OUT/zero.ref" | sed 's/ nominal_speed=.*//') >/dev/null
chk $? "G01 and G1 give the same blocks in harness and model"
grep -q 'moves=2 ' "$OUT/zero.txt"; chk $? "G01 counts as a move (2 moves)"

# --- 5-10. Supported subset, E-only G92 and short-segment length (F1 PR3)
# Expected values are derived from the pinned Marlin source, not copied from
# either program: G92.cpp + motion.cpp sync_plan_position_e() + planner.cpp
# set_e_position_mm() for G92 E, planner.cpp _populate_block() for the
# MIN_STEPS_PER_SEGMENT (4) length rule, gcode.h for the relative modes.
# Step arithmetic is float32 like the firmware: LROUND(float(v) * 715.12f).
run_pair(){   # run_pair NAME GCODE: harness (--blocks) and model on the same file
  printf '%b' "$2" >"$OUT/$1.gcode"
  "$H" --gcode "$OUT/$1.gcode" --blocks >"$OUT/$1.h" 2>&1; hrc=$?
  python3 "$REF" "$OUT/$1.gcode" >"$OUT/$1.m" 2>"$OUT/$1.merr"; mrc=$?
}
steps_of(){ sed -n 's/^replay steps=//p' "$1"; }
path_of(){ sed -n 's/^replay path_mm=//p' "$1"; }
both_steps(){   # both_steps NAME EXPECTED_STEPS LABEL: both exit 0 with these totals
  [ $hrc = 0 ] && [ "$(steps_of "$OUT/$1.h")" = "$2" ]; chk $? "$3: harness exit 0, steps=$2 (got $hrc, $(steps_of "$OUT/$1.h"))"
  [ $mrc = 0 ] && [ "$(steps_of "$OUT/$1.m")" = "$2" ]; chk $? "$3: model exit 0, steps=$2 (got $mrc, $(steps_of "$OUT/$1.m"))"
}

# 5. E-only G92 leaves the X/Y/Z step baseline alone. G92.cpp sets only
#    motion.position.e and calls sync_plan_position_e() ->
#    planner.set_e_position_mm(), which writes position.e only; and only when
#    E changes by more than NEAR_ZERO. A deferred sub-4-step X/Y/Z move must
#    therefore still count from the old baseline after the reset.
run_pair g92x 'G90\nG1 X0.0125 F600\nG92 E0\nG1 X1 F600\n'
both_steps g92x 80,0,0,0 "X 1-step deferral survives G92 E0"
[ "$(path_of "$OUT/g92x.h")" = 1.000 ] && [ "$(path_of "$OUT/g92x.m")" = 1.000 ]
chk $? "X deferral across G92 E0: path_mm=1.000 in harness and model ($(path_of "$OUT/g92x.h"), $(path_of "$OUT/g92x.m"))"
run_pair g92y 'G90\nG1 Y0.0125 F600\nG92 E0\nG1 Y1 F600\n'
both_steps g92y 0,80,0,0 "Y 1-step deferral survives G92 E0"
run_pair g92z 'G90\nG1 Z0.005 F600\nG92 E0\nG1 Z1 F600\n'      # Z0.005 = 2 steps
both_steps g92z 0,0,400,0 "Z 2-step deferral survives G92 E0"
# changed E: E baseline becomes LROUND(5*715.12f)=LROUND(3575.6001)=3576, then
# E6 is 4291 (4290.7197): 715 E steps; X still counts from 0 (80 steps)
run_pair g92chg 'G90\nM82\nG1 X0.0125 F600\nG92 E5\nG1 X1 E6 F600\n'
both_steps g92chg 80,0,0,715 "changed-E G92 E5 resets only E (X keeps its deferral)"
# unchanged E: G1 E0.002 is 1 step (1.43) and deferred, so motion.position.e
# is 0.002 while the planner E baseline is still 0. G92 E0.002 changes nothing
# (NEAR_ZERO), so the next G1 E1 is 715 steps, not 714 from a re-rounded baseline.
run_pair g92same 'G90\nM82\nG1 E0.002 F600\nG92 E0.002\nG1 E1 F600\n'
both_steps g92same 0,0,0,715 "unchanged-E G92 is a no-op (deferred E baseline kept)"

# 6. X/Y/Z and other non-E G92 words are refused (exit 3) before any state
#    change: workspace offsets are on in this config, so real G92 X shifts the
#    workspace, which neither program models.
for c in 'G92 X0' 'G92 Y0' 'G92 Z0' 'G92 X0 E0' 'G92 E' 'G92 F100'; do
  n="g92ref$(echo "$c" | tr -dc 'A-Z0-9')"
  run_pair "$n" "G90\\n$c\\nG1 X10 F600\\n"
  [ $hrc = 3 ] && grep -q '^unsupported line 2: G92' "$OUT/$n.h"; chk $? "harness refuses '$c' with exit 3 and its line number (got $hrc)"
  grep -q 'unsupported=0' "$OUT/$n.h"; chk $([ $? = 1 ]; echo $?) "harness summary does not report '$c' as supported"
  [ $mrc = 3 ] && grep -q '^unsupported line 2: G92' "$OUT/$n.merr"; chk $? "model refuses '$c' with exit 3 and its line number (got $mrc)"
done
# refused mixed G92 X0 E5 mutates neither X nor E: the next move still counts
# X 10->20 (800 steps) and E 1->2 (1430-715 = 715 steps)
run_pair g92mix 'G90\nM82\nG1 X10 E1 F600\nG92 X0 E5\nG1 X20 E2 F600\n'
[ $hrc = 3 ] && [ "$(steps_of "$OUT/g92mix.h")" = 1600,0,0,1430 ]; chk $? "harness: refused G92 X0 E5 leaves X and E untouched, exit 3 (got $hrc, $(steps_of "$OUT/g92mix.h"))"
[ $mrc = 3 ] && [ "$(steps_of "$OUT/g92mix.m")" = 1600,0,0,1430 ]; chk $? "model: refused G92 X0 E5 leaves X and E untouched, exit 3 (got $mrc, $(steps_of "$OUT/g92mix.m"))"
run_pair g92xonly 'G90\nG1 X0.0125 F600\nG92 X5\nG1 X1 F600\n'
[ $hrc = 3 ] && [ "$(steps_of "$OUT/g92xonly.h")" = 80,0,0,0 ]; chk $? "harness: refused G92 X5 keeps the deferred X baseline, exit 3 (got $hrc, $(steps_of "$OUT/g92xonly.h"))"
[ $mrc = 3 ] && [ "$(steps_of "$OUT/g92xonly.m")" = 80,0,0,0 ]; chk $? "model: refused G92 X5 keeps the deferred X baseline, exit 3 (got $mrc, $(steps_of "$OUT/g92xonly.m"))"

# 7. E reset values on a half step. float32 products (exact values checked
#    separately): 3.9385f*715.12f = 2816.5 (exact 2816.50004894),
#    6.25f*715.12f = 4469.5 (exact 4469.49996948, so double maths would give
#    4469), 0.5992f*715.12f = 428.49991. LROUND is lroundf: half away from
#    zero, so 2817, 4470 and 428 steps back to E0, with either sign.
for c in 3.9385:2817 -3.9385:2817 6.25:4470 -6.25:4470 0.5992:428 -0.5992:428; do
  v=${c%%:*}; e=${c#*:}; n="g92half$(echo "$v" | tr -dc '0-9')$( [ "${v#-}" = "$v" ] || echo n)"
  run_pair "$n" "G90\\nM82\\nG92 E$v\\nG1 E0 F600\\n"
  both_steps "$n" "0,0,0,$e" "G92 E$v then G1 E0 is LROUND half away from zero"
done
# queued ordinary moves before an E reset are all counted before it, and a
# nonzero negative reset works: E -2.5 -> -1.5 is LROUND(-1072.68)-LROUND(-1787.8) = 715
run_pair g92queue 'G90\nM82\nG1 X10 E1 F600\nG1 X20 E2 F600\nG92 E0\nG1 X30 E1 F600\nG92 E-2.5\nG1 X40 E-1.5 F600\n'
both_steps g92queue 3200,0,0,2860 "queued moves around G92 E0 and G92 E-2.5"
grep -q '^rblock 1 steps=800,0,0,715 ' "$OUT/g92queue.h"; chk $? "second queued move before G92 E0 is counted in full (800 X, 715 E)"
diff <(grep '^rblock ' "$OUT/g92queue.h" | sed 's/ nominal_speed=.*//') <(grep '^rblock ' "$OUT/g92queue.m" | sed 's/ nominal_speed=.*//') >/dev/null
chk $? "queued G92 case: every block equals the model"

# 8. Block length when X/Y/Z have fewer than MIN_STEPS_PER_SEGMENT steps:
#    planner.cpp sets block->millimeters = |E mm| when !XYZ_HAS_ENOUGH_STEPS
#    (no axis >= 4 steps), so a 1-step X with 1 mm E is a 1.000 mm block at
#    the full 10 mm/s feed, not 0.013 mm.
tiny(){   # tiny NAME GCODE EXPECTED_RBLOCK0 LABEL
  run_pair "$1" "G90\\nM82\\n$2\\n"
  grep -qx "rblock 0 $3" "$OUT/$1.h"; chk $? "$4: harness block is '$3' ($(grep '^rblock 0' "$OUT/$1.h"))"
  grep -qx "rblock 0 $3" "$OUT/$1.m"; chk $? "$4: model block is '$3' ($(grep '^rblock 0' "$OUT/$1.m"))"
}
tiny tinyx 'G1 X0.0125 E1 F600' 'steps=1,0,0,715 mm=1.000 nominal_speed=10.00' "1-step X with E"
tiny tinyy 'G1 Y0.0125 E1 F600' 'steps=0,1,0,715 mm=1.000 nominal_speed=10.00' "1-step Y with E"
tiny tinyz 'G1 Z0.005 E1 F600' 'steps=0,0,2,715 mm=1.000 nominal_speed=10.00' "2-step Z with E"
tiny tiny3 'G1 X0.0375 E1 F600' 'steps=3,0,0,715 mm=1.000 nominal_speed=10.00' "3-step X with E (below the threshold)"
# at 4 steps the X length counts: 0.050 mm, E limits speed to 30*0.05/1 = 1.5 mm/s
tiny tiny4 'G1 X0.05 E1 F600' 'steps=4,0,0,715 mm=0.050 nominal_speed=1.50' "4-step X with E (at the threshold)"
tiny tinyord 'G1 X10 E1 F600' 'steps=800,0,0,715 mm=10.000 nominal_speed=10.00' "ordinary X with E"
run_pair tinynoe 'G90\nG1 X0.0125 F600\n'
grep -q 'moves=1 rejected=0 blocks=0 ' "$OUT/tinynoe.h" && grep -q 'moves=1 short_or_zero=1 blocks=0' "$OUT/tinynoe.m"
chk $? "1-step X with no E is dropped by both (no block)"

# 9. Supported subset: both programs accept exactly the same commands.
run_pair subset "$(cat "$FIX/replay-subset.gcode")\n"
[ $hrc = 0 ] && [ $mrc = 0 ]; chk $? "subset fixture (every supported and ignored command) exits 0 in both (got $hrc, $mrc)"
grep -q 'unsupported=0' "$OUT/subset.h"; chk $? "harness reports no unsupported command in the subset fixture"
diff <(grep '^rblock ' "$OUT/subset.h" | sed 's/ nominal_speed=.*//') <(grep '^rblock ' "$OUT/subset.m" | sed 's/ nominal_speed=.*//') >/dev/null
chk $? "subset fixture gives the same blocks in harness and model ($(grep -c '^rblock ' "$OUT/subset.h") blocks)"
python3 "$REF" "$FIX/replay-unsupported.gcode" >"$OUT/unsup.m" 2>"$OUT/unsup.merr"; rc=$?
[ $rc = 3 ]; chk $? "model fails closed on the G2 fixture with exit 3 (got $rc)"
grep -qx 'unsupported line 5: G2' "$OUT/unsup.merr"; chk $? "model names the unsupported G2 with its line number"
for c in 'G2 X20 Y20 I5 J5' 'G3 X20 Y20 I5 J5' 'G20' 'G29' 'G999' 'M203 X100' 'M220 S50' 'M999' 'T1'; do
  n="unsup$(echo "$c" | cut -d' ' -f1)"
  run_pair "$n" "G90\\n$c\\nG1 X10 F600\\n"
  [ $hrc = 3 ]; chk $? "harness refuses '$c' with exit 3 (got $hrc)"
  [ $mrc = 3 ] && grep -q "^unsupported line 2: $(echo "$c" | cut -d' ' -f1)" "$OUT/$n.merr"; chk $? "model refuses '$c' with exit 3 and its line number (got $mrc)"
done

# 10. E mode after every ordering of G90/G91 with M82/M83: Marlin's own
#     GcodeSuite methods (harness-real --emode-table) are the reference;
#     E_MODE_ABS/E_MODE_REL win until the next G90/G91 clears them.
"$H" --emode-table >"$OUT/emode.txt"; rc=$?
[ $rc = 0 ] && [ "$(grep -c '^emode ' "$OUT/emode.txt")" = 8 ]; chk $? "real GcodeSuite E-mode table has 8 orderings (exit $rc)"
for a in G90 G91 M82 M83; do for b in G90 G91 M82 M83; do
  [ "${a:0:1}" = "${b:0:1}" ] && continue
  ref=$(sed -n "s/^emode $a,$b e_relative=//p" "$OUT/emode.txt")
  hand=0; { [ "$b" = M83 ] || [ "$b" = G91 ]; } && hand=1   # the later command decides
  [ "$ref" = "$hand" ]; chk $? "$a then $b: GcodeSuite says E relative=$ref (hand reading of gcode.h: $hand)"
  [ "$ref" = 1 ] && exp=0,0,0,1430 || exp=0,0,0,715
  run_pair "emode$a$b" "G28\\n$a\\n$b\\nG1 E1 F600\\nG1 E1 F600\\n"
  both_steps "emode$a$b" "$exp" "$a then $b: two G1 E1 moves"
done; done

# 11. CodeRabbit review of 30ecaba.
# 11a. A command is its letter and its number: F1092 is not G92 (the old packed
#      letter*1000+number key made them equal), nor F1090/F1028 G90/G28, nor
#      L1082/L1400 M82/M400. All are outside the subset, so both exit 3.
for c in 'F1092 E5' 'F1090' 'F1028' 'L1082' 'L1400'; do
  n="pack$(echo "$c" | cut -d' ' -f1)"
  run_pair "$n" "G90\\nM82\\n$c\\nG1 X10 F600\\n"
  [ $hrc = 3 ] && grep -q "^unsupported line 3: $(echo "$c" | cut -d' ' -f1)\$" "$OUT/$n.h"; chk $? "harness refuses '$c' as its own command, exit 3 (got $hrc)"
  [ $mrc = 3 ]; chk $? "model refuses '$c', exit 3 (got $mrc)"
done
# 11b. G28 resyncs E as well: homing ends in sync_plan_position(), i.e.
#      planner.set_position_mm(), which re-rounds every axis. G1 E0.002 is
#      1 step (1.43) and deferred, so after G28 the E baseline is
#      LROUND(0.002f*715.12f) = 1 and G1 E1 is 715 - 1 = 714 steps.
run_pair g28e 'G90\nM82\nG1 E0.002 F600\nG28\nG1 E1 F600\n'
both_steps g28e 0,0,0,714 "deferred E before G28 is resynced by homing"
# 11c. Word text the parser cannot read (a checksum, a stray sign) is refused,
#      not skipped: the harness stops with exit 3 on a bad token, and the
#      model must not accept the rest of the line either.
for c in 'G92 E5*7' 'G1 X10*7' 'G1 X10 E-' 'G1 X.' 'M104 S200*7'; do
  n="junk$(echo "$c" | tr -dc 'A-Z0-9')"
  run_pair "$n" "G90\\nM82\\n$c\\n"
  [ $hrc = 3 ]; chk $? "harness refuses unreadable words in '$c', exit 3 (got $hrc)"
  [ $mrc = 3 ] && grep -q '^unsupported line 3: ' "$OUT/$n.merr"; chk $? "model refuses unreadable words in '$c' with its line number, exit 3 (got $mrc)"
done

echo "NOTE: host simulation of the real planner; no hardware validation."
[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]
