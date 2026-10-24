# Generator component design (forge_diag.cpp) - API facts verified at pins 2026-10-24

## Verified API facts (source, pin efc211e8, c13 tree)
- CardReader::openFileWrite(path): O_CREAT|O_APPEND|O_WRITE|O_TRUNC (truncates
  existing TMP - reviewer G1 confirmed). Calls abortFilePrintNow() first, so
  generation during an active print is structurally impossible. Sets
  flag.saving=true, selectFileByName(fname) (filename = 8.3), disables
  EMERGENCY_PARSER.
- CardReader::write(void*, uint16_t) -> int16_t: bytes written or -1
  (SdBaseFile::write impl at SdBaseFile.cpp:2175).
- CardReader::closefile(store_location=false): sync+close, clears saving/logging,
  sdpos=0, RE-ENABLES EMERGENCY_PARSER. Must be called on every exit path.
- CardReader::getWorkDir(): workDir.isOpen() ? workDir : root (cardreader.h:313).
- SdBaseFile::rename(SdBaseFile* dirFile, const char* newPath): same-volume,
  target must not exist (O_EXCL semantics); NOT atomic.
- CardReader::fileExists / removeFile exist (cardreader.h:226-227).
- openFileWrite path resolution: diveToFile(false, diveDirPtr, path) - relative
  to workDir. Generator always uses bare "FORGDIA1.TMP" (workDir-relative).
- FILENAME_LENGTH=13: "FORGDIA1.TMP" (12+NUL) fits exactly (SdFatConfig.h:104).

## Writer flow (fail-closed, every step checked)
1. openFileWrite(FORGE_DIAG_TEMP_NAME) - aborts any active print by design.
2. Write header (banner, firmware version, board target, UTC-less timestamp note,
   measured-temp block recorded at generation time: M105-style current temps are
   NOT available synchronously - use thermalManager current_temperature[0] and
   current_temperature_bed directly at generation time, print as comments).
3. Write start block (G28 if needed; ENABLE_LEVELING_AFTER_G28 is on so no M420 S1;
   G1 F1200 X0 Y0 collision-avoid confirmed pattern from dwin.cpp:12046-60).
4. Write zone plate G-code from fixed geometry tables (zone grid, extrusion math
   per confirmed-nozzle constraint - plate design v3 reviewer refinement #1).
5. Write end block, then sentinel ";FORGE_DIAG_COMPLETE" as the FINAL line
   (sentinel + trailing newline must be the last bytes; reviewer contract:
   within last 96 bytes - sentinel is 20 bytes, huge headroom).
6. If ANY write returns -1 or short: closefile(), removeFile(TMP), report
   failure (status line + serial). Fail-closed.
7. closefile() (re-enables emergency parser).
8. Reopen TMP read-only on getWorkDir(), verify size > 0, then publish:
   if fileExists(FORGE_DIAG_JOB_NAME): caller must have confirmed overwrite;
   removeFile(job) then rename(TMP -> FORGE_DIAG_JOB_NAME). If rename fails:
   removeFile(TMP), report.
9. Post-publish: fileExists(job) check; report byte count.

## Open design decisions (next run)
- Estimated-size function for the review screen: computed from the same line
  templates the writer emits (single source of truth - no drift).
- No free-space precheck (SdFat free-space query not wrapped); write-error
  path is the backstop.
- Zone geometry/nozzle constraint: derive from plate design v3 (reviewer
  refinement #1: nozzle param derives geometry/flow/layer bounds, not free range).
- M24-after-pause nuance: keep as documented caveat in generated file comments.

---

## Addendum 2026-10-24 (post-review v2): gate, transitions, publish verify, harness

This addendum supersedes any earlier pre-gate description above.

1. **Entry gate (reviewer must-fix, implemented):** `generate_plate` refuses while
   `printingIsActive || printingIsPaused || isFileOpen || has_blocks_queued`,
   BEFORE `openFileWrite` (whose abortFilePrintNow destroys a live SD job).
   The menu will gate again at entry.
2. **Inter-zone transitions (reviewer must-fix, implemented):** bounded helper
   `transition_to(x, y, z_dest)` = state-tracked retract -> lift to SAFE_Z=37
   (clears tallest feature, 35mm towers) -> XY travel -> descend onto EMPTY
   destination bed. Fixes A->B, box->patch, patch->C plunges and the box
   layer-0 diagonal extrusion. Retract is state-tracked (`g_retracted`) so
   chained transitions never double-retract. Final end-block travel lifts to
   Z5 before crossing the plate.
3. **Publish verify (reviewer requirement, implemented):** after closefile,
   the temp tail is re-read and the sentinel must be the exact final line
   before the rename publish; mismatch -> close + remove + false (fail-closed).
4. **Size vs estimate:** identical by construction (same emission path,
   counting sink vs SD sink); host harness asserts byte equality at all
   three verified params (0.40: 208,239B; 0.20: 500,368B; 0.80: 117,440B).
5. **Host harness (new, harness/):** replays the byte-identical emission on a
   fake SD: happy path, 5 gate refusals (all pre-openFileWrite), overwrite
   consent, short-write fail-closed, truncated tail, silent tail corruption
   caught only by the sentinel re-read. 27 assertions. Plus
   trajectory_check.py: simulates the emitted 7,791-move G-code on a 1mm
   heightmap - zero Z plunges into printed material, zero XY travels through
   material, zero double-retracts, zero phantom deretracts, all motion in
   bounds, sentinel exact final line. This is offline replay, still not
   on-printer proof.
6. **SAFE_Z margin (corrected after independent review):** tower height is
   round(35/layer_h)*layer_h; over the full integer nozzle_x100 sweep 20..80
   the worst overshoot is +0.105mm at nozzle 0.59 (layer_h 0.295, 119 layers
   -> 35.105mm), so SAFE_Z=37 clears printed geometry by >= 1.895mm
   everywhere. Verified from emitted bytes: max Z in every variant file is
   exactly 37.00 with zero collisions.
7. **Menu notes (owed to the menu component):** the review screen must WARN
   about the flow envelope (zone C reaches 9.6 mm3/s at 0.40 nozzle,
   30.7 mm3/s at 0.80 nozzle with 0.32 layers - beyond any stock hotend, a
   deliberate data-point probe, not a tuning target), must WARN that the
   0.20mm nozzle variant is a multi-hour print (350 tower layers, ~18.5k
   moves), and must not auto-suggest unproven tuning targets; the plate is a
   data-collection instrument, not a calibration of the user's machine.
