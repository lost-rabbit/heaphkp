"""API keys and the /v1 endpoints: a bot reads the book, writes signed as bot:<label>, read-only keys cannot write,
revoked keys stop working, and the in-game state.json is written."""
import os, sys, time, json, urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client
BASE = 'http://127.0.0.1:8799'
for _ in range(120):
    try: urllib.request.urlopen(BASE, timeout=3); break
    except Exception: time.sleep(1)

def call(method, path, body=None, key=None):
    data = json.dumps(body).encode() if body is not None else None
    hdr = {'content-type': 'application/json', 'User-Agent': 'heaphkp-tests/1.0'}
    if key: hdr['Authorization'] = 'Bearer ' + key
    req = urllib.request.Request(BASE + path, data, hdr, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r: return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read())

LS = 'Api%d' % (int(time.time()) % 100000)
h = Client('Heaph', ['Heaph', 'Synaptic', 'Donut'], ls_items=[(513, LS)])
h.lua("register_ls('%s', false)" % LS); h.settle()
h.lua("adjust('Donut', 10, 'seed', 'Heaph')"); h.kill('Simurgh'); h.settle()
token = h.ev('access.books[bookKey].token')

s, r = call('POST', '/keys', {'token': token, 'label': 'Discord', 'role': 'officer'}); print('make officer key', s, r.get('name'))
bot = r['key']
s, r = call('POST', '/keys', {'token': token, 'label': 'Site', 'role': 'viewer'}); ro = r['key']; print('make viewer key', s, r.get('name'))
s, r = call('GET', '/v1/book', key=bot)
print('GET book', s, '| Donut', [x for x in r['standings'] if x['name'] == 'Donut'], '| timers', [(t['mob'], t['state']) for t in r['timers']])
s, r = call('POST', '/v1/adjust', {'name': 'Donut', 'amount': 7, 'reason': 'from discord'}, key=bot); print('bot adjust', s, r.get('by'))
s, r = call('POST', '/v1/tod', {'mob': 'King Arthro', 'time': '-30m'}, key=bot); print('bot tod', s, r.get('by'))
s, r = call('POST', '/v1/award', {'name': 'Synaptic', 'price': 3, 'item': 'Ridill'}, key=bot); print('bot award', s)
s, r = call('POST', '/v1/adjust', {'name': 'Donut', 'amount': 99}, key=ro); print('viewer key writes ->', s, r.get('error'))
h.settle()
h.lua('''
print('Donut dkp=' .. db.members.Donut.dkp .. ' Synaptic dkp=' .. tostring(db.members.Synaptic and db.members.Synaptic.dkp))
for _, e in ipairs(db.history) do if e.by and e.by:find('^bot:') then print('history by ' .. e.by .. ': ' .. e.text) end end
print('KA tod by=' .. tostring(db.tods['King Arthro'] and db.tods['King Arthro'].by))
for _, k in ipairs(db.keys or {}) do print('key listed: ' .. k.name .. ' ' .. k.role) end
''')
h.out('client after bot writes')
s, r = call('POST', '/keys/revoke', {'token': token, 'label': 'Discord'}); print('revoke', s, r)
s, r = call('GET', '/v1/book', key=bot); print('revoked key reads ->', s, r.get('error'))
s, r = call('GET', '/v1/book', key=ro); print('viewer key reads ->', s, 'Donut', [x['dkp'] for x in r['standings'] if x['name'] == 'Donut'])
h.step(6, 2)
st = json.load(open(os.path.join(h.install, 'config', 'addons', 'heaphkp', 'state.json'), encoding='utf-8'))
print('state.json:', st['book'], '| standings', [(x['name'], x['dkp']) for x in st['standings']], '| timers', [(t['mob'], t['state']) for t in st['timers']])
