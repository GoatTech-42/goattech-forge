# First-print calibration after flashing

Draft - will be verified on a real printer before release. Steps follow the
upstream port's own install notes, pulled into one walkthrough.

Do these in order after flashing new firmware. Skipping them is the usual
cause of a bad first print, not the firmware itself.

## 1. Auto Z-offset

Run the auto Z-offset routine from the Level menu. The printer probes and
stores the nozzle-to-bed distance.

## 2. Bed level

Run a full auto-level from the same menu. The GoatTech build uses a 6x6 mesh,
so this takes a few minutes longer than stock - that is normal.

## 3. Extruder e-steps

Upstream's Marlin 2.1 builds use 715.12 e-steps; older firmware used about
424.9. Check the value and, if you want to be sure, mark 120 mm of filament,
extrude 100 mm from the menu and measure what actually went through. Adjust
until 100 mm requested gives 100 mm fed.

## 4. PID tune (nozzle and bed)

Control > Temperature > Auto PID. Run it at the temperatures you actually
print at (for example 210 C nozzle / 60 C bed for PLA). This stops the
temperature from bouncing during prints.

## 5. Input shaper

The firmware ships FT_MOTION input shaping, but out of the box only Y is
shaped (3HEI at 42 Hz) - X ships unshaped, so set both axes. The right
frequencies depend on your individual printer: print a ringing or resonance
tower test, read the cleanest frequency per axis, then set them, for example:

    M493 S1        ; enable FT_MOTION
    M493 X C7 A37  ; X axis: 3HEI shaper at 37 Hz
    M493 Y C7 A42  ; Y axis: 3HEI shaper at 42 Hz
    M500           ; save

C picks the shaper type (7 = 3HEI, 0 = off), A is the frequency in Hz - use
your measured values, not the examples. An on-screen menu for this is on the
GoatTech roadmap.

## 6. First test print

Something small and known-good. Watch the first layer; Z-offset is the
thing most likely to need a nudge.
