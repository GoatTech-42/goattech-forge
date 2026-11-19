; F1(b) replay fixture: small hand-written program. Moves are >= 20 ms long at
; their feedrate so the planner's minimum-segment-time slowdown never applies.
; Also covers Marlin's relative-mode rules: G91 makes E relative even after M82,
; and G90 makes E absolute even after M83.
G28
G90
M82
M104 S200
G92 E0
G1 Z0.6 F600
G1 X20 Y20 F3000
G1 X60 Y20 F3000
G1 X60 Y60 E4.5 F1800
G1 X20 Y60 E9 F1800
G1 X20 Y20 E13.5 F1800
G1 E12.5 F1500
G1 Z1.6 F3000
G1 X40.5 Y33.3 F6000
G1 Z0.6 F3000
G1 E13.5 F1500
G91
G1 X0 Y5 E-1 F1500
M83
G1 X10 Y0 E1.2 F1800
G1 X0 Y10 E1.2 F1800
G1 X-10 Y0 E1.2 F1800
G1 X0 Y-10 E1.2 F1800
G1 Z2 F3000
G90
G1 E10 F1500
G1 X100 Y100 F9000
G4 P100
M107
