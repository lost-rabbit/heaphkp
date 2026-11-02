# HeaphKP: notes for the PhoenixXI addon review

Addon name: **heaphkp** (Ashita v4, Lua). Author: Heaph. Source: this repository.

## What it is

A linkshell DKP tool: standings, attendance ready checks, loot auctions, a loot log with screenshots, and HNM window
timers, all in one ImGui window. Optionally several members share one book through a small web service.

In-game screenshots of every tab, the moogle and the alert: [docs/screenshots](docs/screenshots) (also shown in the README).

## What it reads

| Source | Why |
|---|---|
| Incoming chat packet `0x017` (tell, party, linkshell) | Ready-check answers (`here`), bids (`bid 120`), balance requests (`!dkp`), invite codes. Each of these is a separate Settings switch. |
| Your own outgoing chat packet `0x0B5` | So `!event start <mob>` typed into LS/party by **you** runs the addon's own command. Nothing is sent or changed. |
| Battle message packet `0x029` (message 6 "defeats", 20 "falls to the ground") | To record a time of death. Chat text is never used for this, so a typed line cannot fake a kill. |
| Treasure pool packets `0x0D2` / `0x0D3` | Which item dropped and who won the lot, for the loot log. |
| Party/alliance list, your inventory and equipment, zone | Attendance counting; which linkshell items you have equipped and in which slot; the LS name from the item. |
| Your own chat log files (`chatlogs\<Name>_*.log`), once at load | Kills from the last 24 hours seen while the addon was off. Local files only. |

## What it writes / sends

- `config\addons\heaphkp\state.json`, rewritten every 5 s with the book's standings and timers, so other addons on the
  same PC can read them. Local file only.
- Files under `config\addons\heaphkp\` and a copy of a screenshot (taken with Ashita's own `/screenshot`) when a tracked
  drop lands, and only if the user is an officer or leader of the book. Screenshots can be turned off.
- Chat lines, every one of them optional and off-able in Settings: ready-check announcements (a timed post every N
  minutes **only while you have started a camp**), auction open/close lines, a ToD line when a tracked mob dies (only
  from officers, only while a camp is running), replies by tell (bid refused, balance) only to people already in the
  book. No line is ever sent in reaction to a monster's actions; the ToD line is a chat announcement after a kill the
  game reported, not an action.
- HTTPS to the sync server the user set in Settings, only for a linkshell book the user has shared: DKP entries, ToDs,
  prices, drop names and roles. No passwords, no account data, no packets, no file paths. The server is open source in
  `server/`.

## What it never does

- No actions: no packets to the game server, no targeting, abilities, items, gear swaps or movement.
- No automation that reacts to a monster. Timed posts are driven by the clock and only inside a camp the user started.
- No reading of memory beyond Ashita's public SDK (party, inventory, equipment, entity names and spawn flags).
- No modification of other addons or game files.

## Shared data, identity and privacy

- Sharing is opt-in per linkshell; only the LS owner (Linkshell item equipped) can turn it on. Members join with a
  one-use code, valid for one hour, made out to their character name and delivered by in-game tell to that character.
- Every change is stored under the name the sender's token was issued to, and any name inside the change is overwritten
  with it, so nobody can write as someone else. Admins see who has joined and when they last synced.
- Only the book's own linkshell hears its chat posts; the addon refuses to post if that LS is not equipped.
- A **SHARE TOD / DO NOT SHARE** switch stops a client from sending the ToDs it sees.
- Tokens are stored hashed on the server. The TLS connection verifies the server certificate.
- Outside tools (a Discord bot, a website) use API keys an admin makes in the window. A key is the identity
  `bot:<label>` on the server, never a character name, so a bot's writes are always visibly a bot's, and it is
  revoked like a member. Keys are stored hashed and rate limited. Nothing about the API touches the game client.

## Assets

- Moogle artwork: Heaph's own.
- Window card, chime: generated for this addon. No Square Enix textures or sounds are included.
- `assets/cacert.pem`: public root certificates, for the HTTPS check.

## How to try it without a linkshell

1. `/addon load heaphkp`, click the moogle.
2. Attendance tab: pick any mob, Start camp. A ready check opens; close it with the button. The DKP tab shows the tick.
3. ToDs tab: tick "Show every mob", pick one, "Killed now". The clock moogle starts counting down.
4. Settings: every chat feature can be switched off; "Post announcements" off makes the addon silent in chat.
