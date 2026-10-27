#!/usr/bin/env bash
# GoatTech firmware build for the Ender-3 V3 SE.
#
# Overlay model: this repo vendors no Marlin source. The script clones the
# pinned upstream navaismo Marlin 2.1 port, applies the minimal GoatTech
# branding diff plus the pinned Forge patch set (DWIN FT-Motion shaping menu,
# #74 SD-close guard, diagnostics start guard, config restore, diagnostics
# plate generator, diagnostics menu / review screen), and builds exactly one
# binary for exactly one board.
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
GOATTECH_VERSION="0.6.0"

# Forge patch set, pinned by full-content hash. Never bypassed: a patch file
# whose bytes differ from this hash stops the build.
FORGE_PATCH="patches/forge-dwin-input-shaping-menu.patch"
EXPECTED_PATCH_SHA256="7e73818d9119f87655feaf5532c83770e2bece20f505396ff42eb3f1a1b0c576"
# Patch 2: issue #74 SD-close guard (applied after the menu patch, same strict pin)
FORGE_PATCH2="patches/forge-74-sdclose-guard.patch"
EXPECTED_PATCH2_SHA256="99e96511b52520bce35d9ed6d72d54cc8918902cdfa5a67140c02a49d031801f"
# Patch 3: Forge diagnostics start guard (applied after the #74 patch, same strict pin)
FORGE_PATCH3="patches/forge-diag-startguard.patch"
EXPECTED_PATCH3_SHA256="c653f40c1a28459014e0802b5e6df3efbd2555d79cccc5058d59f10fe80cb34b"
# Patch 4: config restore to the krasnaya_4 baseline (S_CURVE_ACCELERATION + LIN_ADVANCE)
FORGE_PATCH4="patches/forge-config-restore.patch"
EXPECTED_PATCH4_SHA256="47c5fe85488ae6a3ca13746645ee47a239d600adac90096b48d75e04217d31d4"
# Patch 5: Forge diagnostics phase-1 plate generator (applied after the config restore, same strict pin)
FORGE_PATCH5="patches/forge-diag-generator.patch"
EXPECTED_PATCH5_SHA256="ba9aa8ab05f4b1960807f3053091026a10d41b6348191e235bfc1f4ab303d7a7"
# Patch 6: Forge diagnostics menu / review screen (applied after the generator, same strict pin)
FORGE_PATCH6="patches/forge-diag-menu.patch"
EXPECTED_PATCH6_SHA256="7f600ef66bbcba88caec74f282146a4418e62660fd91dfdf5af320c38068cada"
# Patch 7: Forge version label + read-only "Run diagnostics" report (the report is compiled in only with the "test" build flag)
FORGE_PATCH7="patches/forge-v06-diag-report.patch"
EXPECTED_PATCH7_SHA256="6226094e8e006b97ed662508c8d31a015f65fff4187c2d3e54243d75d8322eb0"
# Patch 8: generator prime height (descend before the prime line) + M107 in the end block. Behavior change to generated
# G-code only; NOT a bed-scrape fix and not clearance proof.
FORGE_PATCH8="patches/forge-v06-prime-m107.patch"
EXPECTED_PATCH8_SHA256="6d80ad05843aef3bb798e07b8821208ec37439f2084096bdc20d54a77c7cfca1"
# Patch 9: fit the test-only report to the configured 240x320 panel.
FORGE_PATCH9="patches/forge-v06-report-240.patch"
EXPECTED_PATCH9_SHA256="45e2f527ff63bab8144efdfa2838aaf67ec2092ef07b1736b8c33b3482a4b516"
# Full-content hashes of every file the patches touch, after applying the
# full pinned patch chain to the pinned upstream source. Identical for both boards
# (the patched files are byte-identical across the two pins).
EXPECTED_ADV_SHA256="f7d60f5273e82b28c6ed34af506fb11faef0df0cea1cc3984084606fb1dbed60"
EXPECTED_CARDREADER_SHA256="bc0e59731cf3a991001ce7caf3a562f2b413ec9c84d1166362faede2a5f0fa91"
EXPECTED_FORGEDIAGH_SHA256="02c690725ecf8769c849b3e643efc894c71718a698bf39578b89e694de4fd9de"
EXPECTED_FORGEDIAGCPP_SHA256="8c4c9557df0f71a073cfdb395b80d9bcee52157d85cf104a4654980d624bf3ea"
EXPECTED_DWINCPP_SHA256="8e0a4235493145dc4fbe1acf794b44f62363f0b2f3e7bfeb5ce96b67170ad426"
EXPECTED_DWINH_SHA256="58141564db25946d6ab55fe0df923054aed3d91e9a2222429cc921a4c5af87fb"
EXPECTED_DWINFONT_SHA256="e3b05e148b33b2877589c540ae764f347c74b5aa87fddb7723bb8ca3a55856d9"
EXPECTED_LANGEN_SHA256="e3c389755f03beceb4edc995ea071c32c022ddfb47681d2c2252c2102cb7be25"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ $# -ge 1 ] && [ $# -le 2 ] || fail "Usage: $0 c13|c14 [test]"
# "test" compiles the read-only Run diagnostics report into the Forge Diagnostics menu
# (-DFORGE_TEST_BUILD). Release builds (no second argument) do not contain it.
VARIANT=release
if [ $# -eq 2 ]; then
  [ "$2" = "test" ] || fail "Unknown variant '$2'. Expected: test"
  VARIANT=test
  export PLATFORMIO_BUILD_FLAGS="-DFORGE_TEST_BUILD"
else
  unset PLATFORMIO_BUILD_FLAGS
fi
case "$1" in
  c13)
    BOARD=c13; BRANCH="$C13_BRANCH"; COMMIT="$C13_COMMIT"; ENV_NAME="$C13_ENV"
    EXPECTED_CFG_SHA256="53e4411f7110ce2b121c6fa10f8fc794ab264b26582f50bf2221efb940b1eed4"
    SD_NOTE="C13 (GD32F303RET6): copy the .bin onto the SD card root. Use a unique name per flash attempt if the bootloader ignores a repeated one."
    ;;
  c14)
    BOARD=c14; BRANCH="$C14_BRANCH"; COMMIT="$C14_COMMIT"; ENV_NAME="$C14_ENV"
    EXPECTED_CFG_SHA256="76411607e83dbbf6c4d38e5bf63c3f5c272dd562b11d9ac1fe6dfee50d285853"
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
# target plus every file the Forge patch chain rewrites, each by full-content
# hash. Deterministic because pin + patch bytes are both pinned.
verify_worktree_files() {
  [ "$(tree_sha256 Marlin/src/lcd/dwin/common/dwin_font.h)" = "$EXPECTED_DWINFONT_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/Configuration.h)" = "$EXPECTED_CFG_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/Configuration_adv.h)" = "$EXPECTED_ADV_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/dwin/creality/dwin.cpp)" = "$EXPECTED_DWINCPP_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/dwin/creality/dwin.h)" = "$EXPECTED_DWINH_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/lcd/language/language_en.h)" = "$EXPECTED_LANGEN_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/sd/cardreader.cpp)" = "$EXPECTED_CARDREADER_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/e3v3se/forge_diag.h)" = "$EXPECTED_FORGEDIAGH_SHA256" ] || return 1
  [ "$(tree_sha256 Marlin/src/e3v3se/forge_diag.cpp)" = "$EXPECTED_FORGEDIAGCPP_SHA256" ] || return 1
}

