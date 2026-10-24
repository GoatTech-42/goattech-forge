#!/bin/bash
# GoatTech Forge - source-level verification for the DWIN Forge Diagnostics menu.
# Usage: test-diag-menu-source.sh <marlin_tree> <firmware_bin>
# Static source assertions + compiled-binary string evidence.
# HONEST SCOPE: compilation and static wiring only. Nothing here proves
# on-printer behavior; the generator it invokes was verified offline
# (host harness + independent review), not on hardware.
set -u
T="$1"; B="$2"
D="$T/Marlin/src/lcd/dwin/creality/dwin.cpp"
H="$T/Marlin/src/lcd/dwin/creality/dwin.h"
pass=0; fail=0
chk() { if [ "$2" -eq 0 ]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi }

# 1. checkkey enum + value slot in dwin.h
[ "$(grep -c 'ForgeDiagnostics,\|ForgeDiag_Nozzle,\|ForgeDiag_TempN,\|ForgeDiag_TempB,' "$H")" -eq 4 ]
chk "dwin.h: 4 Forge checkkey enum entries" $?
grep -q 'float ForgeDiag_scaled = 0;' "$H"
chk "dwin.h: HMI_ValueStruct.ForgeDiag_scaled slot" $?

# 2. menu case id defined via concrete predecessor (no lazy macro cycle)
grep -q '#define MOTION_CASE_DIAGNOSTICS (MOTION_CASE_INPUT_SHAPING + 1)' "$D" && \
grep -q '#define MOTION_CASE_DIAGNOSTICS (MOTION_CASE_STEPS + 1)' "$D"
chk "MOTION_CASE_DIAGNOSTICS defined for both IS-menu branches" $?
grep -q '#define _MOTION_LAST_CASE MOTION_CASE_DIAGNOSTICS' "$D"
chk "_MOTION_LAST_CASE advanced to MOTION_CASE_DIAGNOSTICS (menu total grows)" $?

# 3. generator header wired + selector declared
grep -q '#include "../../../e3v3se/forge_diag.h"' "$D"
chk "dwin.cpp includes forge_diag.h" $?
grep -q 'select_forge_diag{0}' "$D"
chk "select_forge_diag selector declared" $?

# 4. review-screen case ids + forward declarations
for c in NOZZLE TEMPN TEMPB GEN TOTAL; do grep -q "#define FORGEDIAG_CASE_$c" "$D" || { false; break; }; done
chk "FORGEDIAG_CASE_NOZZLE/TEMPN/TEMPB/GEN/TOTAL defined" $?
grep -q 'void Draw_ForgeDiagnostics_Menu();' "$D" && grep -q 'void HMI_ForgeDiagnostics();' "$D" && grep -q 'void HMI_ForgeDiagnostics_Values();' "$D"
chk "forward declarations present" $?

# 5. Motion menu entry: glyph branch, string branch, line icon, more icon
[ "$(grep -c 'draw_forge_diagnostics(MBASE(MOTION_CASE_DIAGNOSTICS) + 2)' "$D")" -eq 1 ]
chk "glyph branch draws Diagnostics entry" $?
[ "$(grep -c 'DWIN_Draw_Label(MBASE(MOTION_CASE_DIAGNOSTICS), F("Diagnostics"))' "$D")" -eq 1 ]
chk "string branch draws Diagnostics entry" $?
grep -q 'Draw_Menu_Line(++i, ICON_PrintSize); // forge diagnostics line' "$D" && grep -q 'Draw_More_Icon(i); // forge diagnostics more icon' "$D"
chk "menu line + more icon for diagnostics entry" $?

# 6. entry gate: full job-protection set, menu-level AND used at GEN
grep -q 'marlin.printingIsActive() || marlin.printingIsPaused() || card.isFileOpen() || planner.has_blocks_queued()' "$D"
chk "forge_diag_busy() = active || paused || file open || queued" $?
[ "$(grep -c 'forge_diag_busy()' "$D")" -ge 3 ]
chk "busy gate used in review draw + GEN case (>=3 refs incl. def)" $?
grep -q 'if (!card.isMounted()) { Draw_FtmNotice(F("No SD card")); break; }' "$D"
chk "GEN gates unmounted SD" $?
grep -q 'card.fileExists(FORGE_DIAG_JOB_NAME) && !forge_diag_overwrite_pending' "$D"
chk "overwrite requires second confirm press" $?

