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
# Accepted subset, the same one harness-real --gcode accepts:
#   motion/state: G0/G1, G90/G91, M82/M83, G21, G28 (position reset to 0,0,0),
#                 G92 E<value> or bare G92 (no-op), M400, M200 S0, M220/M221 S100 only;
#   ignored:      G4, M104, M109, M140, M190, M106, M107, M84, M73, M105 and
#                 M117 (free text).
# A G0/G1 whose last X, Y, Z or E word has no number is refused too.
# Anything else, including G92 with X/Y/Z or any word other than E, is named
# on stderr with its line number and makes the model exit 3 after the totals,
# so a file the model cannot follow is never reported as checked.
import math, re, struct, sys
from decimal import Decimal

def f32(x):  # round to IEEE single, as the firmware's float positions are
    return struct.unpack('<f', struct.pack('<f', x))[0]

# Round-to-nearest-even overflows binary32 at this exact decimal midpoint.
F32_OVERFLOW = Decimal(2**128 - 2**103)
F32_MAX = f32((2 - 2**-23) * 2**127)

SPM = [f32(v) for v in (80.0, 80.0, 400.0, 715.12)]
MAXF = [500.0, 500.0, 20.0, 30.0]
MIN_STEPS = 4   # MIN_STEPS_PER_SEGMENT in harness/config/Configuration_adv.h
NEAR_ZERO = f32(0.000001)   # Marlin's NEAR_ZERO bound (core/macros.h)
STATE = {'G0', 'G1', 'G90', 'G91', 'M82', 'M83', 'G21', 'G28', 'G92', 'M400', 'M200', 'M220', 'M221'}
WORD = re.compile(r'([A-Za-z])\s*([-+]?(?:\d+\.?\d*|\.\d+))?')
IGNORED = {'G4', 'M104', 'M109', 'M140', 'M190', 'M106', 'M107', 'M84', 'M73', 'M105', 'M117'}

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
    moves = dropped = unsupported = 0

    def refuse(lineno, what):
        nonlocal unsupported
        print('unsupported line %d: %s' % (lineno, what), file=sys.stderr)
        unsupported += 1

    for lineno, raw in enumerate(open(path), 1):
        line = raw.split(';', 1)[0].strip()
        if not line:
            continue
        # Command word first, then letter+number words. Numbers have no
        # exponent ("X10E2" is X10 then E2) and need no space between words.
        head = re.match(r'([A-Za-z])(\d+)(?![\d.])', line)
        if not head:   # no command number, or a fractional one such as G1.5
            refuse(lineno, 'malformed command')
            continue
        cmd = head.group(1).upper() + str(int(head.group(2)))
        if cmd not in STATE and cmd not in IGNORED:
            refuse(lineno, cmd)
            continue
        if cmd == 'M117':   # free text, never parsed as words
            continue
        w = {}
        tokens = {}
        novalue = set()   # letters given without a number
        # Every character after the command must be a word (letter, optional
        # number) or whitespace; anything else, such as a "*7" checksum or a
        # stray sign, is refused before any state changes, as the replay does.
        rest, i, bad = line[head.end():], 0, False
        while i < len(rest):
            if rest[i].isspace():
                i += 1
                continue
            m = WORD.match(rest, i)
            if not m:
                bad = True
                break
            # A repeated letter keeps its last occurrence, as Marlin's
            # FASTER_GCODE_PARSER does: G92 E E5 is E5, G92 E5 E has no value.
            w[m.group(1).upper()] = float(m.group(2) or 0.0)
            tokens[m.group(1).upper()] = m.group(2) or '0'
            if m.group(2) is None:
                novalue.add(m.group(1).upper())
            else:
                novalue.discard(m.group(1).upper())
            i = m.end()
        if bad:
            refuse(lineno, 'unreadable word text in %s' % cmd)
            continue
        if cmd in IGNORED:   # no motion
            continue
        if cmd in ('G0', 'G1'):
            # A final X/Y/Z/E/F word with no number ("G1 X", "G1 X10 X"): pinned
            # Marlin's get_destination_from_command() reads axes with
            # parser.seenval(), false for it, so the axis keeps its position.
            # The feed-rate reader keeps its prior value via floatval('F') > 0;
            # floatval calls seenval and defaults to zero for a bare F.
            # Not modelled, so refused as the replay does, before F or any
            # position changes.
            missing = [a for a in 'XYZEF' if a in novalue]
            if missing:
                refuse(lineno, '%s %s without a value' % (cmd, missing[0]))
                continue
            if 'F' in w and w['F'] > 0:
                if Decimal(tokens['F']) >= F32_OVERFLOW:
                    refuse(lineno, '%s F outside finite binary32 (not modelled)' % cmd)
                    continue
                # Binary64 can round a finite decimal up to the overflow
                # midpoint. The exact token check above already ruled it out.
                try:
                    raw_feed = f32(w['F'])
                except OverflowError:
                    raw_feed = F32_MAX
                if not math.isfinite(raw_feed):
                    raw_feed = F32_MAX
                if raw_feed > 0:
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
            # planner.cpp _populate_block(): when no X/Y/Z axis has at least
            # MIN_STEPS_PER_SEGMENT steps (!XYZ_HAS_ENOUGH_STEPS) the block
            # length is the E distance, even if X/Y/Z move a step or three.
            if any(abs(x) >= MIN_STEPS for x in d[:3]):
                mm = math.sqrt(dmm[0] ** 2 + dmm[1] ** 2 + dmm[2] ** 2)
            else:
                mm = dmm[3]
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
        elif cmd == 'M200':
            if set(w) != {'S'} or 'S' in novalue or w['S'] != 0:
                refuse(lineno, 'M200 other than S0')
            # Linear E is this model's baseline. Other M200 modes are refused.
        elif cmd in ('M220', 'M221'):
            if set(w) != {'S'} or 'S' in novalue or w['S'] != 100:
                refuse(lineno, cmd + ' other than S100')
            # 100% speed and flow are this model's baseline.
        elif cmd == 'G28':
            # Simplified homing as in the replay: X/Y/Z to 0, then every axis
            # resynced (sync_plan_position() -> set_position_mm()), so E is
            # re-rounded from its logical position too.
            pos[0] = pos[1] = pos[2] = 0.0
            pos_steps[:3] = [0, 0, 0]
            pos_steps[3] = lround(f32(pos[3] * SPM[3]))
        elif cmd == 'G92':
            # Only E with a value, or no word at all (a no-op). Workspace
            # offsets are on in this config, so G92 X/Y/Z would shift the
            # workspace rather than the position: refused, nothing changed.
            if set(w) - {'E'} or 'E' in novalue:
                refuse(lineno, 'G92 with a word other than E, or E without a value')
            elif 'E' in w:
                # G92.cpp sets E only when it changes by more than NEAR_ZERO,
                # then planner.set_e_position_mm() re-rounds the E baseline
                # alone; the X/Y/Z step baselines are left as they are.
                e = f32(w['E'])
                if abs(f32(e - pos[3])) > NEAR_ZERO:
                    pos[3] = e
                    pos_steps[3] = lround(f32(e * SPM[3]))
        # G21 (already mm) and M400 (no queue here) change nothing in the model
    print('replay moves=%d short_or_zero=%d blocks=%d' % (moves, dropped, blocks))
    print('replay steps=%d,%d,%d,%d' % tuple(tot))
    print('replay path_mm=%.3f' % path_mm)
    if unsupported:
        print('replay unsupported=%d' % unsupported)
        sys.exit(3)

main([a for a in sys.argv[1:] if a != '--totals'][0], '--totals' in sys.argv)
