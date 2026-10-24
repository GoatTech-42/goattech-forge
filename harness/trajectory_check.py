#!/usr/bin/env python3
# trajectory_check.py - replay emitted G-code bytes: simulate XYZ/E motion,
# check nozzle-vs-printed-geometry collisions on a heightmap, retract-state
# balance, motion bounds, and the sentinel as the exact final line.
import sys, math, re

path = sys.argv[1]
data = open(path, 'rb').read().decode('ascii', 'replace')
fails = []
def ck(label, cond):
    print(('PASS' if cond else 'FAIL') + ' ' + label)
    if not cond: fails.append(label)

# Sentinel: exact final line
lines = [l for l in data.split('\n')]
final = lines[-2] if lines and lines[-1] == '' else lines[-1]
ck('sentinel is the exact final line', final == ';FORGE_DIAG_COMPLETE')
ck('sentinel appears exactly once', data.count(';FORGE_DIAG_COMPLETE') == 1)

# Heightmap, 1mm cells
W = 240
hmap = [[0.0]*W for _ in range(W)]
def cells_along(x0, y0, x1, y1):
    dist = math.hypot(x1-x0, y1-y0)
    n = max(1, int(dist/0.25))
    seen = set()
    for i in range(n+1):
        t = i/n
        cx, cy = int(x0+(x1-x0)*t), int(y0+(y1-y0)*t)
        if 0 <= cx < W and 0 <= cy < W: seen.add((cx, cy))
    return seen

x = y = z = e = 0.0
abs_xyz, abs_e = True, True
retracted = False
collisions, desc_bad, bounds_bad = 0, 0, 0
double_retract, phantom_deretract = 0, 0
eps = 1e-6
n_moves = 0
for raw in data.split('\n'):
    line = raw.split(';', 1)[0].strip()
    if not line: continue
    parts = line.split()
    cmd = parts[0].upper()
    args = {}
    for p in parts[1:]:
        m = re.match(r'^([A-Za-z])(-?[0-9.]+)$', p)
        if m: args[m.group(1).upper()] = float(m.group(2))
    if cmd == 'G90': abs_xyz = True
    elif cmd == 'G91': abs_xyz = False
    elif cmd == 'M82': abs_e = True
    elif cmd == 'M83': abs_e = False
    elif cmd == 'G28': x = y = z = 0.0
    elif cmd == 'G92':
        if 'E' in args: e = args['E']
    elif cmd in ('G0', 'G1'):
        nx = args.get('X', x) if abs_xyz else x + args.get('X', 0.0)
        ny = args.get('Y', y) if abs_xyz else y + args.get('Y', 0.0)
        nz = args.get('Z', z) if abs_xyz else z + args.get('Z', 0.0)
        de = 0.0; ne = e
        if 'E' in args:
            ne = args['E'] if abs_e else e + args['E']
            de = ne - e
        if not (0 <= nx <= 235 and 0 <= ny <= 235 and -0.01 <= nz <= 40): bounds_bad += 1
        xy_move = (nx, ny) != (x, y)
        z_desc = nz < z - eps
        # Z descent: must not end below existing material at this (x,y)
        if z_desc:
            h = hmap[int(nx)][int(ny)]
            if nz < h - eps: desc_bad += 1
        # XY move: every crossed cell must be clear at nz
        if xy_move:
            for (cx, cy) in cells_along(x, y, nx, ny):
                if nz < hmap[cx][cy] - eps: collisions += 1; break
        # E-only moves: retract-state balance
        if de < -eps and not xy_move:
            if retracted: double_retract += 1
            retracted = True
        elif de > eps and not xy_move:
            if not retracted: phantom_deretract += 1
            retracted = False
        # Extrusion deposits material up to nz along the path
        if de > eps and (xy_move or 'X' in args or 'Y' in args):
            for (cx, cy) in cells_along(x, y, nx, ny):
                if hmap[cx][cy] < nz: hmap[cx][cy] = nz
        x, y, z, e = nx, ny, nz, ne
        n_moves += 1

ck(f'no Z descents into printed material ({desc_bad})', desc_bad == 0)
ck(f'no XY travels through printed material ({collisions})', collisions == 0)
ck(f'no double retracts ({double_retract})', double_retract == 0)
ck(f'no deretract without prior retract ({phantom_deretract})', phantom_deretract == 0)
ck(f'all motion within bed/Z bounds ({bounds_bad} violations)', bounds_bad == 0)
ck(f'move count sane ({n_moves})', 500 < n_moves < 40000)
print('TRAJECTORY ' + ('FAILED' if fails else 'OK'))
sys.exit(1 if fails else 0)
