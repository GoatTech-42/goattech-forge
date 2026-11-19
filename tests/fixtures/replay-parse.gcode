; F1(b) parser edge cases the harness and the model must read the same way.
; M117 carries free text, not numeric words.
G28
G90
M82
M117 Hello World!
; 10E2 is X10 followed by E2, never the number 1000.
G1 X10E2 F600
; No space between the command and its first word.
G1X20 Y5 F600
; A move of 1 step is below MIN_STEPS_PER_SEGMENT (4): the planner defers it
; and the next move is measured from the last queued position (4 steps).
G1 X20.0125 F600
G1 X20.05 F600
G1 X30 Y10 F600
