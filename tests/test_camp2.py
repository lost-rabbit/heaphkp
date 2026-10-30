"""Auto camp + !camp shorthand + belt-free logic checks on the CURRENT heaphkp.lua (client.py harness)."""
import os, sys, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client

h = Client('Heaph', ['Heaph', 'Synaptic', 'Donut'])
def own(kind, msg):
    data = struct.pack('<I B B', 0, kind, 0) + msg.encode() + b'\0'
    h.run('packet_out', h.L.table_from({'id': 0xB5, 'data': data.decode('latin-1')}))

own(5, '!camp auto King Arthro'); h.step(10, 10); h.out('own LS: camp auto')
h.kill('King Arthro'); h.step(10, 10); h.out('kill sets ToD (no event: no LS post expected)')
h.step(21 * 3600 - 15 * 60, 1); h.step(6, 6); h.out('20 min before window: alert only, no camp yet')
h.step(11 * 60, 1); h.step(6, 6); h.out('9 min before window: auto start')
h.kill('King Arthro'); h.step(10, 10); h.out('target killed during event: posts + bonus')
h.step(11 * 60, 1); h.step(4, 4); h.out('11 min later: auto end')
own(5, '!camp start Tiamat'); h.step(4, 4); h.out('own camp start Tiamat')
own(5, '!camp stop'); h.step(4, 4); h.out('stop')
# ready check + bids via chat, undo, export
h.cmd('/hkp start Fafnir camp'); h.step(4, 4); h.chat(5, 'Kooboo', 'here'); h.step(130); h.step(4, 4); h.out('tick')
h.cmd('/hkp auction Ridill 3'); h.step(2, 2); h.chat(5, 'Donut', 'bid 3'); h.chat(5, 'Synaptic', 'bid 4'); h.step(4, 4); h.step(50); h.step(4, 4); h.out('auction')
h.cmd('/hkp undo'); h.step(4, 4); h.cmd('/hkp export'); h.out('undo + export')
h.lua('for k, m in pairs(db.members) do print(k .. " dkp=" .. m.dkp) end'); h.out('standings')

# --- chat-log backfill: a kill 2 h ago in today's log sets the ToD silently; a player's chat line does not
import datetime
b = Client('Heaph', ['Heaph'])
t2 = int(b.g.NOW) - 2 * 3600
hhmmss = datetime.datetime.fromtimestamp(t2).strftime('%H:%M:%S')
b.write_log(['[%s] Synaptic defeats the Simurgh.' % hhmmss, '[%s] Troll : lol Heaph defeats Roc.' % hhmmss, '[%s] (Bob) Bob defeats Tiamat.' % hhmmss])
b.step(1, 2); b.out('backfill on first tick')
print('backfill: Simurgh set:', b.ev('db.tods.Simurgh ~= nil'), '| Roc (chat line) set:', b.ev('db.tods.Roc ~= nil'), '| Tiamat (party line) set:', b.ev('db.tods.Tiamat ~= nil'))
# --- a typed chat line can no longer fake a kill (kills come from packet 0x029 now)
b.chat(5, 'Troll', 'Heaph defeats King Arthro.'); b.step(1, 2)
print('chat spoof set King Arthro:', b.ev('db.tods["King Arthro"] ~= nil'))
b.kill('King Arthro'); b.step(1, 2)
print('real packet set King Arthro:', b.ev('db.tods["King Arthro"] ~= nil'))
