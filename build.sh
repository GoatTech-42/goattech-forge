#!/usr/bin/env bash
# GoatTech firmware build for the Ender-3 V3 SE.
#
# Overlay model: this repo vendors no Marlin source. The script clones the
# pinned upstream navaismo Marlin 2.1 port, applies the minimal GoatTech
# branding diff, and builds exactly one binary for exactly one board.
#
# Safety gate: build only the target matching the printer's physically
# confirmed mainboard label and MCU. A compiled binary is not a validated
# binary. The printer owner performs any flash, by their own decision.
set -euo pipefail

UPSTREAM_URL="https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE.git"
C13_BRANCH="c13_sd"
C13_COMMIT="efc211e87aa74c16587cc6f15899b3206aa3295c"
C13_ENV="STM32F103RET6_creality"
C14_BRANCH="c14_sd"
C14_COMMIT="14c5165729684b7b87282f6d25c1239b6569d9e3"
C14_ENV="STM32F401RE_creality"
GOATTECH_VERSION="0.1.0"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] || fail "Usage: $0 c13|c14"
case "$1" in
  c13)
    BOARD=c13; BRANCH="$C13_BRANCH"; COMMIT="$C13_COMMIT"; ENV_NAME="$C13_ENV"
    SD_NOTE="C13 (GD32F303RET6): copy the .bin onto the SD card root. Use a unique name per flash attempt if the bootloader ignores a repeated one."
    ;;
  c14)
    BOARD=c14; BRANCH="$C14_BRANCH"; COMMIT="$C14_COMMIT"; ENV_NAME="$C14_ENV"
    SD_NOTE="C14 (STM32F401RET6): place the .bin inside a folder named STM32F4_UPDATE on the SD card."
    ;;
  *) fail "Unknown board '$1'. Expected c13 or c14." ;;
esac

command -v git >/dev/null || fail "git not found"
command -v pio >/dev/null || command -v platformio >/dev/null || fail "PlatformIO not found (pip install platformio)"
PIO=$(command -v pio || command -v platformio)

cat <<BANNER
GoatTech build for Ender-3 V3 SE, board target: $BOARD
Confirm before flashing anything:
  - mainboard silkscreen label matches this target (CR4NS200320C13 or CR4NS200320C14)
  - MCU part number matches (C13: GD32F303RET6, C14: STM32F401RET6)
  - a label alone is not proof; at least one C14-labelled unit shipped with a GD chip
BANNER

WORK=".build/$BOARD"
CFG="$WORK/src/Marlin/Configuration.h"

if [ -d "$WORK/src/.git" ] && [ "$(git -C "$WORK/src" rev-parse HEAD 2>/dev/null)" = "$COMMIT" ]; then
  echo "Reusing staged upstream tree at $COMMIT (delete .build/$BOARD for a clean run)"
else
  rm -rf "$WORK"
  mkdir -p "$WORK"
  echo "Cloning upstream $BRANCH @ $COMMIT"
  git clone --quiet "$UPSTREAM_URL" "$WORK/src"
  git -C "$WORK/src" checkout --quiet "$COMMIT"
  [ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] || fail "pinned commit checkout mismatch"
fi

AUTHOR_OLD='#define STRING_CONFIG_H_AUTHOR "Marlin, Creality, Kraplax & Navaismo" // Original author or contributor.'
AUTHOR_NEW='#define STRING_CONFIG_H_AUTHOR "GoatTech build of Marlin by Creality, Kraplax \& Navaismo" // Original author or contributor.'
NAME_OLD='#define CUSTOM_MACHINE_NAME "Ender-3 V3 SE"'
NAME_NEW='#define CUSTOM_MACHINE_NAME "GoatTech Ender-3 V3 SE"'

if grep -qF 'GoatTech build of Marlin' "$CFG" && grep -qF 'GoatTech Ender-3 V3 SE' "$CFG"; then
  echo "Branding already applied"
else
  grep -qF "$AUTHOR_OLD" "$CFG" || fail "upstream author line changed; re-verify Configuration.h before branding"
  grep -qF "$NAME_OLD" "$CFG" || fail "upstream machine-name line changed; re-verify Configuration.h before branding"
  sed -i "s|$AUTHOR_OLD|$AUTHOR_NEW|" "$CFG"
  sed -i "s|$NAME_OLD|$NAME_NEW|" "$CFG"
  grep -qF 'GoatTech build of Marlin' "$CFG" || fail "branding did not apply (author)"
  grep -qF 'GoatTech Ender-3 V3 SE' "$CFG" || fail "branding did not apply (machine name)"
fi

echo "Building env $ENV_NAME (this downloads the toolchain on first run)"
( cd "$WORK/src" && "$PIO" run -e "$ENV_NAME" )

BIN=$(ls -t "$WORK/src/.pio/build/$ENV_NAME"/firmware*.bin 2>/dev/null | head -1)
[ -n "$BIN" ] || fail "no firmware .bin produced under .pio/build/$ENV_NAME"
mkdir -p dist
OUT="dist/GoatTech-Ender3V3SE-${BOARD}-v${GOATTECH_VERSION}.bin"
cp "$BIN" "$OUT"
echo "Artifact: $OUT"
command -v sha256sum >/dev/null && sha256sum "$OUT"
echo "$SD_NOTE"
echo "Reminder: compilation is not hardware validation. Flash only after board and MCU are physically confirmed."
