# Offline tests

The addon runs inside a fake Ashita (`client.py`): Python + `lupa` provide a Lua runtime, the Ashita API is stubbed,
packets and chat lines are fed in, and the chat lines the addon would send are captured.

Needs: Python 3.9+, `pip install lupa`, an Ashita install for `libs/json.lua`, and for the sync tests a local server.

Two environment variables (defaults are a `C:\Games\PhoenixXI` install):

- `HEAPHKP_ADDON` = path of `addons/heaphkp` (defaults to the copy in this repo for `compile_all.py`)
- `ASHITA_LIBS` = your Ashita `addons/libs` folder (for `json.lua`)

```
python compile_all.py        # every Lua file loads
python test_ui2.py           # draws every tab and clicks every button, in every window style
python test_camp2.py         # auto camps, ready checks, auctions, undo, export, chat-log backfill, chat cannot fake a kill
```

Sync tests need the server running locally (see `../server/README.md`):

```
python test_server.py        # the API: register, invite, join, roles, revocation
python test_sync.py          # two players share one book; roles enforced; undo propagates
python test_share.py         # a viewer shares ToDs; the DO NOT SHARE switch; 1-hour codes
python test_identity.py      # a tampered client cannot write as someone else; a stolen code for another name is refused
python test_join.py          # roll call (LS and target), !join heaphkp requests, Invite all / Approve all
python test_api.py           # API keys, GET /v1/book, bot writes signed as bot:<label>, read-only and revoked keys, state.json
```

The game runs LuaJIT 5.1; the harness runs Lua 5.5 and patches `%z` for it. Rendering, D3D textures and the real
LuaSocket/LuaSec path are not covered here.
