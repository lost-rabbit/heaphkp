# HeaphKP sync server

Cloudflare Worker + D1 that lets several HeaphKP clients (the `heaphkp` Ashita addon in
`C:\Games\PhoenixXI\addons\heaphkp`) share one DKP book per linkshell.

- `worker.js`: the API (`/register`, `/invite`, `/join`, `/sync`). Notes on roles are at the top of the file.
- `schema.sql`: the D1 tables.
- `wrangler.toml`: the Worker name and D1 binding. `database_id` is a placeholder until the database is created.

## Test locally (nothing goes online)

```
npx wrangler@4 d1 execute heaphkp-db --local --file=schema.sql
npx wrangler@4 dev --local --port 8799
```

The client test harness is in the session scratchpad `dkptest\` (`test_server.py`, `test_sync.py`).

## Deploy

Heaph's instance: `https://heaphkp.ialreadyforgotwhoiam.workers.dev` (Worker `heaphkp`, D1 `heaphkp-db`), deployed 2026-10-30. To run your own:

```
npx wrangler@4 d1 create heaphkp-db          # paste the id into wrangler.toml
npx wrangler@4 d1 execute heaphkp-db --remote --file=schema.sql --yes
npx wrangler@4 deploy
```

Then put the Worker URL in HeaphKP > Settings > Sync server (or change `DEFAULT_SERVER` in heaphkp.lua).

API for bots and other tools: see `../docs/API.md`.
Node lives at `C:\Program Files\nodejs` and isn't on PATH in the tool shells.

## Trust model

- **Owner check:** only a client with that LS's Linkshell item equipped (item 513) is offered "Turn on DKP". The
  server can't see the game, so it trusts the first registration. Fix disputes by hand in D1.
- **Tokens:** stored as SHA-256 hashes, one per character per LS. Removing someone's role deletes their tokens.
- **TLS:** the addon talks TLS with verify=none, because LuaSec has no Windows CA store.
