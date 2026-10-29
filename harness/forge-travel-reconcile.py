#!/usr/bin/env python3
"""Per-travel classification of a Forge diagnostic G-code file (simulation only).
usage: forge-travel-reconcile.py plate.gcode [out.csv]
Denominator: every non-extruding XY travel. Three rules per travel:
 R1 strict-cell: 1mm heightmap (same cells as trajectory_check), cells crossed
    EXCLUDING the explicit start cell and destination cell; flag if h>0 and nz<h+0.1.
 R2 sampled overlap: 0.1mm samples; sample overlaps a printed bead if lateral
    distance<0.4 to a printed segment with top>=nz-0.05. mid_mm counts only
    samples >1mm from BOTH travel ends.
 R3 end_only: overlap exists but only within 1mm of start/end (pure endpoint contact).
"""
import re,sys,math,collections,csv
W=240; hmap=[[0.0]*W for _ in range(W)]
def cells(x0,y0,x1,y1):
    n=max(1,int(math.hypot(x1-x0,y1-y0)/0.25)); out=[]
    for i in range(n+1):
        t=i/n; c=(int(x0+(x1-x0)*t),int(y0+(y1-y0)*t))
        if 0<=c[0]<W and 0<=c[1]<W and c not in out: out.append(c)
    return out
segs=[]; grid=collections.defaultdict(list)
def add(s):
    i=len(segs); segs.append(s); x0,y0,x1,y1,_=s
    for gx in range(int(min(x0,x1)//2)-1,int(max(x0,x1)//2)+2):
        for gy in range(int(min(y0,y1)//2)-1,int(max(y0,y1)//2)+2): grid[(gx,gy)].append(i)
def dist(px,py,s):
    x0,y0,x1,y1,_=s; dx,dy=x1-x0,y1-y0; L=dx*dx+dy*dy
    t=0 if L==0 else max(0,min(1,((px-x0)*dx+(py-y0)*dy)/L))
    return math.hypot(px-(x0+t*dx),py-(y0+t*dy))
rows=[]; x=y=z=e=0.0; zone='start'
for raw in open(sys.argv[1]).read().split('\n'):
    if raw.startswith(';ZONE'): zone=raw[6:8].strip()
    l=raw.split(';',1)[0].strip()
    if not l: continue
    p=l.split(); c=p[0]; a={}
    for q in p[1:]:
        m=re.match(r'^([A-Za-z])(-?[0-9.]+)$',q)
        if m:a[m.group(1)]=float(m.group(2))
    if c=='G28': x=y=z=0.0
    if c=='G92' and 'E' in a: e=a['E']
    if c not in('G0','G1'): continue
    nx,ny,nz=a.get('X',x),a.get('Y',y),a.get('Z',z); ne=a.get('E',e)
    xy=(nx,ny)!=(x,y); ext=('E' in a) and ne>e+1e-9 and xy
    if xy and not ext:
        cl=cells(x,y,nx,ny); sc=(int(x),int(y)); dc=(int(nx),int(ny))
        r1=any(hmap[cx][cy]>1e-6 and nz<hmap[cx][cy]+0.1 for cx,cy in cl if (cx,cy) not in (sc,dc))
        Ln=math.hypot(nx-x,ny-y); n=max(1,int(Ln/0.1)); mid=0; endn=0
        for k in range(n+1):
            px=x+(nx-x)*k/n; py=y+(ny-y)*k/n
            if any(segs[i][4]>=nz-0.05 and dist(px,py,segs[i])<0.4 for i in set(grid[(int(px//2),int(py//2))])):
                if math.hypot(px-x,py-y)>1 and math.hypot(px-nx,py-ny)>1: mid+=1
                else: endn+=1
        rows.append((zone,round(x,2),round(y,2),round(nx,2),round(ny,2),nz,round(Ln,1),int(r1),round(mid*0.1,1),int(mid==0 and endn>0)))
    if ext:
        add((x,y,nx,ny,nz))
        for cx,cy in cells(x,y,nx,ny):
            if hmap[cx][cy]<nz: hmap[cx][cy]=nz
    x,y,z,e=nx,ny,nz,ne
if len(sys.argv)>2:
    w=csv.writer(open(sys.argv[2],'w')); w.writerow('zone x0 y0 x1 y1 z len R1_strict_cell R2_mid_overlap_mm R3_end_only'.split()); w.writerows(rows)
print('zone | non-extruding XY travels | R1 strict-cell flagged | R2 mid-overlap>=3mm | R2 mid-overlap>0 | R3 end-only')
for zn in ('A','B','C'):
    rr=[r for r in rows if r[0]==zn]
    print(zn,len(rr),sum(r[7] for r in rr),sum(r[8]>=3 for r in rr),sum(r[8]>0 for r in rr),sum(r[9] for r in rr),'max_mid_mm',max([r[8] for r in rr] or [0]))
