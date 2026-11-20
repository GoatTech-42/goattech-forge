#!/usr/bin/env bash
# Dirty runtime M200 mode, real pinned handler/parser/planner. Host-only.
set -euo pipefail
TREE="${1:?usage: test-diag-volumetric.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
read -r -a CXXCMD <<<"${CXX:-c++}"
(cd "$OUT/harness" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/generator")
"$OUT/generator" "$OUT/plate" > "$OUT/generator.log"
python3 - "$TREE/Marlin/src/gcode/config/M200-M205.cpp" "$OUT/harness/real/m200-handler.inc" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a='  void GcodeSuite::M200() {'
b='\n  void GcodeSuite::M200_report'
assert s.count(a)==1 and s.count(b)==1
Path(sys.argv[2]).write_text(s[s.index(a):s.index(b)])
PY
cp "$ROOT/tests/volumetric-driver.cpp" "$OUT/harness/real/main.cpp"
# The real parser.cpp owns this definition in the probe.
sed -i '/^bool GCodeParser::volumetric_enabled = false;$/d' "$OUT/harness/real/stubs.cpp"
bash "$OUT/harness/build-real.sh" "$TREE" "$OUT/real" > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 2; }
for nozzle in 20 40 80; do "$OUT/real/harness-real" "$OUT/plate.$nozzle.gcode"; done
for mutant in missing enabled late; do
  python3 - "$OUT/plate.40.gcode" "$OUT/mutant.gcode" "$mutant" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
assert s.count('M200 S0\n')==1
if sys.argv[3]=='missing': s=s.replace('M200 S0\n','')
elif sys.argv[3]=='enabled': s=s.replace('M200 S0\n','M200 S1\n')
else: s=s.replace('M200 S0\n','')+'M200 S0\n'
Path(sys.argv[2]).write_text(s)
PY
  rc=0
  "$OUT/real/harness-real" "$OUT/mutant.gcode" > "$OUT/mutant.log" 2>&1 || rc=$?
  if [ "$rc" = 1 ] && grep -q '^FAIL volumetric:' "$OUT/mutant.log"; then
    echo "PASS volumetric: $mutant mutant refused by dirty-mode probe"
  else
    cat "$OUT/mutant.log"; echo "FAIL volumetric: $mutant mutant not caught (exit $rc)"; exit 1
  fi
done