EXPECTED_PORCELAIN=" M Marlin/Configuration.h
 M Marlin/Configuration_adv.h
 M Marlin/src/lcd/dwin/creality/dwin.cpp
 M Marlin/src/lcd/dwin/creality/dwin.h
 M Marlin/src/lcd/language/language_en.h
 M Marlin/src/sd/cardreader.cpp
?? Marlin/src/e3v3se/forge_diag.cpp
?? Marlin/src/e3v3se/forge_diag.h"

# Reuse a staged tree only when the pin holds AND the worktree is exactly
# "pinned source + branding patch + pinned Forge patch", proven three ways:
#   1. git status --porcelain is exactly the six expected modified files plus
#      the two untracked Forge diagnostics sources
#      (no other modified, staged or untracked entries);
#   2. each of the eight files matches its full-content sha256;
#   3. no ignored entries outside .pio/ (upstream .gitignore can hide named
#      source/build inputs; only the PlatformIO output dir and reproducible
#      Python __pycache__ bytecode caches are exempt).
READY=0
if [ -d "$SRC/.git" ] && [ "$(git -C "$SRC" rev-parse HEAD 2>/dev/null)" = "$COMMIT" ]; then
  PORCELAIN=$(git -C "$SRC" status --porcelain)
  IGNORED_NONPIO=$(git -C "$SRC" status --porcelain --ignored | grep '^!!' | grep -v '^!! \.pio/' | grep -v '__pycache__/$' || true)
  if [ "$PORCELAIN" = "$EXPECTED_PORCELAIN" ] && [ -z "$IGNORED_NONPIO" ] && verify_worktree_files; then
    echo "Reusing staged upstream tree at $COMMIT (worktree verified: exact pinned source + branding + pinned Forge patch chain)"
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
  PATCH_FILE2="$SCRIPT_DIR/$FORGE_PATCH2"
  [ -f "$PATCH_FILE2" ] || fail "Forge patch 2 missing: $PATCH_FILE2"
  ACTUAL_PATCH2_SHA256=$(sha256sum "$PATCH_FILE2" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH2_SHA256" = "$EXPECTED_PATCH2_SHA256" ] \
    || fail "Forge patch 2 content mismatch (got $ACTUAL_PATCH2_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE2" || fail "Forge patch 2 does not apply cleanly on top of the menu patch"
  git -C "$SRC" apply "$PATCH_FILE2"
  echo "Applied Forge patch $FORGE_PATCH2 (sha256 $EXPECTED_PATCH2_SHA256)"
  PATCH_FILE3="$SCRIPT_DIR/$FORGE_PATCH3"
  [ -f "$PATCH_FILE3" ] || fail "Forge patch 3 missing: $PATCH_FILE3"
  ACTUAL_PATCH3_SHA256=$(sha256sum "$PATCH_FILE3" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH3_SHA256" = "$EXPECTED_PATCH3_SHA256" ] \
    || fail "Forge patch 3 content mismatch (got $ACTUAL_PATCH3_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE3" || fail "Forge patch 3 does not apply cleanly on top of the #74 patch"
  git -C "$SRC" apply "$PATCH_FILE3"
  echo "Applied Forge patch $FORGE_PATCH3 (sha256 $EXPECTED_PATCH3_SHA256)"
  PATCH_FILE4="$SCRIPT_DIR/$FORGE_PATCH4"
  [ -f "$PATCH_FILE4" ] || fail "Forge patch 4 missing: $PATCH_FILE4"
  ACTUAL_PATCH4_SHA256=$(sha256sum "$PATCH_FILE4" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH4_SHA256" = "$EXPECTED_PATCH4_SHA256" ] \
    || fail "Forge patch 4 content mismatch (got $ACTUAL_PATCH4_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE4" || fail "Forge patch 4 does not apply cleanly on top of the start-guard patch"
  git -C "$SRC" apply "$PATCH_FILE4"
  echo "Applied Forge patch $FORGE_PATCH4 (sha256 $EXPECTED_PATCH4_SHA256)"
  PATCH_FILE5="$SCRIPT_DIR/$FORGE_PATCH5"
  [ -f "$PATCH_FILE5" ] || fail "Forge patch 5 missing: $PATCH_FILE5"
  ACTUAL_PATCH5_SHA256=$(sha256sum "$PATCH_FILE5" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH5_SHA256" = "$EXPECTED_PATCH5_SHA256" ] \
    || fail "Forge patch 5 content mismatch (got $ACTUAL_PATCH5_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE5" || fail "Forge patch 5 does not apply cleanly on top of the config-restore patch"
  git -C "$SRC" apply "$PATCH_FILE5"
  echo "Applied Forge patch $FORGE_PATCH5 (sha256 $EXPECTED_PATCH5_SHA256)"
  PATCH_FILE6="$SCRIPT_DIR/$FORGE_PATCH6"
  [ -f "$PATCH_FILE6" ] || fail "Forge patch 6 missing: $PATCH_FILE6"
  ACTUAL_PATCH6_SHA256=$(sha256sum "$PATCH_FILE6" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH6_SHA256" = "$EXPECTED_PATCH6_SHA256" ] \
    || fail "Forge patch 6 content mismatch (got $ACTUAL_PATCH6_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE6" || fail "Forge patch 6 does not apply cleanly on top of the generator patch"
  git -C "$SRC" apply "$PATCH_FILE6"
  echo "Applied Forge patch $FORGE_PATCH6 (sha256 $EXPECTED_PATCH6_SHA256)"

  PATCH_FILE7="$SCRIPT_DIR/$FORGE_PATCH7"
  [ -f "$PATCH_FILE7" ] || fail "Forge patch 7 missing: $PATCH_FILE7"
  ACTUAL_PATCH7_SHA256=$(sha256sum "$PATCH_FILE7" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH7_SHA256" = "$EXPECTED_PATCH7_SHA256" ] \
    || fail "Forge patch 7 content mismatch (got $ACTUAL_PATCH7_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE7" || fail "Forge patch 7 does not apply cleanly on top of the diagnostics menu patch"
  git -C "$SRC" apply "$PATCH_FILE7"
  echo "Applied Forge patch $FORGE_PATCH7 (sha256 $EXPECTED_PATCH7_SHA256)"
  PATCH_FILE8="$SCRIPT_DIR/$FORGE_PATCH8"
  [ -f "$PATCH_FILE8" ] || fail "Forge patch 8 missing: $PATCH_FILE8"
  ACTUAL_PATCH8_SHA256=$(sha256sum "$PATCH_FILE8" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH8_SHA256" = "$EXPECTED_PATCH8_SHA256" ] \
    || fail "Forge patch 8 content mismatch (got $ACTUAL_PATCH8_SHA256); refusing to apply an unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE8" || fail "Forge patch 8 does not apply cleanly on top of patch 7"
  git -C "$SRC" apply "$PATCH_FILE8"
  echo "Applied Forge patch $FORGE_PATCH8 (sha256 $EXPECTED_PATCH8_SHA256)"

  PATCH_FILE9="$SCRIPT_DIR/$FORGE_PATCH9"
  [ -f "$PATCH_FILE9" ] || fail "Forge patch 9 missing: $PATCH_FILE9"
  ACTUAL_PATCH9_SHA256=$(sha256sum "$PATCH_FILE9" | cut -d' ' -f1)
  [ "$ACTUAL_PATCH9_SHA256" = "$EXPECTED_PATCH9_SHA256" ] \
    || fail "Forge patch 9 content mismatch; refusing unverified patch"
  git -C "$SRC" apply --check "$PATCH_FILE9" || fail "Forge patch 9 does not apply cleanly"
  git -C "$SRC" apply "$PATCH_FILE9"

  verify_worktree_files || fail "post-patch worktree content mismatch; refusing to build an unverified tree"
fi

echo "Variant: $VARIANT"
echo "Building env $ENV_NAME (this downloads the toolchain on first run)"
( cd "$SRC" && "$PIO" run -e "$ENV_NAME" )

BIN=$(ls -t "$SRC/.pio/build/$ENV_NAME"/firmware*.bin 2>/dev/null | head -1)
[ -n "$BIN" ] || fail "no firmware .bin produced under .pio/build/$ENV_NAME"
mkdir -p dist
SUFFIX=""
[ "$VARIANT" = "test" ] && SUFFIX="-test"
OUT="dist/GoatTech-Ender3V3SE-${BOARD}-v${GOATTECH_VERSION}${SUFFIX}.bin"
cp "$BIN" "$OUT"
echo "Artifact: $OUT"
command -v sha256sum >/dev/null && sha256sum "$OUT"
echo "$SD_NOTE"
echo "Reminder: compilation is not hardware validation. Flash only after board and MCU are physically confirmed."
