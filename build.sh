#!/usr/bin/env bash
# GoatTech firmware build for the Ender-3 V3 SE.
#
# Overlay model: this repo vendors no Marlin source. The script clones the
# pinned upstream navaismo Marlin 2.1 port, applies the minimal GoatTech
# branding diff plus the pinned Forge patch set (currently: the DWIN
# FT-Motion input-shaping menu), and builds exactly one binary for exactly
# one board.
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
GOATTECH_VERSION="0.2.0"

# Forge patch set, pinned by full-content hash. Never bypassed: a patch file
# whose bytes differ from this hash stops the build.
FORGE_PATCH="patches/forge-dwin-input-shaping-menu.patch"
EXPECTED_PATCH_SHA256="7e73818d9119f87655feaf5532c83770e2bece20f505396ff42eb3f1a1b0c576"
# Full-content hashes of every file the patch touches, after applying the
# pinned patch to the pinned upstream source. Identical for both boards
# (the patched files are byte-identical across the two pins).
EXPECTED_ADV_SHA256="399bd715649bb8015d5ae36e7fe8c83a8a68dd98a431c577457fadac705a90a4"
EXPECTED_DWINCPP_SHA256="9e344693dfd1897f6e36c2c96b01260ed7f8bba4317d9233b1eba1014d12c110"
EXPECTED_DWINH_SHA256="8b8bc96b843237a3c18830552b4fb5cd896c869dfe5b8feb5cae1efa86ddadad"
EXPECTED_LANGEN_SHA256="e3c389755f03beceb4edc995ea071c32c022ddfb47681d2c2252c2102cb7be25"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ $# -eq 1 ] || fail "Usage: $0 c13|c14"
case "$1" in
  c13)
    BOARD=c13; BRANCH="$C13_BRANCH"; COMMIT="$C13_COMMIT"; ENV_NAME="$C13_ENV"
    EXPECTED_CFG_SHA256="0e9b3e29366ae4818d76afda4739b7417cf35c8c3d710c32d2ebcfc162cac2ec"
    SD_NOTE="C13 (GD32F303RET6): copy the .bin onto the SD card root. Use a unique name per flash attempt if the bootloader ignores a repeated one."
    ;;
  c14)
    BOARD=c14; BRANCH="$C14_BRANCH"; COMMIT="$C14_COMMIT"; ENV_NAME="$C14_ENV"
    EXPECTED_CFG_SHA256="0983a1f50ac5af1a8404622b78d91efcb936d00918b87a38cd2d8460a021e1c2"
    SD_NOTE="C14 (STM32F401RET6): place the .bin inside a folder named STM32F4_UPDATE on the SD card."
    ;;
  *) fail "Unknown board '$1'. Expected c13 or c14." ;;
esac

command -v git >/dev/null || fail "git not found"
command -v pio >/dev/null || command -v platformio >/dev/null || fail "PlatformIO not found (pip install platformio)"
PIO=$(command -v pio || command -v platformio)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/$FORGE_PATCH"

cat <<BANNER
GoatTech build for Ender-3 V3 SE, board target: $BOARD
Confirm before flashing anything:
  - mainboard silkscreen label matches this target (CR4NS200320C13 or CR4NS200320C14)
  - MCU part number matches (C13: GD32F303RET6, C14: STM32F401RET6)
  - a label alone is not proof; at least one C14-labelled unit shipped with a GD chip
BANNER

WORK=".build/$BOARD"
SRC="$WORK/src"
CFG="$SRC/Marlin/Configuration.h"

AUTHOR_OLD='#define STRING_CONFIG_H_AUTHOR "Marlin, Creality, Kraplax & Navaismo" // Original author or contributor.'
AUTHOR_NEW='#define STRING_CONFIG_H_AUTHOR "GoatTech build of Marlin by Creality, Kraplax \& Navaismo" // Original author or contributor.'
NAME_OLD='#define CUSTOM_MACHINE_NAME "Ender-3 V3 SE"'
NAME_NEW='#define CUSTOM_MACHINE_NAME "GoatTech Ender-3 V3 SE"'

# sha256 of a file under the staged source tree
tree_sha256() { sha256sum "$SRC/$1" | cut -d' ' -f1; }

# Verify every file the build depends on beyond the pin itself: branding
# target plus all four files the Forge patch rewrites, each by full-content
# hash. Deterministic because pin + patch bytes are both pinned.
verify_worktree_files() {
  [ "$(tree_sha256 Marlin/Configuration.h)" = "$EXPECTED_CFG_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/Configuration_adv.h)" = "$EXPECTED_ADV_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/dwin/creality/dwin.cpp)" = "$EXPECTED_DWINCPP_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/dwin/creality/dwin.h)" = "$EXPECTED_DWINH_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/language/language_en.h)" = "$EXPECTED_LANGEN_SHA256" ] || return 1
}

