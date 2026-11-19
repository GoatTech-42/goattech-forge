# Real planner/temperature host harness (F1a)

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

`tests/test-harness-real-planner.sh <marlin-tree>` builds it and checks the
output. `tests/test-harness-build-isolation.sh` and
`tests/test-harness-spaced-path.sh` cover the scratch-copy and spaced-path
behaviour of `build-real.sh`. Host simulation only; it is not hardware
validation.
