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
  harness does not run (UI, serial, HAL timers, stepper ISR, G-code).
  `millis()` and the ADC read come from `harness_hooks.h`.

`tests/test-harness-real-planner.sh <marlin-tree>` builds it and checks the
output. Host simulation only; it is not hardware validation.