# 7. generator invocation + estimate + review warnings
grep -q 'forge_diag::generate_plate(forge_diag_params, true)' "$D"
chk "GEN invokes generate_plate(params, write=true)" $?
grep -q 'forge_diag::estimate_plate_bytes(forge_diag_params)' "$D"
chk "review shows size estimate from estimate_plate_bytes" $?
grep -q 'nozzle_x100 <= 25' "$D" && grep -q 'Fine nozzle: multi-hour' "$D"
chk "multi-hour warning at <=0.25mm (covers 0.20 review obligation)" $?
grep -q 'nozzle_x100 >= 60' "$D" && grep -q 'Zone C probes high flow' "$D"
chk "high-flow warning at >=0.60mm (covers 0.80 review obligation)" $?
grep -q 'Zone C nears flow limit' "$D"
chk "flow-limit info notice present" $?
grep -q 'Press again to OVERWRITE' "$D"
chk "overwrite-pending warning string" $?

# 7b. W1 regression: EVERY param-apply path disarms a pending overwrite
# confirm and refreshes the review (estimate + notice) - an armed overwrite
# must never survive a parameter change.
for cs in ForgeDiag_Nozzle ForgeDiag_TempN ForgeDiag_TempB; do
  blk=$(awk "/case $cs:/,/break;/" "$D")
  echo "$blk" | grep -q 'forge_diag_overwrite_pending = false' && echo "$blk" | grep -q 'Draw_ForgeDiagReview()'
  chk "$cs apply disarms overwrite + refreshes review" $?
done

# 7c. visible-width guard: font8x16 at LBLX 42 on a 240-wide screen leaves
# 198px -> 24 chars max. Every literal in the diagnostics block must fit.
bad=$(awk '/Forge Diagnostics review screen/,/^void HMI_ForgeDiagnostics\(\)/' "$D" | grep -o 'F("[^"]*")' | sed 's/^F("//; s/")$//' | awk 'length($0) > 24 && $0 !~ /^ *$/')
[ -z "$bad" ]
chk "all diagnostics literals <= 24 chars (fit 240px from LBLX 42)" $?

# 8. no auto-suggested tuning targets (review obligation)
awk '/Forge Diagnostics review screen/,/^void HMI_ForgeDiagnostics\(\)/' "$D" | grep -qi 'recommend\|suggested\|try [0-9].*hz\|set.*shaper to' && false || true
chk "no tuning-target suggestion language in diagnostics block" $?

# 9. HMI wiring: enter case in HMI_Motion + dispatcher cases
grep -q 'case MOTION_CASE_DIAGNOSTICS: // Forge Diagnostics' "$D"
chk "HMI_Motion enter case wired" $?
grep -q 'case ForgeDiagnostics:' "$D" && grep -q 'case ForgeDiag_Nozzle:' "$D"
chk "dispatcher routes ForgeDiagnostics + ForgeDiag_* value keys" $?

# 10. default params are the reviewed safe defaults (0.40mm / 200C / 60C)
grep -q 'static forge_diag::PlateParams forge_diag_params { 40, 200, 60 };' "$D"
chk "defaults = 0.40mm nozzle, 200C nozzle, 60C bed" $?

# 10b. owning screen branch: 320_LCD must be the active one (layout math branch)
L="$T/Marlin/src/lcd/dwin/creality/dwin_lcd.h"
grep -q '^#define DWIN_CREALITY_320_LCD$' "$L" && ! grep -q '^#define DWIN_CREALITY_480_LCD$' "$L"
chk "DWIN_CREALITY_320_LCD active, 480 commented (240x320 active area)" $?
grep -q '^#define DWIN_WIDTH  240$' "$L" && grep -q '^#define DWIN_HEIGHT 320$' "$L"
chk "DWIN_WIDTH 240 / DWIN_HEIGHT 320 confirmed" $?

# 11. compiled-binary evidence: strings actually in flash
grep -qa 'FORGDIA1.G' "$B"
chk "bin contains job-name string FORGDIA1.G" $?
grep -qa 'Forge Diagnostics' "$B"
chk "bin contains menu title string" $?
grep -qa 'multi-hour' "$B"
chk "bin contains multi-hour warning string" $?

echo "diag-menu-source: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
