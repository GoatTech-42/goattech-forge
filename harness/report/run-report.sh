#!/usr/bin/env bash
# usage: run-report.sh <patched-marlin-tree>  (the Marlin/ dir left by build.sh, e.g. .build/c13/src/Marlin)
# Builds the host report harness from the REAL tree file (FORGE_TEST_BUILD on) and renders layout PNGs.
set -eu
cd "$(dirname "$0")"
TREE="${1:?usage: $0 <patched-marlin-tree>}"
rm -rf src report-bin
mkdir -p src/e3v3se src/sd src/module src/lcd src/inc
cp ../src/sd/cardreader.h src/sd/
cp ../src/MarlinCore.h src/
cp ../src/lcd/marlinui.h src/lcd/
cp stub_planner.h src/module/planner.h
cp stub_temperature.h src/module/temperature.h
cp stub_probe.h src/module/probe.h
echo '// stub: SHORT_BUILD_VERSION comes from common.h' > src/inc/Version.h
cp "$TREE/src/e3v3se/forge_diag.cpp" src/e3v3se/forge_diag.cpp
cp "$TREE/src/e3v3se/forge_diag.h" src/e3v3se/forge_diag.h
cmp -s "$TREE/src/e3v3se/forge_diag.cpp" src/e3v3se/forge_diag.cpp
g++ -std=c++17 -O1 -DFORGE_TEST_BUILD -include common.h -I. report_main.cpp src/e3v3se/forge_diag.cpp -o report-bin
./report-bin
python3 render_report.py /tmp/forge-report
