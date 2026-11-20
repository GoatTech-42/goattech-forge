# C14 upstream drift notes

Audit date: 2026-11-20. This is a read-only migration assessment, not approval
to change a pin or flash a printer.

## Snapshot and decision

- Forge main inspected: `8ecc56827dd1a905488eae335f2d45fd425c5f3c`.
- Existing C14 pin: `14c5165729684b7b87282f6d25c1239b6569d9e3`.
- Upstream `c14_sd` head inspected: `dbbc8b174c4d0d63544d8cca878f21141a57735e`.
- That head adds 197 reachable commits beyond the pin, with six first-parent
  commits and 713 changed files in the endpoint diff. Counts are this snapshot,
  not a claim about later upstream heads.
- Keep both board pins unchanged. No migration is underway.

In a clean scratch worktree at the inspected upstream head, `git apply --check`
for the unchanged `forge-dwin-input-shaping-menu.patch` failed in
`Marlin/Configuration_adv.h` and `Marlin/src/lcd/dwin/creality/dwin.cpp`.
The chain stopped at that check. No Forge patch was applied to this worktree;
patches 2-6 were not tested for application there. No firmware build was run.

## Semantic blockers

### Shaping menu ownership

Upstream now explicitly undefines its legacy `DWIN_INPUT_SHAPING_MENU` when
`FT_MOTION` is enabled. The legacy menu uses Stepper shaping setters. Forge's
first patch instead provides FT-Motion controls. A future rebase must preserve
that distinction, not merely adjust patch context or enable the legacy menu.
Review busy gates, frequency/damping bounds, EEPROM save behavior, engine-off
warning and interrupted-edit feedback against the actual owning APIs.

Source: [Configuration_adv.h at the inspected head](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE/blob/dbbc8b174c4d0d63544d8cca878f21141a57735e/Marlin/Configuration_adv.h).

### Numeric parser behavior

Upstream replaces `value_float()`'s `strtof` conversion with `dec_to_float()`.
The source documents agreement with `strtof` up to seven significant digits,
possible last-bit differences at eight or nine, and ignored digits after the
ninth while still scaling whole numbers. Forge's current replay/model work
was checked against the older pin. Its numeric fidelity cannot be carried
forward without checking the replacement parser, including raw-F positivity,
positive overflow, underflow, repeated words and packed axis/extrusion words.
Do not interpret a passing old model as proof of the new parser's behavior.

Sources: [parser.h](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE/blob/dbbc8b174c4d0d63544d8cca878f21141a57735e/Marlin/src/gcode/parser.h),
[parser.cpp](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE/blob/dbbc8b174c4d0d63544d8cca878f21141a57735e/Marlin/src/gcode/parser.cpp).

### SD-close guard remains needed

At the inspected head, `Goto_MainMenu()` still calls `card.closefile()` under
`ONE_CLICK_PRINT` without an ongoing/paused-job predicate around that call.
Do not drop Forge patch 2's job guard just because upstream changed neighboring
media or DWIN code. Recheck the actual lifecycle predicates and cleanup path.

Source: [dwin.cpp at the inspected head](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE/blob/dbbc8b174c4d0d63544d8cca878f21141a57735e/Marlin/src/lcd/dwin/creality/dwin.cpp).

## First-parent review map

| Upstream commit | Change area | Future Forge review |
| --- | --- | --- |
| `f37fed5` | Legacy shaping issue #95 | Patch 1's FT-Motion ownership and menu visibility; retain Forge's reviewed behavior. |
| `6889242` | Broad updated C13 integration | Parser, planner and media semantics; all six patches and board-specific content hashes. |
| `822d96f` | Pause/M600, calibration and thumbnail paths | Patches 2 and 6's DWIN context, job-state gates and diagnostics entry behavior. |
| `03b10b1` | Thumbnail memory changes | Adjacent display/menu integration; source checks do not prove screen layout. |
| `b1476f0` | Feature/fix batch, including print-done behavior | SD-close lifecycle model, diagnostics gates and relevant upstream tests. |
| `dbbc8b1` | README only | No direct Forge source change. |

The broad integration is [6889242](https://github.com/navaismo/Marlin_bugfix_2.1_E3V3SE/commit/688924230b38764be911195c4ff9bd7db8d0f1b7).
The table is a review map, not a complete review or a claim that later patches
apply. All identifiers refer to the snapshot above.

## Gates before any future pin proposal

1. Review each patch's owning source and behavior, then rebase the six-patch
   chain in order without weakening its refusal or job-state gates.
2. Review every changed pin and full-content hash explicitly. Matching hashes
   detect consistency with declared bytes; they do not authenticate a change
   to both the bytes and declarations.
3. Revalidate production-parser assumptions and run source, menu-contract,
   planner/replay, golden-trace, scratch-isolation and spaced-path checks on
   both proposed board trees. Golden changes need an explanation, not a blind
   refresh. Keep all eight E-mode orderings and numeric-boundary cases covered.
4. Keep compilation, host simulation and actual printer validation separate.
   This audit ran no firmware build, upstream test suite or hardware test.
   Board/MCU confirmation and on-printer checks remain separate requirements;
   these notes do not authorize flashing or publishing binaries.
