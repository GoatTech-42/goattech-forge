# Real planner/temperature host harness (F1a, F1b)

`harness/build-real.sh <marlin-tree> [out-dir]` compiles Marlin's real
`Marlin/src/module/planner.cpp` and `temperature.cpp` from the given tree
(the pinned upstream with the Forge patch chain applied) against the host
config in `harness/config`, and links them with:

- `main.cpp`: queues known moves through the real `Planner::buffer_line`,
  drains the blocks with `get_current_block`/`release_current_block`, and
  prints steps, block length, nominal speed and nominal rate per block, then
  exercises the real target-temperature setters, the max-target clamp and the
  thermistor conversion. `--steps-x N` overrides X steps/mm (negative test).
- `stubs.cpp`: typed host stubs for what the two modules reference but the
  harness does not run.

The build works on a scratch copy of `<marlin-tree>/Marlin`, copied with
symlinks dereferenced, so the tree is only read, even when `Marlin/` or its
`Configuration*.h` are symlinks. A `Marlin/Config.h` in the tree is left out
of the scratch copy, since Marlin would otherwise use it instead of the host
config. `build-real.sh` checks a marker define from `harness/config` in
`planner.cpp`, `temperature.cpp`, `main.cpp` and `stubs.cpp`, and fails if
any of them was compiled with a different config.

## What is disabled or stubbed on the host

Config (full list in `harness/config/README.md`): simulated board, A4988
drivers instead of TMC2208, and `S_CURVE_ACCELERATION`, `LIN_ADVANCE`,
`FT_MOTION`, `AUTOTEMP`, `BLTOUCH`/`BLTOUCH_HS_MODE`,
`AUTO_BED_LEVELING_BILINEAR`, `G29_RETRY_AND_RECOVER`, `E0_AUTO_FAN_PIN` and
`DWIN_INPUT_SHAPING_MENU` off. So no bed leveling, S-curve, Linear Advance,
FT-Motion or AUTOTEMP is exercised.

Runtime (`stubs.cpp`, `main.cpp`):
- No stepper ISR: `Stepper::is_block_busy()` is always false, so blocks are
  drained by the driver, not executed; `Stepper` position, enable and
  endstop calls are no-ops returning 0, and `Endstops::poll()` does nothing.
- No live heater loop: `Temperature::manage_heater()` and the temperature
  ISR are never called. Only the target setters, the max-target clamp,
  `tooColdToExtrude` and the thermistor tables are exercised.
- `millis()` returns `harness_millis`, a fixed value the driver sets; time
  does not advance on its own.
- `MarlinHAL::adc_value()` returns `harness_adc`, a fixed stub reading; the
  thermistor check passes raw values straight to the conversion functions.
- HAL timers, `analogWrite` and `delay` are no-ops.
- `Motion::get_move_distance()` is a copy of the cartesian formula from
  `motion.cpp`; the rest of `Motion` (homing check, quickstop) is stubbed.
- Serial output is discarded; UI, DWIN, SD card, host actions, G-code
  subcommands, fans, print counter and `Nozzle::park` are no-ops.
- `Marlin::idle()` does nothing; `Marlin::kill()` prints and exits with 3.

## G-code replay (F1b)

`harness-real --gcode FILE [--blocks]` replays a G-code file through the real
`Planner::buffer_line` instead of the built-in moves and prints the number of
blocks, total steps per axis, total block length and the count of blocks whose
initial or final rate exceeds their nominal rate (reported, not a failure: the
planner's minimum-segment-time slowdown can cause it on very short blocks) (`--blocks` adds one line per
block). It follows Marlin's relative-mode rules
(G90/G91 replace the whole state, so G91 makes E relative even after M82 and
G90 makes it absolute even after M83; M82/M83 override E after that), and
`harness-real --emode-table` prints the E mode after each ordering of G90/G91
with M82/M83 straight from Marlin's own `GcodeSuite` methods, which the test
uses as the reference. Blocks are popped one at a time only when the queue is
full, so lookahead sees a realistic queue.

Accepted subset (the Python model accepts exactly the same one):
- Motion and state: `G0`/`G1`, `G90`/`G91`, `M82`/`M83`, `G21`, `G28`, `G92`
  (E only, or no words), `M400`.
- Ignored, no motion: `G4`, `M104`, `M109`, `M140`, `M190`, `M106`, `M107`,
  `M84`, `M73`, `M105`, and `M117`, whose free text is never parsed.

`G28` is simplified homing: a position reset to 0,0,0 without motion, then
every axis is resynced (`set_position_mm`), as the firmware's
`sync_plan_position()` does after homing (the model re-rounds E the same way). `G92 E<value>` follows `G92.cpp`:
only E changes, and only when it differs from the current E by more than
`NEAR_ZERO`; then `planner.set_e_position_mm()` re-rounds the E step baseline
alone, so a deferred sub-`MIN_STEPS_PER_SEGMENT` X/Y/Z move still counts from
its old baseline. Queued blocks are drained before the reset, so the setter
takes its no-queued-blocks branch; the sync block the firmware queues when
blocks are pending is not modelled or counted. A bare `G92` changes nothing.
`G92` with X, Y, Z or any other word, or `E` without a value, is refused
before anything changes: workspace offsets are on in this config, so a real
`G92 X` shifts the workspace instead of the planner position, and neither
program models that.

