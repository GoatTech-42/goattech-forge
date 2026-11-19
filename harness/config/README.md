# Host harness Marlin config

Copies of the Ender 3 V3 SE Configuration.h / Configuration_adv.h with only
host-build changes, so the real planner and temperature modules compile:

- MOTHERBOARD = BOARD_SIMULATED (Marlin's native/Linux HAL)
- X/Y/Z/E0 drivers = A4988 (no TMCStepper on host)
- FT_MOTION, AUTOTEMP, BLTOUCH_HS_MODE off (clang rejects their constexpr/typedef use)
- BLTOUCH and E0_AUTO_FAN_PIN off (no servo or STM32 pin names on host)

Not a hardware configuration. Nothing here is hardware validation.
