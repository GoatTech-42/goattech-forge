# Host harness Marlin config

Copies of the patched Ender 3 V3 SE `Configuration.h` / `Configuration_adv.h`
(pinned C13 tree plus the Forge patch chain) with only host-build changes, so
the real planner and temperature modules compile on a PC. Every difference
from the patched firmware config:

`Configuration.h`
- `MOTHERBOARD` = `BOARD_SIMULATED` instead of `BOARD_CREALITY_V3_GD303`
  (Marlin's native/Linux HAL)
- X/Y/Z/E0 driver types = `A4988` instead of `TMC2208` (no TMCStepper on host)
- `S_CURVE_ACCELERATION` off
- `BLTOUCH` off (no servo on host)
- `AUTO_BED_LEVELING_BILINEAR` off: no bed leveling is compiled into the planner

`Configuration_adv.h`
- `AUTOTEMP`, `FT_MOTION` and `BLTOUCH_HS_MODE` off (clang rejects their
  constexpr/typedef use)
- `E0_AUTO_FAN_PIN` off (no STM32 pin names on host)
- `DWIN_INPUT_SHAPING_MENU` off (DWIN UI is not built)
- `LIN_ADVANCE` off
- `G29_RETRY_AND_RECOVER` off (no bed leveling)

Each file also defines a marker (`FORGE_HOST_HARNESS_CONFIG`,
`FORGE_HOST_HARNESS_CONFIG_ADV`) that `harness/build-real.sh` and
`harness/real/*.cpp` require, so a build that picks up another config fails.

Because of the list above, the host harness does not exercise S-curve
acceleration, Linear Advance, FT-Motion, AUTOTEMP or bed leveling, and its
planner results are for this host config, not the firmware build.
Not a hardware configuration. Nothing here is hardware validation.
