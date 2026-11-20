#!/usr/bin/env bash
# Actual generator and isolated command handlers; no heater wait simulation.
set -euo pipefail
TREE="${1:?usage: test-diag-cooling.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
python3 - "$TREE/Marlin/src/gcode/temp" "$OUT" <<'PY'
from pathlib import Path
import sys
for name,end,out in [('M104_M109','\n#if ENABLED(AUTOTEMP)\n  //','hotend'),('M140_M190','\n#endif // HAS_HEATED_BED','bed')]:
 s=(Path(sys.argv[1])/(name+'.cpp')).read_text()
 a='void GcodeSuite::'+name+'('
 assert s.count(a)==1
 start=s.index(a);stop=s.index(end,start)
 (Path(sys.argv[2])/(out+'-handler.inc')).write_text(s[start:stop])
PY
read -r -a CXXCMD <<<"${CXX:-c++}"
"${CXXCMD[@]}" -std=c++17 -O1 -I"$OUT" "$ROOT/tests/cooling-driver.cpp" -o "$OUT/probe"
"${CXXCMD[@]}" -std=c++17 -O1 -include "$OUT/harness/harness_common.h" -I"$OUT/harness" "$ROOT/tests/cooling-emitter.cpp" "$OUT/harness/src/e3v3se/forge_diag.cpp" -o "$OUT/emitter"
failed=0
for bed in 0 60; do
 "$OUT/emitter" "$OUT/plate.$bed" "$bed"
 for current in 20 280; do "$OUT/probe" "$OUT/plate.$bed" "$bed" "$current" || failed=1; done
done
[ "$failed" = 0 ] || exit 1
for mutant in nozzle_s bed_s zero_r late; do
 python3 - "$OUT/plate.60" "$OUT/plate.0" "$OUT/mutant" "$mutant" <<'PY'
from pathlib import Path
import sys
mode=sys.argv[4];s=Path(sys.argv[2] if mode=='zero_r' else sys.argv[1]).read_text()
if mode=='nozzle_s':
 assert s.count('M109 R200')==1;s=s.replace('M109 R200','M109 S200')
elif mode=='bed_s':
 assert s.count('M190 R60')==1;s=s.replace('M190 R60','M190 S60')
elif mode=='zero_r':
 assert s.count('M190 S0')==1;s=s.replace('M190 S0','M190 R0')
else:
 assert s.count('M109 R200\n')==1;s=s.replace('M109 R200\n','')+'M109 R200\n'
Path(sys.argv[3]).write_text(s)
PY
 rc=0;bed=60;[ "$mutant" = zero_r ] && bed=0
 "$OUT/probe" "$OUT/mutant" "$bed" 280 > "$OUT/mutant.log" 2>&1 || rc=$?
 if [ "$rc" = 1 ] && grep -q '^FAIL cooling request:' "$OUT/mutant.log"; then
  echo "PASS cooling request: $mutant mutant caught"
 else
  cat "$OUT/mutant.log";echo "FAIL cooling request: $mutant not caught (exit $rc)";exit 1
 fi
done
