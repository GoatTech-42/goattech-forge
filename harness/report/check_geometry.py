from pathlib import Path
import re,sys
root=Path(sys.argv[1]); h=(root/'Marlin/src/lcd/dwin/creality/dwin_lcd.h').read_text(); cpp=(root/'Marlin/src/lcd/dwin/creality/dwin.cpp').read_text(); dh=(root/'Marlin/src/e3v3se/forge_diag.h').read_text()
def define(text,name):return int(re.search(r'^#define\s+'+name+r'\s+(\d+)',text,re.M)[1])
w,ht=define(h,'DWIN_WIDTH'),define(h,'DWIN_HEIGHT');cols=define(dh,'FORGE_REPORT_WIDTH')-1;rows=define(dh,'FORGE_REPORT_MAX_LINES')
f=cpp.split('void Draw_ForgeDiagReport()\n{')[1].split('\n}')[0]
m=re.search(r'Color_Bg_Black, (\d+), (\d+) \+ i \* (\d+), lines\[i\]',f);x,y,stride=map(int,m.groups())
print(dict(panel=(w,ht),cell=(8,16),rows=rows,cols=cols,x_end=x+cols*8,y_end=y+(rows-1)*stride+16))
assert x+cols*8<=w,'report horizontal clipping'
assert y+(rows-1)*stride+16<=ht,'report vertical clipping'
assert y>=25 and stride>=16,'report overlaps title or rows'
print('SOURCE CELL GEOMETRY PASS, not panel glyph proof')
