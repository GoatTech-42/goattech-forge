#!/usr/bin/env bash
# Execute the real generator and isolated DWIN value handler. Host-only.
set -euo pipefail
TREE="${1:?usage: test-bed-target.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
cp "$OUT/harness/src/e3v3se/forge_diag.cpp" "$OUT/generator-original.cpp"
python3 - "$TREE/Marlin/src/lcd/dwin/creality/dwin.cpp" "$OUT/handler-original.cpp" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
start='void HMI_ForgeDiagnostics_Values()\n{'
end='\nvoid HMI_ForgeDiagnostics()\n{'
assert s.count(start)==1 and s.count(end)==1, 'unexpected DWIN handler boundaries'
Path(sys.argv[2]).write_text(s[s.index(start):s.index(end)])
PY
read -r -a CXXCMD <<<"${CXX:-c++}"
build_run() {
  (cd "$OUT/harness" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/generator") || return 2
  local failed=0
  "$OUT/generator" > "$OUT/generator.log" 2>&1 || failed=1
  grep -E '^(PASS|FAIL) bed target:' "$OUT/generator.log"
  "${CXXCMD[@]}" -std=c++17 -O1 -I"$OUT" -I"$OUT/harness" "$ROOT/tests/bed-menu-driver.cpp" -o "$OUT/menu" || return 2
  "$OUT/menu" || failed=1
  [ "$failed" = 0 ]
}
cp "$OUT/handler-original.cpp" "$OUT/handler.cpp"
build_run
# Wrong ceiling, one degree too low/high, must be caught in each production consumer.
for consumer in generator menu; do
  for replacement in BED_MAXTEMP 'BED_MAX_TARGET - 1' 'BED_MAX_TARGET + 1'; do
    cp "$OUT/generator-original.cpp" "$OUT/harness/src/e3v3se/forge_diag.cpp"
    cp "$OUT/handler-original.cpp" "$OUT/handler.cpp"
    target="$OUT/handler.cpp"
    [ "$consumer" = generator ] && target="$OUT/harness/src/e3v3se/forge_diag.cpp"
    python3 - "$target" "$replacement" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
assert 'BED_MAX_TARGET' in s, 'bed target fix missing'
p.write_text(s.replace('BED_MAX_TARGET','('+sys.argv[2]+')'))
PY
    rc=0
    build_run > "$OUT/mutant.log" 2>&1 || rc=$?
    if [ "$rc" = 1 ] && grep -q '^FAIL bed \(target\|menu\):' "$OUT/mutant.log"; then
      echo "PASS: $consumer mutation $replacement fails bed target assertions"
    else
      cat "$OUT/mutant.log"
      echo "FAIL: $consumer mutation $replacement not detected (exit $rc)"
      exit 1
    fi
  done
done
echo 'PASS: bed target boundary contract (host-only)'
