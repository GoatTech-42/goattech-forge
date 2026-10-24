#!/usr/bin/env bash
# test-diag-generator.sh - static (source-level) checks for the Forge
# diagnostics plate generator (forge_diag.cpp/.h). These check that the
# safety structure is present in source: gate before openFileWrite,
# sentinel as the exact final line, fail-closed cleanup paths, and the
# counting/writing emission sharing one code path. They do NOT prove
# runtime behavior; they fail loudly if the safety structure is removed.
# Usage: ./test-diag-generator.sh <marlin-tree>   (tree = Marlin/ root)
set -u
TREE="${1:?usage: $0 <marlin-tree>}"
SRC="$TREE/src/e3v3se/forge_diag.cpp"
HDR="$TREE/src/e3v3se/forge_diag.h"
CR="$TREE/src/sd/cardreader.cpp"
PASS=0; FAIL=0
ck() { # ck <label> <0|1>
  if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf 'PASS %s\n' "$1";
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; fi
}
[ -f "$SRC" ] || { echo "FAIL: $SRC missing"; exit 1; }

# 1. Entry gate: all four conditions present, and it precedes openFileWrite.
GATE_LINE=$(grep -n 'printingIsActive() || .*printingIsPaused() || .*isFileOpen() || .*has_blocks_queued()' "$SRC" | head -1 | cut -d: -f1)
OPEN_LINE=$(grep -n "card.openFileWrite(" "$SRC" | head -1 | cut -d: -f1)
ck "gate has all four conditions (active/paused/fileOpen/queued)" "$([ -n "$GATE_LINE" ]; echo $?)"
ck "gate precedes first openFileWrite" "$([ -n "$GATE_LINE" ] && [ -n "$OPEN_LINE" ] && [ "$GATE_LINE" -lt "$OPEN_LINE" ]; echo $?)"

# 2. Mount and overwrite gates.
grep -q 'isMounted()' "$SRC"; ck "card mount gate present" "$?"
grep -q 'fileExists(FORGE_DIAG_JOB_NAME) && !allow_overwrite' "$SRC"; ck "overwrite gate present" "$?"

# 3. Sentinel emitted as the exact final emit in the emission path.
LAST_EMIT=$(grep -n '^  emit(' "$SRC" | tail -1)
echo "$LAST_EMIT" | grep -q 'FORGE_DIAG_SENTINEL "\\n"' ; ck "sentinel is the final emit line" "$?"
grep -q 'define FORGE_DIAG_SENTINEL  ";FORGE_DIAG_COMPLETE"' "$HDR"; ck "sentinel literal matches guard contract" "$?"

# 4. closefile before every return after the open (fail-closed audit):
#    every 'return false' after the open line is in a block that closed first
#    or never had the file open. We check structurally: closefile() appears
#    immediately after emit_plate in generate_plate, and each later failure
#    path calls removeFile.
grep -q 'emit_plate(p);' "$SRC"; ck "generation calls shared emit_plate" "$?"
awk '/openFileWrite/,/^}/' "$SRC" | grep -q 'card.closefile()'; ck "closefile on the post-open path" "$?"
N_REM=$(awk '/openFileWrite/,/^}/' "$SRC" | grep -c 'removeFile(FORGE_DIAG_TEMP_NAME)')
ck "fail-closed removeFile on all 3 error paths (found $N_REM)" "$([ "$N_REM" -ge 3 ]; echo $?)"

# 5. One shared emission path for count and write (no drift between the
#    estimate shown on the review screen and the bytes actually written).
N_CALLS=$(grep -c 'emit_plate(' "$SRC")
ck "emit_plate called from both estimate and generate ($N_CALLS call sites incl. def use)" "$([ "$N_CALLS" -ge 3 ]; echo $?)"
grep -q 'count_only' "$SRC" && grep -q 'byte_count' "$SRC"; ck "counting sink implemented via count_only/byte_count" "$?"

# 6. No direct card.write outside the emit() sink (all output length-checked).
N_WRITE=$(grep -c 'card.write' "$SRC")
ck "exactly one card.write call site (the emit sink)" "$([ "$N_WRITE" = 1 ]; echo $?)"

# 7. No PLR, no motion commands to the printer itself, no queue injection:
#    generator must only write a file, never call queue.inject or M24/M25.
grep -Eq 'queue\.inject|M24|M25|process_subcommands' "$SRC"; ck "no G-code injection into the live queue" "$([ $? -ne 0 ]; echo $?)"

# 8. Header/API wiring: names match the cardreader guard's expectations.
grep -q 'FORGE_DIAG_JOB_NAME  "FORGDIA1.G"' "$HDR"; ck "job name FORGDIA1.G in header" "$?"
grep -q 'FORGE_DIAG_TEMP_NAME "FORGDIA1.TMP"' "$HDR"; ck "temp name FORGDIA1.TMP in header" "$?"
grep -q 'FORGE_DIAG' "$CR"; ck "guard references the reserved names in cardreader.cpp" "$?"

echo "---"; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
