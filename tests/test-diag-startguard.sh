#!/usr/bin/env bash
# Static (source-level) tests for the Forge diagnostics start guard.
# No runtime claims: these verify the guard code exists and is wired at the
# chokepoint, not behavior on hardware.
set -u
T="${1:-/home/sandbox/goattech-fw/marlin-c13}"
C="$T/Marlin/src/sd/cardreader.cpp"
H="$T/Marlin/src/e3v3se/forge_diag.h"
pass=0; fail=0
chk() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }

chk "shared header exists"                '[ -f "$H" ]'
chk "job name constant"                   'grep -q "FORGE_DIAG_JOB_NAME  \"FORGDIA1.G\"" "$H"'
chk "temp name constant"                  'grep -q "FORGE_DIAG_TEMP_NAME \"FORGDIA1.TMP\"" "$H"'
chk "sentinel constant"                   'grep -q "FORGE_DIAG_SENTINEL  \";FORGE_DIAG_COMPLETE\"" "$H"'
chk "header included by cardreader"       'grep -q "#include \"../e3v3se/forge_diag.h\"" "$C"'
chk "guard inside startOrResume"          'awk "/void CardReader::startOrResumeFilePrinting/,/flag.sdprinting = true/" "$C" | grep -q "Forge diagnostics start guard"'
chk "guard before sdprinting flag"        '[ $(grep -n "Forge diagnostics start guard" "$C" | cut -d: -f1) -lt $(grep -n "flag.sdprinting = true;" "$C" | head -1 | cut -d: -f1) ]'
chk "temp name refused"                   'grep -q "strcmp(canon, FORGE_DIAG_TEMP_NAME)" "$C"'
chk "job name sentinel check"             'grep -q "strcmp(canon, FORGE_DIAG_JOB_NAME)" "$C" && grep -q "strstr(buf, FORGE_DIAG_SENTINEL)" "$C"'
chk "canonical case-fold"                 'grep -qF "*p -= '"'"'a'"'"' - '"'"'A'"'"'" "$C"'
chk "name from opened file (getDosName)"  'grep -qF "myfile.getDosName(canon)" "$C"' 
chk "read position restored"              'grep -q "myfile.seekSet(sdpos)" "$C"'
chk "refuse returns (2 paths)"            '[ $(awk "/void CardReader::startOrResumeFilePrinting/,/flag.sdprinting = true/" "$C" | grep -c "return;") -eq 2 ]'
echo "== $pass passed, $fail failed =="
[ $fail -eq 0 ]
