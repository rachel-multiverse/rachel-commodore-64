import json,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'build/production-ui';out.mkdir(exist_ok=True)
script=[{'action':'run_frames','frames':200},{'action':'type_string','text':'RUN\n','hold_frames':2,'settle_frames':40},{'action':'run_frames','frames':30},{'action':'type_string','text':'s','hold_frames':2,'settle_frames':30},{'action':'type_string','text':'8','hold_frames':2,'settle_frames':400}]
script += [{'action':'memory_read','addr':0x19,'len':1},{'action':'press_key','key':'Right','hold_frames':2},{'action':'run_frames','frames':10},{'action':'memory_read','addr':0x19,'len':1}]
script += [{'action':'memory_read','addr':a,'len':256} for a in range(0x400,0x800,256)]
(out/'session.json').write_text(json.dumps(script))
bin=str(Path.home()/'Projects/198x/Emu198x/emu198x/target/release/emu198x-c64')
r=subprocess.run([bin,'--headless','--rom-dir',str(Path.home()/'.emu198x/roms/commodore-c64'),'--load',str(root/'build/rachel.prg'),'--script',str(out/'session.json'),'--screenshot',str(out/'solo.png')],capture_output=True,text=True,timeout=120)
(out/'report.json').write_text(r.stdout+r.stderr)
assert r.returncode==0, r.stderr
reads=[o['bytes'] for o in json.loads(r.stdout)['observations'] if o['kind']=='memory_read']
assert reads[0]==[0] and reads[1]==[1], f'production cursor did not move: {reads[:2]}'
screen=sum(reads[2:],[])
def row(n):
 return ''.join(chr((c&127)+64 if (c&127)<32 else c&127) for c in screen[n*40:n*40+40])
for seat in range(8):
 assert f'P{seat+1}:' in row(2+seat//4), f'missing seat {seat+1}'
assert 'YOUR TURN' in row(24), row(24)
assert 'P PLAY' in row(20), row(20)
print('Production keyboard smoke passed: choose solo, eight seats, move cursor')
