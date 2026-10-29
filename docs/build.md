# Building GoatTech firmware

This repo vendors no Marlin source. `build.sh` is the whole pipeline: it
clones the pinned upstream port, applies GoatTech branding and nine pinned
Forge patches, and builds one binary for one board and build variant.

## Upstream and attribution

GoatTech builds on navaismo's Marlin 2.1 port for the Ender-3 V3 SE:
https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE (branches `c13_sd` and
`c14_sd`), itself derived from Marlin (GPLv3) and Creality's published source.
The base firmware is upstream's; GoatTech adds the pinned Forge patches,
branding, docs, and this build script. Pinned commits:

| Board | Branch | Commit |
| --- | --- | --- |
| C13 | `c13_sd` | `efc211e87aa74c16587cc6f15899b3206aa3295c` |
| C14 | `c14_sd` | `14c5165729684b7b87282f6d25c1239b6569d9e3` |

The branding diff changes two lines in `Marlin/Configuration.h`
(`STRING_CONFIG_H_AUTHOR` and `CUSTOM_MACHINE_NAME`). The nine patches add
the shaping menu, SD-close guard, diagnostics start guard, config restore,
plate generator, diagnostics menu, version/report screen, prime-height/M107, and the 240px test-report fit
changes. `build.sh` pins the patch bytes and resulting source hashes and fails
closed on a mismatch.

## Requirements

- Linux or macOS with `git` and Python 3
- PlatformIO Core (`pip install platformio`); the STM32 toolchain downloads
  automatically on first build

## Build

    bash build.sh c13 test   # CR4NS200320C13, GD32F303RET6 (env STM32F103RET6_creality)
    bash build.sh c14 test   # CR4NS200320C14, STM32F401RET6 (env STM32F401RE_creality)

Output: `dist/GoatTech-Ender3V3SE-<board>-v0.6.0-test.bin`, with a sha256
printed at the end of the build. The `test` argument defines `FORGE_TEST_BUILD`:
it adds a read-only "Run diagnostics" report with current state and no heating,
motion or SD writes. Both variants show Forge's own version on the Info screen.
Omitting `test` builds the release variant without the report or `-test` suffix;
it does not make this candidate a validated release.

The prime-height descent and fan-off `M107` change are separate generated
G-code behavior changes included in both variants, not actions run by the
read-only report. They are not a bed-scrape fix or proof of physical clearance.

Both board test targets have compile and host-check evidence. The report
layout uses a stand-in font for host renders, not the real panel glyphs. This
v0.6 candidate has not been flashed or checked on the printer. Compilation
and host checks do not validate panel behavior or physical bed clearance.

## SD card layout per board

For reference only, not instructions to flash this candidate.

- C13: copy the `.bin` to the SD card root. If the bootloader ignores a
  repeated filename, rename the file and retry.
- C14: place the `.bin` inside a folder named `STM32F4_UPDATE` on the SD card.

## Safety gate

This branch is a test candidate, not a release or flash clearance. Do not
flash it or run generated prints on the strength of software checks alone.

Build only the target matching the printer's physically confirmed mainboard
silkscreen label and MCU part number. A label alone is not proof: at least
one C14-labelled unit shipped with a GD chip (see docs/research.md). Keep the
matching Creality stock firmware on hand as the recovery path before any
flash, and confirm it targets the same board. The printer owner performs any
flash, by their own decision.
