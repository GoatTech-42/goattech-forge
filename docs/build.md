# Building GoatTech firmware

This repo vendors no Marlin source. `build.sh` is the whole pipeline: it
clones the pinned upstream port, applies the minimal GoatTech branding diff,
and builds one binary for one board.

## Upstream and attribution

GoatTech builds on navaismo's Marlin 2.1 port for the Ender-3 V3 SE:
https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE (branches `c13_sd` and
`c14_sd`), itself derived from Marlin (GPLv3) and Creality's published source.
All feature work in the base firmware is upstream's; GoatTech adds branding,
unified docs, and this reproducible build. Pinned commits:

| Board | Branch | Commit |
| --- | --- | --- |
| C13 | `c13_sd` | `efc211e87aa74c16587cc6f15899b3206aa3295c` |
| C14 | `c14_sd` | `14c5165729684b7b87282f6d25c1239b6569d9e3` |

The branding diff is exactly two lines in `Marlin/Configuration.h`
(`STRING_CONFIG_H_AUTHOR` and `CUSTOM_MACHINE_NAME`). The script verifies the
exact upstream lines before patching and fails closed if upstream changes.

## Requirements

- Linux or macOS with `git` and Python 3
- PlatformIO Core (`pip install platformio`); the STM32 toolchain downloads
  automatically on first build

## Build

    bash build.sh c13   # CR4NS200320C13, GD32F303RET6 (env STM32F103RET6_creality)
    bash build.sh c14   # CR4NS200320C14, STM32F401RET6 (env STM32F401RE_creality)

Output: `dist/GoatTech-Ender3V3SE-<board>-v<version>.bin`, with a sha256
printed at the end of the build. Both targets compile green at the pinned
commits. Compilation is not hardware validation: neither target has run on a
physical printer yet.

## SD card layout per board

- C13: copy the `.bin` to the SD card root. If the bootloader ignores a
  repeated filename, rename the file and retry.
- C14: place the `.bin` inside a folder named `STM32F4_UPDATE` on the SD card.

## Safety gate

Build only the target matching the printer's physically confirmed mainboard
silkscreen label and MCU part number. A label alone is not proof: at least
one C14-labelled unit shipped with a GD chip (see docs/research.md). Keep the
matching Creality stock firmware on hand as the recovery path before any
flash, and confirm it targets the same board. The printer owner performs any
flash, by their own decision.
