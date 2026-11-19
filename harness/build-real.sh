#!/usr/bin/env bash
# build-real.sh <marlin-tree> - syntax-check (and compile) Marlin's real
# planner.cpp and temperature.cpp against the host config in harness/config.
# Work on a scratch copy so the tree is never modified.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="${1:?usage: $0 <marlin-tree>}"
ZIG="${ZIG:-zig}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
cp -r "$TREE/Marlin" "$W/Marlin"
cp "$HERE"/config/Configuration.h "$HERE"/config/Configuration_adv.h "$W/Marlin/"
cd "$W"
for m in planner temperature; do
  $ZIG c++ -std=gnu++17 -c -w -D__PLAT_LINUX__ -DHAL_PATH=src/HAL -IMarlin -IMarlin/src \
    -IMarlin/src/HAL/LINUX/include Marlin/src/module/$m.cpp -o "$HERE/$m.o.tmp" && echo "compiled $m"
  rm -f "$HERE/$m.o.tmp"
done
