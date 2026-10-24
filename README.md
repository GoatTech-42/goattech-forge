# GoatTech Firmware for Ender 3 V3 SE

Custom GoatTech firmware for the Creality Ender 3 V3 SE, based on the community
Marlin 2.1.x port. A real upgrade over stock: input shaping, gcode thumbnails,
one-click print, finer mesh leveling and a proper UI - plus original GoatTech work
on top, not just a rebrand.

## Status

Docs and reproducible build pipeline live. **Nothing here is flash-ready yet.**
Binaries will only ever be published per confirmed board revision and MCU, and
compilation is not hardware validation.

## Building

`./build.sh c13` or `./build.sh c14` clones the pinned upstream port, applies the
minimal GoatTech branding diff (verified against the exact upstream lines), and
builds one binary for one board. See [docs/build.md](docs/build.md).

## Based on (with thanks)

- [MarlinFirmware/Marlin](https://github.com/MarlinFirmware/Marlin) (GPLv3)
- [CrealityOfficial/Ender-3V3-SE](https://github.com/CrealityOfficial/Ender-3V3-SE) - stock source (GPLv3)
- [navaismo/Marlin_bugfix_2.1_E3V3SE](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE) - the active community Marlin 2.1.x port for this printer (GPLv3)
- [navaismo/Ender-3V3-SE](https://github.com/navaismo/Ender-3V3-SE) - the original Community Edition

## What GoatTech adds

- GoatTech boot screen and display skin for the stock TJC/DWIN screen
- A guided first-print calibration walkthrough (e-steps, PID, Z-offset, shaper tuning)
- Unified docs covering both mainboard revisions end to end
- An on-screen input-shaping menu (upstream only exposes M493 gcode)

## Docs

- [docs/research.md](docs/research.md) - the grounded research behind the plan
- [docs/build.md](docs/build.md) - reproducible build pipeline
- [docs/calibration.md](docs/calibration.md) - first-print calibration walkthrough (reviewed)
- [docs/architecture.md](docs/architecture.md) - branch strategy and change policy

## Safety rules

- Thermal runaway protection stays enabled, always.
- Temperature limits are never raised.
- No binary is published until the exact board revision and MCU are confirmed.
- Recovery back to stock is verified per board before any flash instructions ship.

## Hardware note

The Ender 3 V3 SE ships with two mainboard revisions, CR4NS200320C13 and
CR4NS200320C14, with different MCUs and different flash procedures. Firmware
built for one does not boot on the other.

## License

GPL v3.0 - a derivative of GPL Marlin sources must stay GPL. See LICENSE.
