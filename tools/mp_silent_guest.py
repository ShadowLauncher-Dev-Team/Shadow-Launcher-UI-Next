
import socket, sys, time
ip, port = sys.argv[1], int(sys.argv[2])
s = socket.create_connection((ip, port), timeout=10)
print('connected, staying silent (no heartbeat) for 8s to simulate slow handshake')
time.sleep(8)
print('done')
