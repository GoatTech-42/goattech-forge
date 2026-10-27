# Forge report host harness

Host build of the real `forge_diag::build_report` with stubbed printer state.
Run `bash run-report.sh <absolute patched Marlin directory>`.

The configured panel is 240x320. The report uses font ID 0x01 (vendor table:
8x16), 29 visible characters, x=4, y=34+17*i, up to 16 lines. Cell bounds end
at x=236 and y=305. These are source-command geometry bounds, not glyph pixels.
The panel font bank is not included here. No stand-in render is invoked.

The harness checks report values and no SD write/remove/rename. Compilation,
host logic and geometry do not establish panel appearance or printer clearance.
