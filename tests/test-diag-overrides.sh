#!/usr/bin/env bash
# Dirty runtime speed/flow, real pinned handlers/parser/planner. Host-only.
set -euo pipefail
TREE="${1:?usage: test-diag-overrides.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
read -r -a CXXCMD <<<"${CXX:-c++}"
(cd "$OUT/harness" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/generator")
"$OUT/generator" "$OUT/plate" > "$OUT/generator.log"
python3 - "$TREE/Marlin/src/gcode/config" "$OUT/harness/real" <<'PYCODE'
from pathlib import Path
import sys
for num in (220,221):
 s=(Path(sys.argv[1])/('M%d.cpp'%num)).read_text()
 a='void GcodeSuite::M%d() {'%num
 start=s.index(a); end=s.index('\n}',start)+2
 (Path(sys.argv[2])/('m%d-handler.inc'%num)).write_text(s[start:end])
PYCODE
cp "$ROOT/tests/overrides-driver.cpp" "$OUT/harness/real/main.cpp"
# The real parser.cpp owns this definition in the probe.
sed -i '/^bool GCodeParser::volumetric_enabled = false;$/d' "$OUT/harness/real/stubs.cpp"
bash "$OUT/harness/build-real.sh" "$TREE" "$OUT/real" > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 2; }
for nozzle in 20 40 80; do "$OUT/real/harness-real" "$OUT/plate.$nozzle.gcode"; done
for mutant in speed_missing flow_missing speed_wrong flow_wrong speed_late flow_late; do
 python3 - "$OUT/plate.40.gcode" "$OUT/mutant.gcode" "$mutant" <<'PYCODE'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); mode=sys.argv[3]
cmd='M220 S100\n' if mode.startswith('speed') else 'M221 S100\n'
assert s.count(cmd)==1
if mode.endswith('wrong'): s=s.replace(cmd,cmd.replace('100','150'))
elif mode.endswith('late'): s=s.replace(cmd,'')+cmd
else: s=s.replace(cmd,'')
Path(sys.argv[2]).write_text(s)
PYCODE
 rc=0; "$OUT/real/harness-real" "$OUT/mutant.gcode" > "$OUT/mutant.log" 2>&1 || rc=$?
 if [ "$rc" = 1 ] && grep -q '^FAIL overrides:' "$OUT/mutant.log"; then
  echo "PASS overrides: $mutant mutant caught"
 else
  cat "$OUT/mutant.log"; echo "FAIL overrides: $mutant not caught (exit $rc)";exit 1
 fi
done
