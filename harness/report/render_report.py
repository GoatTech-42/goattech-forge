#!/usr/bin/env python3
# Layout proof only: draws the report lines on a 272x480 canvas with the firmware's coordinates
# (x=8, y=40+22*i, 8px char cell, 16px line). Uses a monospace stand-in font, NOT the panel's
# font8x16 bitmap, so glyph shapes are approximate. Checks every line stays inside the canvas.
import sys, glob
from PIL import Image, ImageDraw, ImageFont
W,H,CW,CH=272,480,8,16
font=ImageFont.truetype('/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf', 13)
bad=0
for fn in sorted(glob.glob(sys.argv[1]+'-*.txt')):
    lines=open(fn).read().split('\n')[:-1]
    im=Image.new('RGB',(W,H),(0,0,0)); d=ImageDraw.Draw(im)
    d.rectangle([0,0,W,30],fill=(40,40,40)); d.text((8,7),'Forge Report',font=font,fill=(255,255,255))
    for i,l in enumerate(lines):
        x,y=8,40+i*22
        for j,ch in enumerate(l): d.text((x+j*CW,y),ch,font=font,fill=(255,255,255))
        if x+len(l)*CW>W or y+CH>H: bad+=1; print('OVERFLOW',fn,i,l)
    out=fn.replace('.txt','.png'); im.save(out); print(out, 'lines',len(lines),'max_x',8+max(len(l) for l in lines)*CW,'last_y_end',40+(len(lines)-1)*22+CH)
sys.exit(1 if bad else 0)
