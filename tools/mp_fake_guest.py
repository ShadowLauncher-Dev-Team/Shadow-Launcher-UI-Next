
import socket, struct, json, time, sys

HOST_IP = sys.argv[1] if len(sys.argv) > 1 else '127.0.0.1'
PORT = int(sys.argv[2])

s = socket.create_connection((HOST_IP, PORT), timeout=10)
print('connected to', HOST_IP, PORT)

def pack(t, body):
    tb = t.encode()
    return bytes([len(tb)]) + tb + struct.pack('>I', len(body)) + body

def player_ping(ts):
    return pack('c:player_ping', json.dumps({
        'name': 'PY-GUEST', 'machine_id': 'ffffffffffffffffffffffffffffffff',
        'hostname': 'pyhost', 'vendor': 'python-test', 'ts': ts,
    }).encode())

buf = b''
def pump(dur):
    global buf
    end = time.time() + dur
    s.settimeout(0.3)
    while time.time() < end:
        try:
            chunk = s.recv(65536)
            if not chunk:
                print('peer closed'); return
            buf += chunk
        except socket.timeout:
            pass
        # parse frames
        while True:
            if len(buf) < 5: break
            if buf[0] == 0:                      # response
                ln = struct.unpack('>I', buf[1:5])[0]
                if len(buf) < 5 + ln: break
                body = buf[5:5+ln]; buf = buf[5+ln:]
                print('  response len=%d %s' % (ln, body[:80]))
            else:                                # request with type
                tl = buf[0]
                if len(buf) < 1 + tl + 4: break
                t = buf[1:1+tl].decode()
                ln = struct.unpack('>I', buf[1+tl:5+tl])[0]
                if len(buf) < 5 + tl + ln: break
                body = buf[5+tl:5+tl+ln]; buf = buf[5+tl+ln:]
                print('  request %s len=%d' % (t, ln))
                if t == 'c:player_ping':
                    # echo back as pong
                    tb = 'c:player_pong'.encode()
                    s.sendall(bytes([len(tb)]) + tb + struct.pack('>I', len(body)) + body)
                    print('   -> pong echoed')

now = lambda: int(time.time() * 1000)
for i in range(6):
    s.sendall(player_ping(now()))
    print('sent player_ping ts=%d' % now())
    pump(1.5)
print('done')
