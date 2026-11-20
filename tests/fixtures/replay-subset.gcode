; F1(b) command-subset parity fixture: every command the replay and the model
; accept, motion/state and ignored, in one file. Both must exit 0 and give the
; same blocks. Unsupported commands are tested one per file by the test.
; Motion/state: G0/G1, G90/G91, M82/M83, G21, G28, G92 (E only, or no words),
; M400. Ignored (no motion): G4, M104, M109, M140, M190, M106, M107, M84, M73,
; M105, and M117 free text.
G21
G28
G90
M82
M104 S200
M109 S200
M140 S60
M190 S60
M105
M106 S255
M117 Subset parity: G1 X99 must not be read as a move
M73 P0
G92 E0
G0 X10 Y10 F3000
G1 X30 Y10 E1 F1800
G4 P50
M400
G92
G1 X30 Y30 E2 F1800
G92 E0
G91
G1 X-10 Y0 E0.5 F1800
M83
G1 X0 Y-10 E0.5 F1800
G90
M107
G1 X10 Y10 F3000
M84
