# Zone C lift candidate (NOT part of any build)

`patches/candidates/forge-v06-zonec-lift.patch` is an isolated candidate. `build.sh` does not
reference it. It applies on top of the pinned patch chain at d2cbf05 (the chain through
`forge-v06-report-240.patch`).

What it changes: in the Zone C speed ladder, before each return travel it retracts, lifts
0.6 mm, travels, descends and de-retracts. The first ladder line skips the lift.

Evidence (simulation only, idealised bead model, 0.40 nozzle variant):
- Baseline: 8 of 10 Zone C non-extruding travels run at the top of the line just printed.
  Candidate: 0. Harness suite OK on both.
- `harness/forge-travel-reconcile.py` reports per-travel results. Zone A has 351 flagged
  travels in the baseline and is not addressed here. Zone B has no real crossings.

Not evidence of anything on a printer. It is not a bed-scrape fix. Status: held for policy review.
Not built, not flashed.
