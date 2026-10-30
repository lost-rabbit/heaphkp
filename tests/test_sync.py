import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client

LS = 'Harem%d' % (int(time.time()) % 100000)
heaph = Client('Heaph', ['Heaph', 'Synaptic', 'Donut'], ls_items=[(513, LS)])
syn = Client('Synaptic', ['Synaptic', 'Heaph', 'Donut'], ls_items=[(515, LS)])
eq = "(function() local t = equipped_ls(); return t[1].name .. ' / ' .. t[1].kind .. ' / owner=' .. tostring(t[1].owner) end)()"
print('Heaph equipped:', heaph.ev(eq))
print('Synaptic equipped:', syn.ev(eq))

def deliver_tells(src, dst):
    for line in list(src.g.sent.values()):
        if line.startswith('/t %s ' % dst.name):
            dst.chat(3, src.name, line[len('/t %s ' % dst.name):])

# Heaph has a This-PC book, then shares it
heaph.cmd('/hkp add Donut 10 old points'); heaph.cmd('/hkp price Ridill 5')
heaph.lua("register_ls('%s', true)" % LS); heaph.settle(); heaph.out('register + import')
print('Heaph book:', heaph.ev('bookKey'), '| role', heaph.ev('access.books[bookKey].role'), '| unsent', heaph.ev('#db.outbox'))

# Synaptic can't register it (pearl), and the server would refuse anyway
syn.lua("register_ls('%s', false)" % LS); syn.settle(); print('Synaptic tries to register:', syn.ev('lsMsg') if False else '(see below)')
syn.out('synaptic register attempt')

heaph.lua("send_invite('Synaptic', 'officer')"); heaph.step(2, 2)
deliver_tells(heaph, syn); heaph.out('invite sent')
syn.out('invite received')
print('Synaptic pending invites:', syn.ev('#pendingInvites'))
syn.lua("join_ls(pendingInvites[1].ls, pendingInvites[1].code)"); syn.settle(); syn.out('joined')
print('Synaptic book:', syn.ev('bookKey'), '| role', syn.ev('access.books[bookKey].role'),
      '| Donut', syn.ev('db.members.Donut and db.members.Donut.dkp'), '| Ridill min', syn.ev("db.prices.ridill and db.prices.ridill.min"))

# Synaptic runs a camp and an auction; Heaph should see the results
syn.cmd('/hkp camp start King Arthro'); syn.settle(); syn.step(130); syn.settle()
syn.cmd('/hkp auction Ridill'); syn.chat(5, 'Donut', 'bid 6'); syn.step(50); syn.settle(); syn.out('synaptic runs camp + auction')
heaph.settle(); heaph.out('heaph after sync')
print('Heaph sees Donut', heaph.ev('db.members.Donut.dkp'), '| Synaptic', heaph.ev('db.members.Synaptic.dkp'),
      '| live from Synaptic:', heaph.ev("db.live.Synaptic and db.live.Synaptic.s.event and db.live.Synaptic.s.event.name"))
print('Synaptic sees Donut', syn.ev('db.members.Donut.dkp'))

# Heaph undoes the win; Synaptic sees it
heaph.cmd('/hkp undo'); heaph.settle(); syn.settle()
print('after undo: Heaph Donut', heaph.ev('db.members.Donut.dkp'), '| Synaptic Donut', syn.ev('db.members.Donut.dkp'))

# officers can't change roles; owner removes Synaptic's access
syn.lua("set_role('Donut', 'admin')"); syn.settle(); syn.out('officer tries a role change')
heaph.lua("set_role('Synaptic', 'member')"); heaph.settle(); syn.settle(); syn.out('access removed')
print('Synaptic revoked:', syn.ev('access.books[bookKey].revoked'))

# window alert 30 min before
heaph.cmd('/hkp tod Simurgh -1290m'); heaph.step(6, 2); heaph.out('alert')
