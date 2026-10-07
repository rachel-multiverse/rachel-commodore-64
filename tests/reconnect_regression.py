"""Run reconnect hydration/failure paths using production code and framed replies."""
import json, os, re, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reconnect-regression';OUT.mkdir(parents=True,exist_ok=True)
def frame(kind,payload=b'',gid=1):
 b=bytearray(64);b[:4]=b'RACH';b[4]=2;b[5]=kind;b[10:12]=gid.to_bytes(2,'big');b[16:16+len(payload)]=payload
 crc=0xffff
 for c in b:
  crc^=c<<8
  for _ in range(8):crc=((crc<<1)^0x1021 if crc&0x8000 else crc<<1)&0xffff
 b[14:16]=crc.to_bytes(2,'big');return b
welcome=frame(2,bytes([0,0,0,1,2,1,0,1,1]))
state=bytearray(48);state[0]=0;state[3]=14;state[4]=255;state[16]=255;state[20]=1;state[22]=1;state[23]=1
state[24:32]=bytes(range(1,9))
public=frame(7,state)
private=bytearray(48);private[:3]=bytes([2,2,14]);private[36]=1;private[38]=1;private[39]=1;private[40:48]=state[24:32]
hand=frame(15,private)
wrong=bytearray([0,1,0,1,2,1,0,1,1])
cases=[('complete',[welcome,hand,public,hand],0),('wrong_seat',[frame(2,wrong)],1),('wrong_game',[frame(2,gid=2)],1),('rejected',[frame(0xff)],1),('missing_hand',[welcome,public],1),('silent',[],1)]
# Actual ERROR type is 0x0b (see src/rubp.asm); no hand may complete this case.
cases[3]=('rejected',[frame(0x0b)],1)
for label,offset in [('turn',36),('spec',38),('hash',47),('hash_flag',39)]:
 bad=private.copy();bad[offset]^=1
 cases.append(('mismatched_'+label,[welcome,public,frame(15,bad)],1))
 if label=='hash':cases.append(('mismatch_then_match',[welcome,public,frame(15,bad),public,hand],0))
no_hash=state.copy();no_hash[23]=0
cases.append(('missing_state_hash',[welcome,frame(7,no_hash),hand],1))
legacy=bytearray([0,0,0,1,2,1,0,1,0])
cases.append(('legacy_without_hashes',[frame(2,legacy),frame(7,no_hash),frame(15,bytes([2,2,14]))],0))
assert len(cases)*2<31

source='''!source "src/main.asm"
* = $9000
fixture_start:
 jsr init_buffers
 jsr screen_init
 lda #$60
 sta ultimate_close
 sta transport_send_frame
 lda #$4c
 sta transport_connect
 lda #<fixture_connect
 sta transport_connect+1
 lda #>fixture_connect
 sta transport_connect+2
 lda #0
 sta $c820
 lda #$4c
 sta rubp_receive
 lda #<fixture_receive
 sta rubp_receive+1
 lda #>fixture_receive
 sta rubp_receive+2
 lda #1
 sta zp_transport
 sta zp_game_id
 lda #0
 sta zp_game_id+1
 sta zp_player_id
 sta zp_player_id+1
'''
for i,(name,frames,expected) in enumerate(cases):
 source+=f''' lda #<{name}_frames
 sta fixture_pointer
 lda #>{name}_frames
 sta fixture_pointer+1
 lda #{len(frames)}
 sta fixture_remaining
 lda #1
 sta zp_hand_count
 lda #9
 sta MY_HAND
 jsr reconnect_attempt
 sta ${0xc800+i*2:04x}
 lda zp_hand_count
 sta ${0xc801+i*2:04x}
'''
source+=''' lda #$aa
 sta $c81f
 jsr reconnect_session
halt: jmp halt
fixture_connect:
 inc $c820
 lda #0
 rts
fixture_receive:
 lda fixture_remaining
 beq timeout
 lda fixture_pointer
 sta zp_ptr2
 lda fixture_pointer+1
 sta zp_ptr2+1
 ldy #0
copy:
 lda (zp_ptr2),y
 sta SERIAL_RX_BUF,y
 iny
 cpy #64
 bne copy
 clc
 lda fixture_pointer
 adc #64
 sta fixture_pointer
 bcc next
 inc fixture_pointer+1
next:
 dec fixture_remaining
 lda #0
 rts
timeout:
 lda #1
 rts
fixture_pointer: !word 0
fixture_remaining: !byte 0
'''
for name,frames,_ in cases:
 source+=name+'_frames:\n'
 for f in frames:source+=' !byte '+','.join(str(c) for c in f)+'\n'
(OUT/'test.asm').write_text(source)
subprocess.run(['make'],cwd=ROOT,check=True)
subprocess.run(['asm198x','--dialect','acme','--prg','-I','.',str(OUT/'test.asm'),'--sym='+str(OUT/'test.sym'),'-o',str(OUT/'test.prg')],cwd=ROOT,check=True)
entry=int(re.search(r'^fixture_start\s*=\s*\$([0-9a-fA-F]+)',(OUT/'test.sym').read_text(),re.M)[1],16)
b=bytearray((OUT/'test.prg').read_bytes());b[2:15]=bytes([0x0d,8,10,0,0x9e])+str(entry).encode()+bytes([0,0,0]);(OUT/'test.prg').write_bytes(b)
script=[{'action':'run_frames','frames':200},{'action':'type_string','text':'RUN\n','hold_frames':2,'settle_frames':40},{'action':'run_frames','frames':200},{'action':'memory_read','addr':0xc800,'len':32},{'action':'memory_read','addr':0xc820,'len':1},{'action':'type_string','text':'r','hold_frames':2,'settle_frames':200},{'action':'memory_read','addr':0xc820,'len':1},{'action':'type_string','text':'q','hold_frames':2,'settle_frames':200},{'action':'memory_read','addr':0xc310,'len':8},{'action':'memory_read','addr':0x7c0,'len':40}]
(OUT/'session.json').write_text(json.dumps(script))
emu=Path(os.environ.get('EMU198X_DIR',Path.home()/'Projects/198x/Emu198x/emu198x'))/'target/release/emu198x-c64'
r=subprocess.run([str(emu),'--headless','--rom-dir',str(Path.home()/'.emu198x/roms/commodore-c64'),'--load',str(OUT/'test.prg'),'--script',str(OUT/'session.json')],capture_output=True,text=True,timeout=120)
(OUT/'report.json').write_text(r.stdout+r.stderr)
assert r.returncode==0,r.stderr
reads=[o['bytes'] for o in json.loads(r.stdout)['observations'] if o['kind']=='memory_read']
values=reads[0]
assert reads[1:3]==[[len(cases)+3],[len(cases)+6]], ('retry count',reads[1:3])
assert reads[3]==[0]*8, 'menu did not discard old session token'
menu=''.join(chr(c+64 if c<32 else c) for c in reads[4])
assert 'S = SOLO GAME' in menu, menu
assert values[31]==0xaa,values
for i,(name,_,expected) in enumerate(cases):
 assert values[i*2]==expected,(name,values)
 assert values[i*2+1]==(2 if expected==0 else 1),(name,'private hand changed on failure',values)
print('Reconnect hydration regression passed: matching metadata, legacy pairs, ordering, identity, rejection, partial sync and timeout')
