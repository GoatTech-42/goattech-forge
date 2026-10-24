#!/usr/bin/env bash
# run-harness.sh - replay the REAL generator emission on host and check the
# emitted G-code trajectory. The compiled forge_diag.cpp is a byte-identical
# copy of the tree file; this script fails if they drift.
set -eu
cd "$(dirname "$0")"
TREE="${1:?usage: $0 <patched-marlin-tree> e.g. the src/<board>/Marlin work dir left by build.sh}"
mkdir -p src/e3v3se
cp "$TREE/src/e3v3se/forge_diag.cpp" src/e3v3se/forge_diag.cpp
cp "$TREE/src/e3v3se/forge_diag.h"   src/e3v3se/forge_diag.h
cmp -s "$TREE/src/e3v3se/forge_diag.cpp" src/e3v3se/forge_diag.cpp
g++ -std=c++17 -O1 -include harness_common.h -I. main.cpp src/e3v3se/forge_diag.cpp -o harness-bin
./harness-bin /tmp/forge-plate
for v in 40 20 80; do echo "== variant nozzle_x100=$v =="; python3 trajectory_check.py /tmp/forge-plate.$v.gcode; done
echo "HARNESS SUITE OK"
