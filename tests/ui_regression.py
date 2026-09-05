"""Execute production rendering/input routines with ROM-backed KERNAL calls."""
import json, os, re, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EMU = Path(os.environ.get('EMU198X_DIR', Path.home()/'Projects/198x/Emu198x/emu198x'))
OUT = ROOT/'build/ui-regression'
OUT.mkdir(parents=True, exist_ok=True)
subprocess.run(['make'], cwd=ROOT, check=True)
subprocess.run(['asm198x','--dialect','acme','--prg','-I','.', '--sym='+str(OUT/'test.sym'),'tests/ui_regression.asm','-o',str(OUT/'test.prg')],cwd=ROOT,check=True)
symbols=(OUT/'test.sym').read_text()
entry=int(re.search(r'^test_start\s*=\s*\$([0-9a-fA-F]+)',symbols,re.M)[1],16)
data=bytearray((OUT/'test.prg').read_bytes())
# Redirect the test PRG entry after the BASIC stub, never the production PRG.
data[17:20]=bytes([0x4c,entry&255,entry>>8])
(OUT/'test.prg').write_bytes(data)
script=[{'action':'run_frames','frames':200},{'action':'type_string','text':'RUN\n','hold_frames':2,'settle_frames':40},{'action':'run_frames','frames':300}]
script += [{'action':'memory_read','addr':a,'len':n} for a,n in [(0xc400,16)]+[(a,256) for a in range(0x4000,0x5000,256)]]
(OUT/'session.json').write_text(json.dumps(script))
r=subprocess.run([str(EMU/'target/release/emu198x-c64'),'--headless','--rom-dir',str(Path.home()/'.emu198x/roms/commodore-c64'),'--load',str(OUT/'test.prg'),'--script',str(OUT/'session.json'),'--screenshot',str(OUT/'final.png')],capture_output=True,text=True,timeout=120)
(OUT/'emulator.json').write_text(r.stdout+r.stderr)
assert r.returncode==0, r.stderr
reads=[x['bytes'] for x in json.loads(r.stdout)['observations'] if x['kind']=='memory_read']
state=reads[0]
full,short,last,out=[sum(reads[i:i+4],[]) for i in (1,5,9,13)]
assert state[15]==0xaa, f'harness did not finish: {state}'
assert state[11:13]==[0,63], 'user-port frame index was corrupted'
assert state[9:11]==[1,0], 'user-port readiness convention reversed'
assert state[8]==1, 'lobby did not return after link loss'
assert state[:8]==[1,1,0x04,0x05,1,0,2,2], f'input regression: {state}'
def row(screen,n):
 return ''.join(chr((c&127)+64 if (c&127)<32 else c&127) for c in screen[n*40:n*40+40])
assert row(full,0)[12:23]=='RACHEL V1.0',row(full,0)
assert len(set(full[40:79]))==1 and full[40]!=0, 'border is not continuous'
for seat in range(8):
 assert f'P{seat+1}:' in row(full,2+seat//4), f'missing seat {seat+1}'
assert row(full,17)[35:39]=='>2H ',row(full,17)
assert all(c==32 for c in short[14*40+10:18*40]), 'stale cards after hand shrank'
assert 'DRAW' not in row(short,10),row(short,10)
assert 'YOU FINISHED LAST' in row(last,12),row(last,12)
assert 'YOU WENT OUT' in row(out,12),row(out,12)
assert 'YOUR TURN' not in row(out,24),row(out,24)
print('UI regression passed: layout, 32-card hand, stale clearing, keyboard, Ace suit and results')
