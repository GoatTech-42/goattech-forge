# Architecture

How the GoatTech firmware is organized. Draft, follows the research in
[research.md](research.md).

## Base and branches

- Upstream base: navaismo/Marlin_bugfix_2.1_E3V3SE, branches c13_sd and c14_sd.
- GoatTech firmware branches track one board revision each:
  - goattech-c13 - from upstream c13_sd (GD32F303 / STM32F103-compatible, env
    STM32F103RET6_creality)
  - goattech-c14 - from upstream c14_sd (STM32F401, env STM32F401RE_creality;
    upstream marks this profile as awaiting printer validation)
- main stays the docs/project hub. Releases carry one binary per confirmed
  board revision, never a "universal" file.

## Change policy

- Small, documented diffs on top of upstream so rebasing stays cheap.
- Upstream attribution preserved in source headers and README (GPLv3).
- Safety configuration is read-only for this project: thermal runaway
  protection (hotend + bed), cold-extrusion prevention, lengthy-extrusion
  guard and temperature limits are never disabled or raised.
- Every binary release notes its exact target board + MCU, the upstream
  commit it was built from, and the config diff.

## Planned feature set (from upstream, credited)

FT_MOTION input shaping on, SD gcode thumbnails, one-click print, 6x6 mesh
leveling, LCD dimming, buzzer mute, fixed M600. Power-loss recovery stays
off by default, matching upstream.

## GoatTech additions (original work)

1. Display skin + boot screen via the TJC screen toolchain (separate TFT
   asset flash, independent of the mainboard firmware).
2. On-screen input-shaping menu (upstream exposes only M493 gcode; listed
   upstream as a later step - candidate to contribute back).
3. Guided first-print calibration: [calibration.md](calibration.md).
4. Unified docs for both board revisions.

## Build

- PlatformIO, one env per board (above). Both verified compiling from a clean
  checkout on 2026-10-24.
- Upstream ships a GitHub Actions workflow (build-marlin.yml) for toolchain-
  free builds; adopt it once source lands in this repo.
- Compilation is not hardware validation. First-flash on a real printer
  follows the calibration doc and starts with a small known-good print.

## Display skin toolchain

- Screen: TJC3224T132_011N (TJC/DWIN serial LCD). Screen firmware is built
  with TJC's editor and flashed separately from the mainboard.
- Community skin tooling exists (see research.md). All GoatTech visual assets
  get a pixel-level review before publishing.
