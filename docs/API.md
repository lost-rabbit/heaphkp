# Integrating with HeaphKP

Two doors: one inside the game for other Ashita addons, one outside for bots, websites and spreadsheets.

## Inside the game: other Ashita addons

No key needed. Each Ashita addon has its own Lua state, so HeaphKP talks through a file and commands.

**Read:** `config\addons\heaphkp\state.json`, rewritten every 5 seconds while the addon runs. It holds the open book's
name and your role, `standings` (name, dkp, earned, spent, ticks), `timers` (mob, form, zone, tod, opens, closes,
state = waiting | open | closed | forced | no-timer, and the text the window shows), the running `event`,
`readyCheck` and `auction` if any, the last 20 `drops` and the last 20 `history` lines. All times are Unix seconds.

```lua
local json = require('json');
local f = io.open(AshitaCore:GetInstallPath() .. 'config\\addons\\heaphkp\\state.json', 'r');
if f then
    local st = json.decode(f:read('*a')); f:close();
    for _, t in ipairs(st.timers) do print(t.mob, t.state, t.text); end
end
```

**Write:** queue HeaphKP's own commands. They run with the keeper's rights on that PC.

```lua
AshitaCore:GetChatManager():QueueCommand(1, '/hkp tod ka now');          -- King Arthro died now
AshitaCore:GetChatManager():QueueCommand(1, '/hkp add Synaptic 5 helped'); -- +5 DKP with a reason
AshitaCore:GetChatManager():QueueCommand(1, '/hkp event start kb');       -- start a King Behemoth camp
```

The full command list is in the addon's Help tab and in `/hkp help`. Mob aliases (`ka`, `kb`, `faf`, `nid`, `sim`,
`serk`, `tia`, `jorm`, `kv`, `cerb`, `khim`, …) work everywhere a mob name does.

## Outside the game: the REST API

A shared book lives on the sync server. The linkshell owner or an admin makes API keys in HeaphKP's Linkshells tab
(label + role). A key is shown once. On the server it is the identity `bot:<label>`, so everything a bot writes is
signed as that bot, never as a player, and it can be revoked like any member.

- **viewer** key: read the book.
- **officer** key: also record ToDs, adjust DKP, award items.

Send the key as `Authorization: Bearer hkp_…` (or `"key"` in the JSON body). 120 calls per minute per key.

### GET /v1/book

Everything a player sees, computed from the shared log:

```json
{
  "ls": "HeaphsHarem", "time": 1793400000,
  "standings": [{ "name": "Synaptic", "dkp": 42, "earned": 60, "spent": 18, "ticks": 31 }],
  "timers": [{ "mob": "King Arthro", "form": "King Arthro", "zone": "Jugner Forest", "tod": 1793390000,
               "by": "Heaph", "opens": 1793465900, "closes": 1793476700, "state": "waiting" }],
  "prices": { "ridill": { "name": "Ridill", "min": 200 } },
  "drops": [ { "id": "...", "t": 1793390010, "item": "Ridill", "mob": "Fafnir", "awarded": "Synaptic", "price": 250 } ],
  "history": [ { "id": "...", "t": 1793390020, "kind": "win", "by": "Heaph", "text": "Synaptic won Ridill for 250" } ],
  "live": [ { "who": "Heaph", "event": { "name": "Fafnir camp", "ticks": 3 } } ],
  "auto": [ "King Arthro" ]
}
```

### POST /v1/tod

`{ "mob": "King Arthro", "time": "now" }` — `time` may be `"now"` (default), Unix seconds, `"-15m"` or `"-2h"`.
`form` names the HQ (`"Nidhogg"` on the Fafnir timer). Officer keys only.

### POST /v1/adjust

`{ "name": "Synaptic", "amount": 5, "reason": "helped" }` — officer keys only.

### POST /v1/award

`{ "name": "Synaptic", "price": 250, "item": "Ridill" }` — officer keys only.

Errors come back as `{ "error": "…" }` with 400 (bad input), 401 (bad key), 403 (read-only key), 429 (rate limit).

### Python example

```python
import requests
KEY = 'hkp_...'
BASE = 'https://<your-worker>.workers.dev'
H = {'Authorization': 'Bearer ' + KEY}

book = requests.get(BASE + '/v1/book', headers=H).json()
for t in book['timers']:
    if t['state'] in ('waiting', 'open'):
        print(t['mob'], t['state'], 'opens', t.get('opens'))

requests.post(BASE + '/v1/tod', headers=H, json={'mob': 'Simurgh', 'time': 'now'})
```

### curl

```
curl -H "Authorization: Bearer hkp_..." https://<your-worker>.workers.dev/v1/book
curl -H "Authorization: Bearer hkp_..." -H "content-type: application/json" -d "{\"name\":\"Synaptic\",\"amount\":5}" https://<your-worker>.workers.dev/v1/adjust
```

Players' HeaphKP windows pick up a bot's changes on their next sync (within about 15 seconds).
