# Zone A inter-tower exit candidate (source only, not in build)

Status: candidate source patch. Not referenced by build.sh. Not built, not flashed, not run on hardware.

Patch: patches/candidates/forge-v06-zonea-exit.patch. It applies on top of the d2cbf05 patch chain plus the Zone C lift candidate (patches/candidates/forge-v06-zonec-lift.patch). 13 lines added to Marlin/src/e3v3se/forge_diag.cpp.

## What it changes

Zone A towers 0 and 2 start and end their 10x10 loop at the top-left corner (x0, y0+10) instead of (x0, y0). Towers 1 and 3 are unchanged. No z-hop. Retract, speeds, extrusion and thermal paths are unchanged.

Reason: in the baseline, the tower 0 to 1 and tower 2 to 3 travels ran +Y back along the wall just printed, retracted but not lifted. The reconciler flags 350 of 700 Zone A travels at 0.40 (max mid-overlap 9.3mm).

## Simulated result, 0.40 variant (idealised bead model)

- R2 mid-overlap >=3mm: 350 to 0. Max overlap 9.3mm to 0.0.
- R1 strict-cell: 351 to 1. The one flag is the first approach from the prime end (180,5) to (55,65). Its end-point flag under the fixed 0.4mm radius and >1mm exclusion is NOT proven to be no real contact or nozzle clearance.
- Harness: HARNESS SUITE OK, TRAJECTORY OK.
- Extruding moves 3875, extrusion 52820.0mm, G0/G1 moves 7816: all unchanged from base.
- Zone B output unchanged. Total travel 11.24% shorter.

0.20 and 0.80 variants were run by the author only: R2 >=3mm goes to 0 in both. Residual R1 flags (0.20: 80, 0.80: 1) have 0.0mm mid-overlap and are believed to be destination-corner cell artifacts, but that is NOT independently proven. Only the 0.40 result was independently checked.

## Policy qualifier

This is a NEW-VERSION stringing diagnostic, not measurement-equivalent to the old plate. Winding, seam position, departure direction and travel time changed for towers 0 and 2. Do not compare old and new string counts as a retraction-only improvement and do not reuse the baseline. Bind results to the version and generated G-code.

## Not claimed

No hardware print, no scrape fix, no board identity, no clearance proof, no proof that the old plate had a physical defect.
