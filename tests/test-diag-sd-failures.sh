#!/usr/bin/env bash
# Run the real generator against fake SD failures; never printer validation.
set -euo pipefail
TREE="${1:?usage: test-diag-sd-failures.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
cp -R "$ROOT/harness" "$OUT/harness"
mkdir -p "$OUT/harness/src/e3v3se"
cp "$TREE/Marlin/src/e3v3se/forge_diag.cpp" "$TREE/Marlin/src/e3v3se/forge_diag.h" "$OUT/harness/src/e3v3se/"
cp "$OUT/harness/src/e3v3se/forge_diag.cpp" "$OUT/original.cpp"
read -r -a CXXCMD <<<"${CXX:-c++}"
run() {
  (cd "$OUT/harness" && "${CXXCMD[@]}" -std=c++17 -O1 -include harness_common.h -I. \
    main.cpp src/e3v3se/forge_diag.cpp -o "$OUT/generator") || return 2
  "$OUT/generator"
}
run >"$OUT/baseline.log" 2>&1 || { cat "$OUT/baseline.log"; exit 1; }
fails=0
for mutant in verify_cleanup rename_cleanup rename_ignored; do
  python3 - "$OUT/original.cpp" "$OUT/harness/src/e3v3se/forge_diag.cpp" "$mutant" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
anchors={
 'verify_cleanup': ('if (!verified) {\n    f.close();\n    card.removeFile(FORGE_DIAG_TEMP_NAME);',
                    'if (!verified) {\n    f.close();'),
 'rename_cleanup': ('if (!f.rename(&dir, FORGE_DIAG_JOB_NAME)) {\n    f.close();\n    card.removeFile(FORGE_DIAG_TEMP_NAME);',
                    'if (!f.rename(&dir, FORGE_DIAG_JOB_NAME)) {\n    f.close();'),
 'rename_ignored': ('if (!f.rename(&dir, FORGE_DIAG_JOB_NAME)) {',
                    'if ((f.rename(&dir, FORGE_DIAG_JOB_NAME), false)) {'),
}
a,b=anchors[sys.argv[3]]
assert s.count(a)==1, 'unexpected generator source shape'
Path(sys.argv[2]).write_text(s.replace(a,b,1))
PY
  rc=0
  run >"$OUT/mutant.log" 2>&1 || rc=$?
  if [ "$rc" = 1 ] && grep -q '^FAIL SD failure:' "$OUT/mutant.log"; then
    echo "PASS: $mutant detected by generator failure assertions"
  else
    cat "$OUT/mutant.log"
    echo "FAIL: $mutant not detected by generator failure assertions (exit $rc)"
    fails=$((fails+1))
  fi
done
cat "$OUT/baseline.log"
printf 'RESULT: %s SD failure contract failure(s)\n' "$fails"
[ "$fails" = 0 ]
