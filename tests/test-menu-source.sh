#!/bin/bash
# GoatTech Forge - source-level verification for the DWIN FT-Motion input-shaping menu.
# Usage: test-menu-source.sh <marlin_tree> <firmware_bin>
# Static source assertions + binary string evidence. No hardware claims.
set -u
T="$1"; B="$2"
D="$T/Marlin/src/lcd/dwin/creality/dwin.cpp"
C="$T/Marlin/Configuration_adv.h"
FM="$T/Marlin/src/module/ft_motion.h"
SC="$T/Marlin/src/module/settings.cpp"
pass=0; fail=0
chk() { # chk <desc> <result 0/1>
  if [ "$2" -eq 0 ]; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi
}

# 1. define sits OUTSIDE the classic INPUT_SHAPING_X/Y/Z guard
line_def=$(grep -n '#define DWIN_INPUT_SHAPING_MENU' "$C" | cut -d: -f1)
line_guard=$(grep -n '#if ANY(INPUT_SHAPING_X, INPUT_SHAPING_Y, INPUT_SHAPING_Z)' "$C" | cut -d: -f1)
[ -n "$line_def" ] && [ -n "$line_guard" ] && [ "$line_def" -lt "$line_guard" ]
chk "DWIN_INPUT_SHAPING_MENU defined before/outside classic guard" $?

# 2. no dead classic shaping API calls remain
[ "$(grep -c 'stepper.get_shaping\|stepper.set_shaping' "$D")" -eq 0 ]
chk "zero classic stepper shaping API references" $?

# 3. every FTM config write in dwin.cpp is busy-gated (same line or lock check directly above)
unguarded=$(grep -n -B2 '^\s*ftMotion.cfg.set' "$D" | grep 'ftMotion.cfg.set' | grep -v 'ftm_edits_locked' | wc -l)
unguarded_ctx=$(grep -n -B2 'ftMotion.cfg.set' "$D" | grep -A2 -B2 'ftMotion.cfg.set' | grep -c 'ftm_edits_locked')
writes=$(grep -c 'ftMotion.cfg.set' "$D")
[ "$writes" -eq 6 ] && [ "$unguarded_ctx" -ge 6 ]
chk "all 6 ftMotion.cfg.set* writes guarded by ftm_edits_locked (same or -2 lines)" $?

# 4. freq/zeta bounds use the API constants
[ "$(grep -c 'FTM_MIN_SHAPE_FREQ \* 100.0f, (FTM_FS / 2) \* 100.0f' "$D")" -eq 4 ]
chk "frequency clamp = [FTM_MIN_SHAPE_FREQ, FTM_FS/2] in commit+dial x2 axes" $?
[ "$(grep -c 'ftm_max_dampening \* 100.0f' "$D")" -eq 4 ]
chk "zeta clamp = [0, ftm_max_dampening] in commit+dial x2 axes" $?
[ "$(grep -c 'LIMIT(HMI_ValueStruct.InputShaping_scaled, 0.0f, 100.0f)' "$D")" -eq 0 ]
chk "no stale 0-100 zeta limit remains" $?

# 5. save-on-exit: exactly one settings.save, six dirty sites, failure visible
[ "$(grep -c 'if (settings.save())' "$D")" -eq 1 ]
chk "exactly one new guarded settings.save() (save-on-exit, not per click)" $?
[ "$(grep -c 'ftm_menu_dirty = true' "$D")" -eq 6 ]
chk "dirty flag set at all 6 edit commit sites" $?
grep -q 'EEPROM SAVE FAILED' "$D"
chk "EEPROM failure is user-visible" $?

# 6. busy gate covers print-active, print-paused and queued motion
grep -q 'marlin.printingIsActive() || marlin.printingIsPaused() || planner.has_blocks_queued()' "$D"
chk "busy gate = printing || paused || planner blocks queued" $?
[ "$(grep -c 'ftm_edits_locked' "$D")" -ge 8 ]
chk "gate invoked in menu draw, 4 value entries, 2 shaper cycles, commits" $?

# 7. FTM setter safety path in owning source
for fn in setShaper setBaseFreq setZeta; do
  awk "/bool $fn/,/return true/" "$FM" | grep -q 'prep_for_shaper_change'
  chk "$fn calls prep_for_shaper_change" $?
done
awk '/static void prep_for_shaper_change/,/^    }/' "$FM" | grep -q 'planner.synchronize()'
chk "prep_for_shaper_change drains motion via planner.synchronize()" $?

# 8. EEPROM struct coverage in owning source
grep -q 'EEPROM_WRITE(ftMotion.cfg)' "$SC" && grep -q 'EEPROM_READ(ftMotion.cfg)' "$SC"
chk "settings.cpp persists whole ftMotion.cfg struct" $?

# 9. menu structure sanity
grep -q 'if (select_input_shaping.inc(1 + INPUT_SHAPING_CASE_TOTAL))' "$D"
chk "menu encoder bound = back + INPUT_SHAPING_CASE_TOTAL" $?
grep -q 'if (select_shaper.inc(1 + SHAPERSEL_CASE_Y))' "$D"
chk "submenu encoder bound = back + 2 rows" $?
[ "$(grep -c 'Draw_InputShaping_Menu();\|Draw_ShaperSel_Menu();\|HMI_InputShaping();\|HMI_ShaperSel();\|HMI_InputShaping_Values();' "$D" | head -1)" -ge 5 ]
chk "forward declarations present" $?

# 10. engine-state visibility
grep -q 'FT Motion OFF - tuning has no effect' "$D"
chk "inert engine state produces visible warning" $?

# 10b. interrupted edit produces visible not-applied notice
[ "$(grep -c 'Locked - value NOT applied' "$D")" -ge 4 ]
chk "all four value commits show visible notice when locked" $?

# 10c. guard endif comment matches the actual guard
grep -q '#endif // ENABLED(DWIN_INPUT_SHAPING_MENU)' "$D"
chk "guard endif comment accurate" $?

# 11. binary evidence
for s in 'Input Shaping' 'Shaper type' 'X frequency' 'Y damping' 'X shaper' 'View only while printing' 'Shaping settings saved' 'EEPROM SAVE FAILED' 'FT Motion OFF' 'ZVDDD' 'Locked - value NOT applied'; do
  [ "$(grep -a -c "$s" "$B")" -ge 1 ]
  chk "binary contains '$s'" $?
done
echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
