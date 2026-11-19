#!/usr/bin/env python3
# replay_reference.py <gcode> - independent expectation for harness-real --gcode
# --blocks. Re-derives per-block step counts, block length and nominal speed
# from the G-code and the Ender 3 V3 SE host config numbers, without using any
# Marlin code, in the same line format harness-real prints. Only linear moves
# are modelled (the same subset the replay accepts).
# --totals prints only the summary lines (for files with segments shorter than
# the minimum segment time, where the per-block speeds are not modelled).
# Speed model: nominal = feedrate, reduced so no axis exceeds its max feedrate
# (valid while every segment lasts >= the 20 ms minimum segment time).
import math, re, struct, sys

def f32(x):  # round to IEEE single, as the firmware's float positions are
    return struct.unpack('<f', struct.pack('<f', x))[0]

SPM = [f32(v) for v in (80.0, 80.0, 400.0, 715.12)]
MAXF = [500.0, 500.0, 20.0, 30.0]
MIN_STEPS = 4   # MIN_STEPS_PER_SEGMENT in harness/config/Configuration_adv.h

def lround(x):  # round half away from zero, like Marlin's LROUND
    return int(math.copysign(math.floor(abs(x) + 0.5), x))

def main(path, totals_only=False):
    pos = [0.0] * 4
    pos_steps = [0] * 4
    # Marlin's relative-mode state: G90/G91 replace it wholesale (clearing any
    # M82/M83 choice, so G91 makes E relative); M82/M83 override E after that.
    relxyz = rele = False
    emode = 0   # 0 follow G90/G91, 1 M82, 2 M83
    feed = 25.0
    blocks = 0
    tot = [0, 0, 0, 0]
    path_mm = 0.0
    moves = dropped = 0
    for raw in open(path):
        line = raw.split(';', 1)[0].strip()
        if not line:
            continue
        # Command word first, then letter+number words. Numbers have no
        # exponent ("X10E2" is X10 then E2) and need no space between words.
        head = re.match(r'([A-Za-z])(\d+)', line)
        cmd = (head.group(1) + head.group(2)).upper()
        if cmd == 'M117':   # free text, ignored like the replay does
            continue
        w = {}
        for m in re.finditer(r'([A-Za-z])\s*([-+]?(?:\d+\.?\d*|\.\d+))?', line[head.end():]):
            w[m.group(1).upper()] = float(m.group(2) or 0.0)
        if cmd in ('G0', 'G1'):
            if 'F' in w:
                feed = f32(w['F'] / 60.0)
            t = list(pos)
            for i, a in enumerate('XYZE'):
                if a in w:
                    rel = relxyz if a != 'E' else (emode == 2 or (emode == 0 and rele))
                    t[i] = f32(pos[i] + f32(w[a])) if rel else f32(w[a])
            moves += 1
            tsteps = [lround(f32(t[i] * SPM[i])) for i in range(4)]
            d = [tsteps[i] - pos_steps[i] for i in range(4)]
            pos = t
            # The planner drops a segment with fewer than MIN_STEPS_PER_SEGMENT
            # step events and keeps its old step baseline for the next move.
            if max(abs(x) for x in d) < MIN_STEPS:
                dropped += 1
                continue
            pos_steps = tsteps
            dmm = [abs(d[i]) / SPM[i] for i in range(4)]
            xyz = math.sqrt(dmm[0] ** 2 + dmm[1] ** 2 + dmm[2] ** 2)
            mm = xyz if any(d[:3]) else dmm[3]
            nominal = feed
            for i in range(4):
                if dmm[i] > 0:
                    nominal = min(nominal, MAXF[i] * mm / dmm[i])
            if not totals_only: print('rblock %d steps=%d,%d,%d,%d mm=%.3f nominal_speed=%.2f' %
                  (blocks, abs(d[0]), abs(d[1]), abs(d[2]), abs(d[3]), mm, nominal))
            for i in range(4):
                tot[i] += abs(d[i])
            path_mm += mm
            blocks += 1
        elif cmd == 'G90': relxyz = rele = False; emode = 0
        elif cmd == 'G91': relxyz = rele = True; emode = 0
        elif cmd == 'M82': emode = 1
        elif cmd == 'M83': emode = 2
        elif cmd == 'G28': pos[0] = pos[1] = pos[2] = 0.0; pos_steps[:3] = [0, 0, 0]
        elif cmd == 'G92':
            for i, a in enumerate('XYZE'):
                if a in w:
                    pos[i] = f32(w[a]); pos_steps[i] = lround(f32(pos[i] * SPM[i]))
    print('replay moves=%d short_or_zero=%d blocks=%d' % (moves, dropped, blocks))
    print('replay steps=%d,%d,%d,%d' % tuple(tot))
    print('replay path_mm=%.3f' % path_mm)

main([a for a in sys.argv[1:] if a != '--totals'][0], '--totals' in sys.argv)
