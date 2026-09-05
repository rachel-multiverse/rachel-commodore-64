"""Cut two live Ultimate sessions; assert exact seat/hand restoration, then finish."""
import os, select, socket, threading
os.environ.setdefault('RACHEL_E2E_GAME_FRAMES', '4500')
os.environ.setdefault('RACHEL_E2E_OUTPUT', 'reconnect-output')
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen()
listener.settimeout(.5)
os.environ['RACHEL_E2E_CLIENT_PORT'] = str(listener.getsockname()[1])
import full_game_e2e as game
stop = threading.Event()
errors = []
checks = {'drops':0, 'restored':0, 'connections':0}

def proxy():
    token = None
    game_id = None
    seat = None
    latest_hand = None
    expected_hand = None
    turns = 0
    sockets = []
    try:
        while not stop.is_set():
            try: client, _ = listener.accept()
            except socket.timeout: continue
            upstream = socket.create_connection(('127.0.0.1',game.PORT), timeout=10)
            sockets = [client,upstream]
            checks['connections'] += 1
            buffers = {client:bytearray(), upstream:bytearray()}
            dropped = False
            while not stop.is_set() and not dropped:
                ready,_,_ = select.select(sockets,[],[],.25)
                for source in ready:
                    data = source.recv(4096)
                    if not data:
                        dropped=True
                        break
                    buffers[source].extend(data)
                    while len(buffers[source]) >=64:
                        frame=bytes(buffers[source][:64]);del buffers[source][:64]
                        assert frame[:4]==b'RACH', 'proxy lost framing'
                        kind=frame[5]
                        if source is client and kind==1:
                            received_token=frame[36:44]
                            if token is None:
                                token=received_token
                                assert any(token), 'initial HELLO has no reconnect token'
                            else:
                                assert received_token==token, 'token changed on retry'
                                assert frame[10:12]==game_id, 'retry changed game'
                        if source is upstream:
                            if kind==2:
                                if seat is None:
                                    seat=frame[16:18];game_id=frame[18:20]
                                else:
                                    assert frame[16:18]==seat, 'reclaim assigned a different seat'
                                    assert frame[18:20]==game_id, 'reclaim assigned a different game'
                            if kind in (3,0x0f):
                                # GAME_START and HAND_SYNC have count at payload+0.
                                latest_hand=frame[17:17+frame[16]]
                                if expected_hand is not None and kind==0x0f:
                                    assert latest_hand==expected_hand, 'private hand changed during reclaim'
                                    checks['restored']+=1
                                    expected_hand=None
                            if kind==8:
                                turns+=1
                                if checks['drops']<2 and turns in (2,4):
                                    assert latest_hand is not None, 'no private hand before drop'
                                    expected_hand=latest_hand
                                    checks['drops']+=1
                                    dropped=True
                                    break
                        target=upstream if source is client else client
                        target.sendall(frame)
                    if dropped: break
            for s in sockets:
                try:s.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                s.close()
            sockets=[]
    except Exception as e:
        errors.append(e)
    finally:
        for s in sockets:s.close()

thread=threading.Thread(target=proxy,daemon=True);thread.start()
failure = None
try:
    game.main()
except BaseException as error:
    failure = error
finally:
    stop.set();thread.join(timeout=2);listener.close()
assert not errors, errors
if failure is not None:
    raise RuntimeError(f'{failure}; proxy checks: {checks}') from failure
assert checks['drops']==2 and checks['restored']==2, checks
log=(game.OUTPUT/'server.log').read_text()
assert log.count('reclaimed player')>=2, 'server did not record both reclaims'
print('Reconnect passed: two dropped connections, same token/game/seat/hand, game completed')
