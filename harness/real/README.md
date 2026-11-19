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
initial or final rate exceeds their nominal rate (`--blocks` adds one line per
block). It follows Marlin's relative-mode rules (G90/G91 replace the whole
state, so G91 makes E relative even after M82 and G90 makes it absolute even
after M83; M82/M83 override E after that) and treats G28 as a position reset to
0,0,0. Blocks are popped one at a time only when the queue is full, so
lookahead sees a realistic queue. `G0`/`G1`, `G28`, `G90`/`G91`, `M82`/`M83`,
`G92`, `G21`, `M400` and a short list of no-motion commands (`G4`, `M104`,
`M109`, `M140`, `M190`, `M106`, `M107`, `M84`, `M105`, `M117`, `M73`) are
accepted. Anything else (arcs, `G20`, `M203`-`M205`, `M220`/`M221`, ...) is
named with its line number and the replay exits 3, so a file the replay cannot
model is never reported as checked. The hotend is treated as hot (no heater
simulation), and time does not advance.

`tests/test-harness-gcode-replay.sh <marlin-tree>` compares the replay with an
independent Python model (`tests/replay_reference.py`, float32 positions, no
Marlin code): per block for the small hand-written `tests/fixtures/replay-small.gcode`
(steps, length and nominal speed, which includes the Z and E axis speed
limits), and block count plus total steps per axis for the three diagnostics
plates the real `forge_diag.cpp` generates. Its negative checks are a wrong X
steps/mm, an edited move and an unsupported `G2`.

`tests/test-harness-real-planner.sh <marlin-tree>` builds it and checks the
output. `tests/test-harness-build-isolation.sh` and
`tests/test-harness-spaced-path.sh` cover the scratch-copy and spaced-path
behaviour of `build-real.sh`. Host simulation only; it is not hardware
validation.
