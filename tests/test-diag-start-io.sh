#!/usr/bin/env bash
# Isolated execution of the real SD start/resume function, not SD-media proof.
set -euo pipefail
TREE="${1:?usage: test-diag-start-io.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/forge_diag.h"
python3 - "$TREE/Marlin/src/sd/cardreader.cpp" "$OUT/original.cpp" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
a='void CardReader::startOrResumeFilePrinting() {'
b='\n//\n// Run tasks upon finishing or aborting a file print.'
assert s.count(a)==1 and s.count(b)==1, 'unexpected start/resume function boundaries'
Path(sys.argv[2]).write_text(s[s.index(a):s.index(b)])
PY
read -r -a CXXCMD <<<"${CXX:-c++}"
run() {
  "${CXXCMD[@]}" -std=c++17 -O1 -I"$OUT" "$ROOT/tests/start-guard-driver.cpp" -o "$OUT/start" || return 2
  "$OUT/start"
}
cp "$OUT/original.cpp" "$OUT/start-function.cpp"
run
for mutant in tail_seek restore_seek short_read; do
  python3 - "$OUT/original.cpp" "$OUT/start-function.cpp" "$mutant" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
changes={
 'tail_seek': ('const bool tail_seek_ok = myfile.seekSet(filesize - tail);',
               'const bool tail_seek_ok = (myfile.seekSet(filesize - tail), true);'),
 'restore_seek': ('const bool restored = myfile.seekSet(sdpos);',
                  'const bool restored = (myfile.seekSet(sdpos), true);'),
 'short_read': ('n == (int)tail && restored', 'n > 0 && restored'),
}
a,b=changes[sys.argv[3]]
assert s.count(a)==1, 'unexpected I/O guard spelling'
Path(sys.argv[2]).write_text(s.replace(a,b,1))
PY
  rc=0
  run > "$OUT/mutant.log" 2>&1 || rc=$?
  if [ "$rc" = 1 ] && grep -q '^FAIL start guard:' "$OUT/mutant.log"; then
    echo "PASS: $mutant mutation rejected by start guard assertions"
  else
    cat "$OUT/mutant.log"
    echo "FAIL: $mutant not detected (exit $rc)"; exit 1
  fi
done
echo 'PASS: diagnostic start I/O checks (host/source only)'
