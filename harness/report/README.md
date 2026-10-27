# Forge report host harness

Host build of the real `forge_diag::build_report` (test builds only, `-DFORGE_TEST_BUILD`) against
stubbed printer state, plus a layout render. Run: `bash run-report.sh <patched Marlin dir>`.

Scope: host logic and layout fit only. The render uses a monospace stand-in font and the firmware's
coordinates (x=8, y=40+22*i, 8px cell, 272x480). It is not the panel's font8x16 bitmap, so it proves
fit, not panel appearance. Nothing here is flash, runtime or panel verification.
