"""Nobody can write as someone else: an officer's modified client claims by='Heaph'; the server stamps Synaptic."""
import os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client
for _ in range(120):
    try: urllib.request.urlopen('http://127.0.0.1:8799', timeout=3); break
    except Exception: time.sleep(1)

LS = 'Ident%d' % (int(time.time()) % 100000)
h = Client('Heaph', ['Heaph', 'Synaptic'], ls_items=[(513, LS)])
s = Client('Synaptic', ['Synaptic', 'Heaph'], ls_items=[(515, LS)])
def deliver(src, dst):
    for line in list(src.g.sent.values()):
        if line.startswith('/t %s ' % dst.name): dst.chat(3, src.name, line[len('/t %s ' % dst.name):])
h.lua("register_ls('%s', false)" % LS); h.settle()
h.lua("send_invite('Synaptic', 'officer')"); h.step(2, 2); deliver(h, s)
s.lua("join_ls(pendingInvites[1].ls, pendingInvites[1].code)"); s.settle()

# a tampered client: the adjust is recorded with by = 'Heaph' and a drop 'seen by' Heaph
s.lua("adjust('Donut', 25, 'totally heaph', 'Heaph')")
s.lua("emit('drop', { id = new_id(), t = os.time(), item = 'Ridill', mob = 'Fafnir', slot = 0, seenBy = 'Heaph' })")
s.lua("set_tod('Simurgh', os.time() - 60, 'Heaph', nil, true)")
s.settle(); h.settle()
h.lua('''
for _, e in ipairs(db.history) do if e.kind == 'adjust' then print('adjust by=' .. tostring(e.by)) end end
for _, d in ipairs(db.drops) do print('drop seenBy=' .. tostring(d.seenBy)) end
print('tod by=' .. tostring(db.tods.Simurgh and db.tods.Simurgh.by))
for n, r in pairs(db.perms) do local sn = db.seen[n] or {}; print(('registry %s %s joined=%s last=%s'):format(n, r, tostring(sn.joined), tostring(sn.last))) end
''')
h.out('what Heaph sees')

# an impostor with a stolen code for another name is refused; a bare name cannot join
h.lua("send_invite('Donut', 'viewer')"); h.step(2, 2)
code = [x for x in h.g.sent.values() if 'Invite' in x][-1].split('Code ')[1].split('.')[0]
s.lua("join_ls('%s', '%s')" % (LS, code)); s.settle()
print('Synaptic uses Donut\'s code ->', s.ev('lsMsg'))
