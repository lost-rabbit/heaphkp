import json, urllib.request, time, sys
BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:8799'

def post(path, body):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), {'content-type': 'application/json', 'User-Agent': 'heaphkp-tests/1.0'})
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read())

for _ in range(60):
    try: urllib.request.urlopen(BASE, timeout=3); break
    except Exception: time.sleep(1)

ls = 'TestShell%d' % int(time.time())
s, r = post('/register', {'ls': ls, 'name': 'heaph'}); print('register', s, r.get('role'), r.get('owner')); owner = r['token']
s, r = post('/register', {'ls': ls, 'name': 'Synaptic'}); print('second register', s, r)
s, r = post('/invite', {'token': owner, 'name': 'Synaptic', 'role': 'officer'}); print('invite officer', s, r.get('code')); code = r['code']
s, r = post('/join', {'ls': ls, 'name': 'Donut', 'code': code}); print('wrong person joins', s, r)
s, r = post('/join', {'ls': ls, 'name': 'Synaptic', 'code': code}); print('join', s, r.get('role')); syn = r['token']
s, r = post('/join', {'ls': ls, 'name': 'Synaptic', 'code': code}); print('reuse code', s, r)
s, r = post('/sync', {'token': syn, 'since': 0, 'ops': [{'cid': 's1', 'kind': 'rec', 'body': {'id': 's1', 'kind': 'tick', 'deltas': [{'n': 'Donut', 'd': 1}]}},
                                                       {'cid': 's2', 'kind': 'role', 'body': {'n': 'Donut', 'r': 'admin'}}]})
print('officer sync', s, 'ops', len(r['ops']), 'rejected', r['rejected'])
s, r = post('/sync', {'token': syn, 'since': 0, 'ops': [{'cid': 's1', 'kind': 'rec', 'body': {}}]}); print('resend dup', s, len(r['ops']))
s, r = post('/invite', {'token': syn, 'name': 'Kooboo', 'role': 'viewer'}); print('officer invites', s, r)
s, r = post('/invite', {'token': owner, 'name': 'Kooboo', 'role': 'viewer'}); kcode = r['code']
s, r = post('/join', {'ls': ls, 'name': 'Kooboo', 'code': kcode}); koo = r['token']
s, r = post('/sync', {'token': koo, 'since': 0, 'ops': [{'cid': 'k1', 'kind': 'rec', 'body': {}}]}); print('viewer pushes', s, r['rejected'], 'sees', len(r['ops']), 'role', r['role'])
s, r = post('/sync', {'token': owner, 'since': 0, 'ops': [{'cid': 'h1', 'kind': 'role', 'body': {'n': 'Synaptic', 'r': 'none'}}]}); print('owner revokes Synaptic', s, r['rejected'], [x['name'] + ':' + x['role'] for x in r['roles']])
s, r = post('/sync', {'token': syn, 'since': 0, 'ops': []}); print('revoked syncs', s, r)
s, r = post('/sync', {'token': owner, 'since': 1, 'ops': []}); print('owner pull since 1', s, [(o['seq'], o['kind'], o['author']) for o in r['ops']])
