
import socket, struct, time, sys
local = None
for line in __import__('subprocess').run(['ipconfig'], capture_output=True, text=True, encoding='gbk', errors='ignore').stdout.splitlines():
    pass
# 直接取默认路由地址不可靠；用 1.1.1.1 UDP connect 探测
s0 = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s0.connect(('1.1.1.1', 53))
local = s0.getsockname()[0]
print('local iface =', local)

payload = b'[MOTD]Test World[/MOTD][AD]25565[/AD]'
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(local))
for i in range(6):
    s.sendto(payload, ('224.0.2.60', 4445))
    print('sent', i+1, 'from', local)
    time.sleep(1.0)