Numbers have no exponent (`X10E2` is X10 then E2), lines of any length
are read whole, and a read error exits 74. A command is matched on its letter
and number separately (`F1092` is not `G92`), and a repeated word letter keeps
its last occurrence, as Marlin's `FASTER_GCODE_PARSER` does (`G92 E E5` is
`G92 E5`; `G92 E5 E` has no E value and is refused). A `G0`/`G1` whose last
`X`, `Y`, `Z`, `E` or `F` word has no number (`G1 X`, `G1 X10 X`, `G1 X20 F`) is refused by both
programs with exit 3, before the feed rate or any position changes. This is a
refused subset, not a firmware bug: in the pinned source, `parser.cpp` records
each word with `set(letter, valptr)`, `valptr` null when no number follows,
so the last occurrence of a letter wins; `parser.h` `seenval(c)` is
`seen(c) && has_value()`, false for that word; and `gcode.cpp`
`get_destination_from_command()` reads every axis and E with `seenval()`, so
the firmware leaves that axis where it is. The feed-rate reader checks
`floatval('F') > 0`. `floatval` calls `seenval` and defaults to zero for a bare F,
so the previous feed rate is kept. Neither program models that
bare-word reading. Numbered F words are accepted; as in the pinned firmware,
zero and negative F keep the previous feed rate and still perform the move.
Positive F outside finite binary32 is refused by both programs with exit 3 and
a line number, before the feed rate or position changes. Its nonfinite planner
behavior is outside the modelled subset; this is not firmware validation.
When the last occurrence has a number (`G1 X X10`), it is that
number, in Marlin and in both programs. Word text neither program can
read, such as a `*7` checksum or a sign with no digits, is refused with exit 3
(the replay stops at once with `error: bad token`).
A segment below `MIN_STEPS_PER_SEGMENT` is deferred by the planner, and the
model does the same. When no X/Y/Z axis reaches `MIN_STEPS_PER_SEGMENT` but E
does, the block length is the E distance (`!XYZ_HAS_ENOUGH_STEPS` in
`planner.cpp`), in the model as in the planner. Anything outside the subset
(arcs, `G20`, `M203`-`M205`, `M220`/`M221`, tool changes, ...) is named with its
line number, by the replay on stdout and by the model on stderr, and both exit
3, so a file they cannot model is never reported as checked; the replay still
prints its totals, with `unsupported=` above 0. The hotend is treated as hot (no heater
simulation), and time does not advance.

`tests/test-harness-gcode-replay.sh <marlin-tree>` compares the replay with an
independent Python model (`tests/replay_reference.py`, float32 positions, no
Marlin code): per block for the small hand-written `tests/fixtures/replay-small.gcode`
(steps, length and nominal speed, which includes the Z and E axis speed
limits), and block count plus total steps per axis for the three diagnostics
plates the real `forge_diag.cpp` generates. Its negative checks are a wrong X
steps/mm, an edited move and an unsupported `G2`. It also checks, in both
programs: E-only `G92` keeping deferred X/Y/Z baselines, the unchanged-E no-op,
refused `G92` forms leaving X and E untouched, refused `G0`/`G1` axis words
with no value leaving X, E and the feed rate untouched, E resets on a float32 half step
(rounded half away from zero), short X/Y/Z segments with extrusion around the
4-step threshold, every supported and ignored command
(`tests/fixtures/replay-subset.gcode`), representative unsupported commands,
and the E mode for all eight G90/G91 and M82/M83 orderings.

`tests/test-harness-real-planner.sh <marlin-tree>` builds it and checks the
output. `tests/test-harness-build-isolation.sh` and
`tests/test-harness-spaced-path.sh` cover the scratch-copy and spaced-path
behaviour of `build-real.sh`. Host simulation only; it is not hardware
validation.

### Source-only menu checks

`tests/test-menu-source-contract.sh <patched-marlin-tree>` runs the two menu
source checks with `--source-only` and verifies that the diagnostics check
rejects an injected tuning suggestion. CI runs this against both pinned board
trees. Source-only mode does not read a firmware binary or verify its strings.
The default two-argument mode still requires a readable, nonempty firmware
binary and checks its strings separately. A synthetic string fixture used by
the contract test isolates the assertion mutant; it is not compiled evidence.
None of these source checks validates the on-printer menu or its layout.

### Offline patch-pin contract

Before source CI applies any Forge patch, `scripts/verify-patch-pins.py` checks
all six literal patch paths and SHA256 declarations in `build.sh`. It reads
those declarations as data, never as shell code. Missing, duplicate or dynamic
declarations, invalid paths and hashes, symlinks, missing files and modified
patch bytes fail the check. `tests/test-patch-pins.sh` runs scratch-copy
regressions and checks that CI verifies pins before applying patches. This
checks repository inputs only, not a compiled binary or hardware behavior.
