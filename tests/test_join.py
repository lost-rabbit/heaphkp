"""Roll call (LS and individual), !join heaphkp requests, Invite all / Approve all."""
import os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client
for _ in range(120):
    try: urllib.request.urlopen('http://127.0.0.1:8799', timeout=3); break
    except Exception: time.sleep(1)

LS = 'Join%d' % (int(time.time()) % 100000)
h = Client('Heaph', ['Heaph', 'Donut', 'Synaptic'], ls_items=[(513, LS)])
d = Client('Donut', ['Donut', 'Heaph'], ls_items=[(515, LS)])
s = Client('Synaptic', ['Synaptic', 'Heaph'], ls_items=[(515, LS)])
def deliver(src, dsts):
    """Hand every LS line and tell the source queued to the right fake clients."""
    for line in list(src.g.sent.values()):
        if line.startswith('/l '):
            for c in dsts: c.chat(5, src.name, line[3:])
        elif line.startswith('/t '):
            name, text = line[3:].split(' ', 1)
            for c in dsts:
                if c.name == name: c.chat(3, src.name, text)
    src.L.execute('sent = {}')
h.lua("register_ls('%s', false)" % LS); h.settle()

# roll call to the LS: both answer by tell
h.cmd('/hkp rollcall'); h.step(2, 2); deliver(h, [d, s])
d.step(2, 2); s.step(2, 2); deliver(d, [h]); deliver(s, [h])
print('roll call answers:', h.ev("(function() local t = {} for n, a in pairs(HK.rollcall) do t[#t+1] = n .. ' ' .. a.ver end table.sort(t) return table.concat(t, ', ') end)()"))
# asked again within 10 min: no second answer
h.cmd('/hkp rollcall'); h.step(2, 2); deliver(h, [d, s]); d.step(2, 2)
print('Donut answered twice?', any('present' in x for x in d.g.sent.values()))
# individual ask by target
h.target('Donut'); h.cmd('/hkp rollcall t'); h.step(2, 2)
print('ask target sends a tell:', [x for x in h.g.sent.values() if x.startswith('/t Donut')][:1])
h.L.execute('sent = {}')

# !join heaphkp from Synaptic in LS
s.lua("sent = {}");
h.chat(5, 'Synaptic', '!join heaphkp'); h.chat(5, 'Donut', '!join')
print('join requests:', h.ev("(function() local t = {} for n in pairs(HK.joinReq) do t[#t+1] = n end table.sort(t) return table.concat(t, ', ') end)()"))
# approve all as officer
h.lua("for n in pairs(HK.joinReq) do HK.approve_join(n, 'officer') end"); h.step(4, 4); deliver(h, [d, s])
d.out('Donut gets'); s.out('Synaptic gets')
d.lua("join_ls(pendingInvites[1].ls, pendingInvites[1].code)"); s.lua("join_ls(pendingInvites[1].ls, pendingInvites[1].code)"); d.settle(); s.settle(); h.settle()
print('Donut:', d.ev('access.books[bookKey] and access.books[bookKey].role'), '| Synaptic:', s.ev('access.books[bookKey] and access.books[bookKey].role'))
print('join requests left:', h.ev("(function() local c = 0 for _ in pairs(HK.joinReq) do c = c + 1 end return c end)()"))
