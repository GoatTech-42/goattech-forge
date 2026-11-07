import re,sys
from pathlib import Path
p=Path(sys.argv[1]);lines=p.read_text().splitlines();z=None;after=False;travel=[]
for line in lines:
 if line.startswith(';ZONE A'):after=True;continue
 if not line.startswith('G1 '):continue
 parts={k:float(v) for k,v in re.findall(r'([XYZE])(-?\d+(?:\.\d+)?)',line)}
 if 'Z'in parts:z=parts['Z']
 if not after:continue
 if 'X'in parts or 'Y'in parts:
  if 'E'in parts:break
  travel.append((line,z));assert z is not None and z>=2,'initial bare-bed XY travel below2mm: '+str((line,z))
assert travel,'no initial XY travel observed'
print('initial destination travel keptZ>=2:',travel)
