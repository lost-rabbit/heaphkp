import os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client
for _ in range(90):
    try: urllib.request.urlopen('http://127.0.0.1:8799', timeout=3); break
    except Exception: time.sleep(1)

LS = 'Share%d' % (int(time.time()) % 100000)
h = Client('Heaph', ['Heaph', 'Kooboo'], ls_items=[(513, LS)])
k = Client('Kooboo', ['Kooboo', 'Heaph'], ls_items=[(515, LS)])
def deliver(src, dst):
    for line in list(src.g.sent.values()):
        if line.startswith('/t %s ' % dst.name): dst.chat(3, src.name, line[len('/t %s ' % dst.name):])
h.lua("register_ls('%s', false)" % LS); h.settle()
h.lua("send_invite('Kooboo', 'viewer')"); h.step(2, 2); deliver(h, k)
print('invite tell:', [x for x in h.g.sent.values() if 'Invite' in x])
k.lua("join_ls(pendingInvites[1].ls, pendingInvites[1].code)"); k.settle()
k.kill('Simurgh'); k.settle(); h.settle()
print('viewer shared Simurgh -> Heaph has it:', h.ev('db.tods.Simurgh ~= nil'))
k.lua("db.cfg.shareTod = false"); k.kill('Roc'); k.settle(); h.settle()
print('DO NOT SHARE Roc -> Heaph has it:', h.ev('db.tods.Roc ~= nil'), '| Kooboo has it:', k.ev('db.tods.Roc ~= nil'))
k.lua("adjust('Kooboo', 50, 'cheat', 'Kooboo')") if False else None
print('Kooboo posted to LS:', [x for x in k.g.sent.values() if x.startswith('/l')])