EXPECTED_PORCELAIN=" M Marlin/Configuration.h
 M Marlin/Configuration_adv.h
 M Marlin/src/lcd/dwin/creality/dwin.cpp
 M Marlin/src/lcd/dwin/creality/dwin.h
 M Marlin/src/lcd/language/language_en.h"

# Reuse a staged tree only when the pin holds AND the worktree is exactly
# "pinned source + branding patch + pinned Forge patch", proven three ways:
#   1. git status --porcelain is exactly the five expected modified files
#      (no other modified, staged or untracked entries);
#   2. each of the five files matches its full-content sha256;
#   3. no ignored entries outside .pio/ (upstream .gitignore can hide named
#      source/build inputs; only the PlatformIO output dir and reproducible
#      Python __pycache__ bytecode caches are exempt).
READY=0
if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$COMMIT" ]; then
  PORCELAIN=$(git -C "$SRC" status --porcelain)
  IGNORED_NONPIO=$(git -C "$SRC" status --porcelain --ignored | grep '^!!' | grep -v '^!! \.pio/' | grep -v '__pycache__/$' || true)
  if [ "$PORCELAIN" = "$EXPECTED_PORCELAIN" ] && [ -z "$IGNORED_NONPIO" ] && verify_worktree_files; then
    echo "Reusing staged upstream tree at $COMMIT (worktree verified: exact pinned source + branding + pinned Forge patch)"
    READY=1
  else
    echo "Staged tree differs from the pinned source beyond the known diffs; re-staging clean"
    rm -rf "$WORK"
  fi
fi
if [ ! -d "$SRC" ]; then
  mkdir -p "$WORK"
  echo "Cloning upstream $BRANCH @ $COMMIT"
  git clone --quiet "$UPSTREAM_URL" "$SRC"
  git -C "$SRC" checkout --quiet "$COMMIT"
  [ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || fail "pinned commit checkout mismatch"
fi

if [ "$READY" -eq 0 ]; then
  # Branding diff (Configuration.h only).
  grep -qF "$AUTHOR_OLD" "$CFG" || fail "upstream author line changed; re-verify Configuration.h before branding"
  grep -qF "$NAME_OLD" "$CFG" || fail "upstream machine-name line changed; re-verify Configuration.h before branding"
  sed -i "s|$AUTHOR_OLD|$AUTHOR_NEW|" "$CFG"
  sed -i "s|$NAME_OLD|$NAME_NEW|" "$CFG"
  grep -qF 'GoatTech build of Marlin' "$CFG" || fail "branding did not apply (author)"
  grep -qF 'GoatTech Ender-3 V3 SE' "$CFG" || fail "branding did not apply (machine name)"

  # Forge patch set: pinned by full-content hash, no bypass path.
  [ -f "$PATCH_FILE" ] || fail "Forge patch missing: $PATCH_FILE"
  ACTUAL_PATCH_SHA256=$(sha256sum "$PATCH_FILE" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH_SHA256" = "$EXPECTED_PATCH_SHA256" ] \
    || fail "Forge patch content mismatch (got $ACTUAL_PATCH_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE" || fail "Forge patch does not apply cleanly to the pinned source"
  git -C "$SRC" apply "$PATCH_FILE"
  echo "Applied Forge patch $FORGE_PATCH (sha256 $EXPECTED_PATCH_SHA256)"

  verify_worktree_files || fail "post-patch worktree content mismatch; refusing to build an unverified tree"
fi

echo "Building env $ENV_NAME (this downloads the toolchain on first run)"
( cd "$SRC" && "$PIO" run -e "$ENV_NAME" )

BIN=$(ls -t "$SRC/.pio/build/$ENV_NAME"/firmware*.bin 2>/dev/null | head -1)
[ -n "$BIN" ] || fail "no firmware .bin produced under .pio/build/$ENV_NAME"
mkdir -p dist
OUT="dist/GoatTech-Ender3V3SE-${BOARD}-v${GOATTECH_VERSION}.bin"
cp "$BIN" "$OUT"
echo "Artifact: $OUT"
command -v sha256sum >/dev/null && sha256sum "$OUT"
echo "$SD_NOTE"
echo "Reminder: compilation is not hardware validation. Flash only after board and MCU are physically confirmed."
