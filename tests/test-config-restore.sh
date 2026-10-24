#!/usr/bin/env bash
# Static (source-level) checks for the Forge config restore
# (S_CURVE_ACCELERATION + LIN_ADVANCE re-enabled to the krasnaya_4 baseline).
# Verifies the defines are active in the patched tree, not behavior on hardware.
set -u
T="${1:-/home/sandbox/goattech-fw/marlin-c13}"
CFG="$T/Marlin/Configuration.h"
ADV="$T/Marlin/Configuration_adv.h"
pass=0; fail=0
chk() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
chk "S_CURVE_ACCELERATION active"  'grep -q "^#define S_CURVE_ACCELERATION$" "$CFG"'
chk "S_CURVE not commented out"    '! grep -q "^//#define S_CURVE_ACCELERATION$" "$CFG"'
chk "LIN_ADVANCE active"           'grep -q "^#define LIN_ADVANCE$" "$ADV"'
chk "LIN_ADVANCE not commented"    '! grep -q "^//#define LIN_ADVANCE$" "$ADV"'
chk "ADVANCE_K default still 0.0"  'grep -q "^    #define ADVANCE_K 0.0" "$ADV"'
chk "FT_MOTION still enabled"      'grep -q "^#define FT_MOTION$" "$ADV"'
echo "== $pass passed, $fail failed =="
[ $fail -eq 0 ]
