#!/usr/bin/env bash
# Mutation contract for the pinned SD-close source check, not firmware execution.
set -euo pipefail
TREE="${1:?usage: test-74-sdclose-contract.sh <patched-marlin-tree>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
for p in Marlin/src/lcd/dwin/creality/dwin.cpp Marlin/src/MarlinCore.cpp \
         Marlin/src/sd/cardreader.cpp Marlin/src/sd/cardreader.h \
         Marlin/src/gcode/queue.cpp Marlin/Configuration_adv.h; do
  mkdir -p "$OUT/tree/$(dirname "$p")"
  cp "$TREE/$p" "$OUT/tree/$p"
done
bash "$ROOT/tests/test-74-sdclose.sh" "$OUT/tree" >"$OUT/baseline.log" 2>&1 || {
  cat "$OUT/baseline.log"; exit 1;
}
cp "$OUT/tree/Marlin/src/lcd/dwin/creality/dwin.cpp" "$OUT/original.cpp"
fails=0
for mutant in noop extra wrong_pause comment_decoy moved_outside raw_literal continued_comment split_comment digit_separator; do
  python3 - "$OUT/original.cpp" "$OUT/tree/Marlin/src/lcd/dwin/creality/dwin.cpp" "$mutant" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
a='if (!Marlin::printJobOngoing() && !Marlin::printingIsPaused())\n      card.closefile();'
assert s.count(a)==1, 'unexpected pinned guard spelling'
replacements={
 'noop': a.replace('card.closefile();', '(void)0;\n    card.closefile();'),
 'extra': a+'\n    card.closefile();',
 'wrong_pause': 'if (!Marlin::printJobOngoing())\n      card.closefile();\n    // '+a.replace('\n',' '),
 'comment_decoy': '// '+a.replace('\n',' ')+'\n    card.closefile();',
 'moved_outside': '(void)0;\n    card.closefile();',
 'raw_literal': 'const char *fixture = u8R"forge(embedded " quote\n'+a+'\n)forge";',
 'continued_comment': '// continued fixture '+chr(92)+'\n'+a,
 'split_comment': '/'+chr(92)+'\n/ split fixture '+chr(92)+'\n'+a,
 'digit_separator': "int fixture_before = 1'000;\n    "+a+"\n    int fixture_after = 2'000;",
}
s=s.replace(a,replacements[sys.argv[3]],1)
if sys.argv[3]=='moved_outside':
    # Preserve the old whole-file predicate hit in an unrelated function.
    s+='\nvoid unrelated_contract_fixture() { '+a+' }\n'
Path(sys.argv[2]).write_text(s)
PY
  rc=0
  bash "$ROOT/tests/test-74-sdclose.sh" "$OUT/tree" >"$OUT/mutant.log" 2>&1 || rc=$?
  diagnostic='^FAIL: Goto_MainMenu closefile containment contract'
  case "$mutant" in
    continued_comment|split_comment|digit_separator)
      diagnostic='^FAIL: Goto_MainMenu closefile containment contract: unsupported lexical construct' ;;
  esac
  if [ "$rc" = 1 ] && grep -q "$diagnostic" "$OUT/mutant.log"; then
    echo "PASS: $mutant rejected by containment contract"
  else
    cat "$OUT/mutant.log"
    echo "FAIL: $mutant was not rejected by containment contract (exit $rc)"
    fails=$((fails+1))
  fi
done
printf 'RESULT: %s containment contract failure(s)\n' "$fails"
[ "$fails" = 0 ]
