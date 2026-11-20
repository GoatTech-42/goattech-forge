#!/usr/bin/env python3
# trace_summary.py <gcode> - golden-trace fingerprint of an emitted plate file:
# sha256 of the bytes plus counts derived by a plain parse (no motion model).
# Used by tests/test-trajectory-golden.sh. Host-side text analysis only.
import hashlib, re, sys

data = open(sys.argv[1], 'rb').read()
text = data.decode('ascii', 'replace')
moves = 0
xs, ys, zs = [], [], []
e_pos_max = 0.0
for raw in text.split('\n'):
    line = raw.split(';', 1)[0].strip()
    if not line:
        continue
    w = line.split()
    if w[0].upper() not in ('G0', 'G1'):
        continue
    moves += 1
    for p in w[1:]:
        m = re.match(r'^([XYZE])(-?[0-9.]+)$', p, re.I)
        if not m:
            continue
        v = float(m.group(2))
        a = m.group(1).upper()
        if a == 'X': xs.append(v)
        elif a == 'Y': ys.append(v)
        elif a == 'Z': zs.append(v)
        else: e_pos_max = max(e_pos_max, v)
print('sha256=' + hashlib.sha256(data).hexdigest())
print('bytes=%d' % len(data))
print('lines=%d' % text.count('\n'))
print('moves=%d' % moves)
print('x_range=%.2f..%.2f' % (min(xs), max(xs)))
print('y_range=%.2f..%.2f' % (min(ys), max(ys)))
print('z_range=%.2f..%.2f' % (min(zs), max(zs)))
print('e_max=%.3f' % e_pos_max)
