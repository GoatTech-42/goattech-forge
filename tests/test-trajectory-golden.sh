#!/usr/bin/env bash
# Forge F1(c): golden traces for the diagnostics plate emission, per board tree.
# The real forge_diag.cpp from each patched tree (C13 pin and C14 pin) is
# compiled into the host harness, the three nozzle variants are emitted, and
#  1. each emitted file matches its golden fingerprint (tests/golden/plate-<n>.txt:
#     sha256, size, line/move counts, XYZ ranges, max E), so ANY change in the
#     emitted bytes shows up here and has to be reviewed;
#  2. harness/trajectory_check.py passes on every emitted file;
#  3. negative checks: deliberately motion-breaking edits of the 0.40 plate
#     (no sentinel, out-of-bounds travel, Z dive into printed material, XY
#     travel through printed spikes, double retract, relative-E deretract
#     without a retract) must each make trajectory_check.py FAIL for the
#     expected reason;
#  4. every tree must emit byte-identical plates (C13 vs C14).
# Usage: test-trajectory-golden.sh <marlin-tree> [<marlin-tree> ...]
#        test-trajectory-golden.sh --write-golden <marlin-tree>   (developer: rewrite goldens)
# Host simulation of emitted G-code text only. Not hardware validation.
set -u
WRITE=0
[ "${1:-}" = "--write-golden" ] && { WRITE=1; shift; }
[ $# -ge 1 ] || { echo "usage: $0 [--write-golden] <marlin-tree> [...]"; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOLD="$ROOT/tests/golden"
TC="$ROOT/harness/trajectory_check.py"
SUM="$ROOT/tests/trace_summary.py"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fails=0
chk(){ if [ "$1" = 0 ]; then echo "PASS: $2"; else echo "FAIL: $2"; fails=$((fails+1)); fi; }

# emit <tree> <dir>: build the harness against the tree's forge_diag, write plates to <dir>/plate.<n>.gcode
emit() {
  local tree="$1" d="$2"
  mkdir -p "$d"; cp -r "$ROOT/harness/." "$d/h"
  mkdir -p "$d/h/src/e3v3se"
  cp "$tree/Marlin/src/e3v3se/forge_diag.cpp" "$tree/Marlin/src/e3v3se/forge_diag.h" "$d/h/src/e3v3se/" || return 1
  ( cd "$d/h" && g++ -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o harness-bin \
      && ./harness-bin "$d/plate" >"$d/harness.log" ) || return 1
}

first=""
n=0
for TREE in "$@"; do
  n=$((n+1)); D="$OUT/t$n"
  echo "== tree $n: $(git -C "$TREE" rev-parse --short HEAD 2>/dev/null || echo "$TREE")"
  emit "$TREE" "$D"; chk $? "plate emission harness builds and runs"
  [ -f "$D/plate.40.gcode" ] || { echo "RESULT: emission failed"; exit 1; }
  for v in 20 40 80; do
    python3 "$SUM" "$D/plate.$v.gcode" >"$D/sum.$v"
    if [ $WRITE = 1 ]; then cp "$D/sum.$v" "$GOLD/plate-$v.txt"; echo "wrote $GOLD/plate-$v.txt"; fi
    diff "$GOLD/plate-$v.txt" "$D/sum.$v" >"$D/diff.$v"; chk $? "nozzle_x100=$v matches the golden fingerprint"
    [ -s "$D/diff.$v" ] && sed 's/^/  /' "$D/diff.$v"
    python3 "$TC" "$D/plate.$v.gcode" >"$D/tc.$v" 2>&1; chk $? "nozzle_x100=$v passes trajectory_check"
  done
  if [ -z "$first" ]; then first="$D"
  else
    for v in 20 40 80; do cmp -s "$first/plate.$v.gcode" "$D/plate.$v.gcode"; chk $? "tree $n emits the same bytes as tree 1 (nozzle_x100=$v)"; done
  fi
done

# --- negative checks on the 0.40 plate of the first tree
P="$first/plate.40.gcode"
# mut <name> <label the failing check must carry> <python statements editing the line list L>
mut() {
  local name="$1" label="$2" edit="$3" f="$OUT/mut-$1.gcode"
  python3 - "$P" "$f" <<PY
import sys
L = open(sys.argv[1]).read().split('\n')
last = max(i for i, l in enumerate(L) if l.startswith("G1") and " E" in l and " X" in l)
$edit
open(sys.argv[2], 'w').write('\n'.join(L))
PY
  python3 "$TC" "$f" >"$OUT/mut-$name.log" 2>&1; local rc=$?
  [ $rc != 0 ]; chk $? "mutation '$name' makes trajectory_check fail (exit $rc)"
  grep -q "^FAIL .*$label" "$OUT/mut-$name.log"; chk $? "mutation '$name' fails the expected check ($label)"
}
mut no-prime-height "prime explicitly sets" 'del L[next(i for i, l in enumerate(L) if l.startswith("G1 Z"))]'
mut zero-prime-height "prime explicitly sets" 'L[next(i for i, l in enumerate(L) if l.startswith("G1 Z"))] = "G1 Z0 F600"'
mut high-prime-height "prime explicitly sets" 'L[next(i for i, l in enumerate(L) if l.startswith("G1 Z"))] = "G1 Z10 F600"'
mut no-sentinel "sentinel" 'L = [l for l in L if "FORGE_DIAG_COMPLETE" not in l]'
mut out-of-bounds "bed/Z bounds" "L.insert(last + 1, 'G1 X300 Y10 F3000')"
mut z-dive "no Z descents" "L.insert(last + 1, 'G1 Z0.00 F600')"
mut xy-through-spike "no XY travels" "L[last+1:last+1] = ['G1 Z5 F600', 'G1 X30 Y60 F3000', 'G1 X90 Y60 F3000']"
mut double-retract "no double retracts" "L[last+1:last+1] = ['M83', 'G1 E-1 F2400', 'G1 E-1 F2400', 'M82']"
mut relative-e-deretract "no deretract" "L[last+1:last+1] = ['G91', 'G1 E2 F2400', 'G90']"
# a legitimate G91 relative retract followed by a relative deretract must stay clean
python3 - "$P" "$OUT/ok-g91.gcode" <<'PY'
import sys
L = open(sys.argv[1]).read().split('\n')
last = max(i for i, l in enumerate(L) if l.startswith("G1") and " E" in l and " X" in l)
L[last+1:last+1] = ['G91', 'G1 E-2 F2400', 'G1 E2 F2400', 'G90']
open(sys.argv[2], 'w').write('\n'.join(L))
PY
python3 "$TC" "$OUT/ok-g91.gcode" >"$OUT/ok-g91.log" 2>&1; chk $? "G91 relative retract then deretract is accepted"

echo "NOTE: host simulation of emitted G-code text; no hardware validation."
[ $fails = 0 ] && echo "RESULT: all checks passed" || echo "RESULT: $fails failure(s)"
[ $fails = 0 ]
