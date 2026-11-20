#!/usr/bin/env bash
# Actual emission wording and byte-identical command stream versus PR24.
set -euo pipefail
TREE="${1:?usage: test-diag-speed-caveat.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
read -r -a CXXCMD <<<"${CXX:-c++}"
(cd "$OUT/harness" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/generator")
"$OUT/generator" "$OUT/plate" > "$OUT/emission.log"
python3 - "$OUT" <<'PY'
from pathlib import Path
import hashlib,sys
root=Path(sys.argv[1])
# PR24 emitted command-stream hashes, excluding only blank/comment lines.
baseline={20:'41b4f05baf085edfa5a1bb3f3ab8501f100d427dfcada0e7efa2ce5f8c52d1a5',
40:'94746df41fdff6aa24ab2678b02099dbcfa7702e13b0e76fa06fea83ac5e6ad5',
80:'ba9c1c5869db52e464803d49637b93a15377b770ddce623a6088b309bd16fb9e'}
def valid(s):
 return (b'; Runtime acceleration settings are not normalized; commanded speeds are not guaranteed.\n' in s
         and b'DEFAULT_ACCELERATION 3000' not in s and b'segments reach 120mm/s' not in s)
failed=False
for v,want in baseline.items():
 s=(root/('plate.%d.gcode'%v)).read_bytes()
 commands=b''.join(l for l in s.splitlines(keepends=True) if l.strip() and not l.lstrip().startswith(b';'))
 ok=valid(s) and hashlib.sha256(commands).hexdigest()==want
 print(('PASS' if ok else 'FAIL')+' speed caveat: nozzle%d wording and unchanged command bytes'%v)
 failed |= not ok
 if valid(s.replace(b'; Runtime acceleration settings are not normalized; commanded speeds are not guaranteed.\n',b'')):
  print('FAIL speed caveat: missing-caveat mutant survived');failed=True
 else: print('PASS speed caveat: missing-caveat mutant caught nozzle%d'%v)
sys.exit(1 if failed else 0)
PY
