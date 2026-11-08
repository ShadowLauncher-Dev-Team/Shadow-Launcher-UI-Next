
import socket, struct, json, time, sys

HOST_IP, PORT, LAT = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
s = socket.create_connection((HOST_IP, PORT), timeout=10)
print('connected; reporting latency=%d, never answering anything' % LAT)

def pack(t, body):
    tb = t.encode()
    return bytes([len(tb)]) + tb + struct.pack('>I', len(body)) + body

def hb():
    return pack('c:player_ping', json.dumps({
        'name': 'PY-GUEST2', 'machine_id': 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        'hostname': 'pyhost2', 'vendor': 'python-test', 'latency': LAT,
        'ts': int(time.time()*1000),
    }).encode())

buf = b''
s.settimeout(0.2)
requests = 0
end = time.time() + 9
while time.time() < end:
    s.sendall(hb())
    t0 = time.time()
    while time.time() - t0 < 1.2:
        try:
            chunk = s.recv(65536)
            if not chunk: print('peer closed'); break
            buf += chunk
        except socket.timeout:
            pass
        while len(buf) >= 5:
            if buf[0] == 0:
                ln = struct.unpack('>I', buf[1:5])[0]
                if len(buf) < 5 + ln: break
                buf = buf[5+ln:]
            else:
                tl = buf[0]
                if len(buf) < 5 + tl: break
                t = buf[1:1+tl].decode(errors='replace')
                ln = struct.unpack('>I', buf[1+tl:5+tl])[0]
                if len(buf) < 5 + tl + ln: break
                buf = buf[5+tl+ln:]
                requests += 1
                print('  !! host sent request', t)
print('total requests received from host =', requests)
