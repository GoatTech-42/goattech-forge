#!/usr/bin/env bash
# build-real.sh <marlin-tree> [out-dir] - compile Marlin's REAL planner.cpp
# and temperature.cpp against the host config in harness/config, then link
# them with harness/real/{main,stubs}.cpp into <out-dir>/harness-real.
# <marlin-tree> is the directory holding Marlin/ (the patched pinned tree).
# Works on a scratch copy so the tree is never modified. Host build only.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="${1:?usage: $0 <marlin-tree> [out-dir]}"
OUT="${2:-$HERE/build-real}"
CXX="${CXX:-c++}"
[ -f "$TREE/Marlin/src/module/planner.cpp" ] || { echo "no Marlin/src/module/planner.cpp under $TREE" >&2; exit 1; }
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cp -r "$TREE/Marlin" "$W/Marlin"
cp "$HERE"/config/Configuration.h "$HERE"/config/Configuration_adv.h "$W/Marlin/"
cd "$W"
FLAGS="-std=gnu++17 -O1 -w -D__PLAT_LINUX__ -DHAL_PATH=src/HAL -IMarlin -IMarlin/src -IMarlin/src/HAL/LINUX/include -I$HERE/real"
pids=""
for src in Marlin/src/module/planner.cpp Marlin/src/module/temperature.cpp "$HERE/real/stubs.cpp" "$HERE/real/main.cpp"; do
  o="$W/$(basename "$src" .cpp).o"
  ( $CXX $FLAGS -c "$src" -o "$o" && echo "compiled $(basename "$src")" ) & pids="$pids $!"
done
rc=0; for p in $pids; do wait "$p" || rc=1; done
[ "$rc" = 0 ] || { echo "compile failed" >&2; exit 1; }
$CXX "$W"/main.o "$W"/stubs.o "$W"/planner.o "$W"/temperature.o -o "$OUT/harness-real" -lm
echo "linked $OUT/harness-real"
