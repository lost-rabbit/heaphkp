--[[
* HeaphKP - linkshell DKP, auctions, attendance and HNM time-of-death tracking for PhoenixXI.
*
* Shared books: the LS owner (whoever has that LS's Linkshell item equipped) turns DKP on for the LS in the
* Linkshells tab. The book then lives on the sync server (the server\ folder of this repo), and the owner and
* admins invite people by name. Every change is an entry in a shared log that every client applies in order,
* so every officer sees the same standings. The server checks each change against the sender's role.
* A 'This PC only' book still works with no server at all.
*
* Everything is done from the window (on-screen DKP button, or /dkp). Chat is optional: Settings > Chat control
* turns each part on or off. With it on, everyone else can use linkshell, party or tells:
*     here                  answer a ready check
*     bid 120 / bid max     bid during an auction (in a tell, just "120" works)
*     !dkp                  get your balance by tell
*   Officers (only if "Officers can run things from chat" is on; roles set in Settings) can also use:
*     !camp start <mob>   !camp stop   !camp auto <mob>   (these also work when YOU type them in LS/party)
*     !auction <item> [min]   !close   !cancel   !rc   !tod <mob> [21:43|-15m]   !award <name> <price> <item>
*   Admins:  !adjust <name> <+/-n> [reason]   !undo
*
* What it does by itself:
*   - Every 30 min (Settings) while an event is running: ready check. Alliance members in your zone are counted
*     automatically, anyone else answers "here" within the window. Everyone present gets the tick DKP.
*   - Treasure pool drops from tracked HNMs/NMs (or priced items, or anything during an event): screenshot, copied to
*     config\addons\heaphkp\drops\, and logged with who lotted it.
*   - "X defeats <HNM>" sets that HNM's time of death and shows its window. A kill during an event pays the kill bonus.
*
* Data: config\addons\heaphkp\db.json (This PC only book), book_<ls>.json per shared LS, access.json (sync tokens,
* keep private). /hkp export writes CSVs next to them.
*
* Local commands: /dkp (window)  /dkp start <event>  /dkp stop  /dkp rc  /dkp auction <item> [min]  /dkp close
*   /dkp cancel  /dkp award <name> <price> <item>  /dkp add <name> <+/-n> [reason]  /dkp tod <mob> [now|21:43|-15m]
*   /dkp role <name> <admin|officer|member|none>  /dkp price <item> <min>  /dkp track <mob> <minHours> <maxHours>
*   /dkp undo  /dkp export
*
* Creation assisted by ADA.
]]--

addon.name    = 'heaphkp';
addon.author  = 'Heaph';
addon.version = '1.5.1';
addon.desc    = 'HeaphKP: linkshell DKP shared between officers, auctions, ready checks, drop screenshots, HNM windows.';
addon.link    = '';

require('common');
local imgui = require('imgui');
local json  = require('json');

local okData, HNM = pcall(require, 'hnm_data');
if (not okData) or (type(HNM) ~= 'table') then HNM = {}; end

local INSTALL = AshitaCore:GetInstallPath():gsub('\\$', '');
local ROOT    = INSTALL .. '\\config\\addons\\heaphkp';
local DBFILE  = ROOT .. '\\db.json';
local DROPDIR = ROOT .. '\\drops';
local SSDIR   = INSTALL .. '\\screenshots';
local TAG     = '\30\81[HeaphKP]\30\01 ';
local ACCESSFILE = ROOT .. '\\access.json';
local DEFAULT_SERVER = 'https://heaphkp.ialreadyforgotwhoiam.workers.dev';   -- Heaph's sync server; change in Settings > Sync server
local HK = {};               -- helpers and small state added after the main chunk filled up with locals

local ROLES = { 'member', 'officer', 'admin' };
local LEVEL = { none = 0, member = 1, viewer = 1, officer = 2, admin = 3, owner = 3 };
local SROLES = { 'member', 'viewer', 'officer', 'admin' };   -- roles in a shared book ('member' = no addon access)
local ACTIONS = {
    { key = 'bid',     label = 'Bid' },
    { key = 'here',    label = 'Answer ready check' },
    { key = 'balance', label = 'Ask balance (!dkp)' },
    { key = 'auction', label = 'Open / close auctions' },
    { key = 'award',   label = 'Award items' },
    { key = 'tod',     label = 'Set ToD' },
    { key = 'rc',      label = 'Call ready check' },
    { key = 'adjust',  label = 'Adjust DKP' },
    { key = 'undo',    label = 'Undo' },
};

---------------------------------------------------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------------------------------------------------
local function defaults()
    return {
        version = 1,
        cfg = {
            channel     = 'l',        -- where announcements go: l, l2, p
            tickMin     = 30,         -- minutes between ready checks
            rcWindow    = 120,        -- seconds to answer a ready check
            dkpPerTick  = 1,
            killBonus   = 5,
            bidSec      = 45,
            bidExtend   = 10,         -- a bid in the last N seconds puts the clock back to N
            increment   = 1,
            defaultMin  = 0,
            sealed      = false,      -- sealed auctions take bids by tell only and post nothing until close
            allowNeg    = false,
            openRoster  = true,       -- anyone who answers a ready check joins the roster
            announce    = true,
            replyTells  = true,
            todPost     = true,       -- post HNM ToDs to the channel
            chatHere    = true,       -- "here" in chat answers a ready check
            chatBids    = true,       -- "bid 120" in chat bids
            chatBalance = true,       -- "!dkp" in chat gets a balance tell
            chatCommands = false,     -- officers' !auction / !tod / ... from chat (off: the menu does it all)
            answerRollCall = true,    -- tell a keeper who asks "[DKP] Roll call" that you run HeaphKP
            showPill    = true,       -- the small on-screen DKP button
            shareTod    = true,       -- send the ToDs you see to your LS book
            theme       = 'ffxi',     -- window style: ffxi | midnight | parchment | crystal
            opacity     = 100,        -- window background, percent
            iconStyle   = 'clock',    -- clock = the moogle holding a countdown to the next known window; round = roundel
            iconSize    = 70,         -- before the 4K scale
            iconBob     = true,       -- the clock moogle bobs gently
            autoLead    = 10,         -- auto camps start this many minutes before the window opens
            endOnKill   = true,       -- end the event after the camp target dies...
            endAfterKill = 10,        -- ...this many minutes later (time to finish loot and bids)
            shotMode    = 'tracked',  -- tracked | all | off
            notifyOn    = true,       -- window alerts
            notifyLead  = 30,         -- minutes before a known window opens
            notifySound = true,
            notifyLS    = false,      -- also post window alerts to the channel
            need        = { bid = 'member', here = 'member', balance = 'member', auction = 'officer', award = 'officer',
                            tod = 'officer', rc = 'officer', adjust = 'admin', undo = 'admin' },
        },
        members = {}, perms = {}, prices = {}, custom = {}, tods = {}, autoCamp = {},
        history = {}, drops = {}, nextId = 1,
        event = nil, auction = nil, rc = nil,
        seq = 0, outbox = {}, sent = {}, live = {}, notified = {}, seen = {}, aliases = {}, keys = {},   -- sync state (shared books); seen = the registry
    };
end

local db = defaults();
local dirty, lastSave = false, 0;

local function merge(dst, src)
    for k, v in pairs(src) do
        if (type(v) == 'table') and (type(dst[k]) == 'table') and (k ~= 'members') then merge(dst[k], v);
        else dst[k] = v; end
    end
end

-- Books: 'local' = This PC only (db.json); every shared LS has its own book_<ls>.json.
local bookKey = 'local';
local access = { server = DEFAULT_SERVER, active = 'local', books = {} };   -- books[key] = { ls, name, token, role, ... }

-- ToDs are stored as UTC seconds, so every client already shows them in its own zone.
-- What can still differ is a PC clock that is off; each sync measures this PC against the server's clock
-- (access.clockOffset) and every os.time() here is corrected by it. This addon has its own Lua state in Ashita.
os.rawtime = os.rawtime or os.time;
os.time = function (t)
    if (t ~= nil) then return os.rawtime(t); end
    return os.rawtime() + math.floor(access.clockOffset or 0);
end

local function book_file(key) return (key == 'local') and DBFILE or ('%s\\book_%s.json'):format(ROOT, key); end

local function read_json(path)
    local f = io.open(path, 'r');
    if (f == nil) then return nil; end
    local raw = f:read('*a');
    f:close();
    local ok, t = pcall(json.decode, raw);
    return (ok and type(t) == 'table') and t or false;
end

local function write_json(path, t)
    local ok, raw = pcall(json.encode, t);
    if (not ok) then print(TAG .. 'save failed: ' .. tostring(raw)); return false; end
    local tmp = path .. '.tmp';
    local f = io.open(tmp, 'w');
    if (f == nil) then print(TAG .. 'cannot write ' .. tmp); return false; end
    f:write(raw);
    f:close();
    os.remove(path .. '.bak');
    os.rename(path, path .. '.bak');
    os.rename(tmp, path);
    return true;
end

local function load_access()
    local t = read_json(ACCESSFILE);
    if t then
        if (type(t.server) == 'string') and (t.server ~= '') then access.server = t.server; end   -- an empty saved value keeps the default
        access.active = t.active or 'local';
        access.books = t.books or {};
    end
end

-- access.json holds the sync tokens. Keep it private: anyone with it can act as you in that LS.
local function save_access() write_json(ACCESSFILE, access); end

local function load_db()
    local path = book_file(bookKey);
    local t = read_json(path);
    db = defaults();
    if t then merge(db, t);
    elseif (t == false) then
        print(TAG .. path .. ' could not be read; starting empty (the old file is kept as .bad).');
        os.rename(path, path .. '.bad');
    end
end

local function save_db()
    if write_json(book_file(bookKey), db) then dirty, lastSave = false, os.clock(); end
end

local function touch() dirty = true; end

-- Globally unique ids for history entries, drops and sync ops.
local idSeq = 0;
local function new_id()
    idSeq = idSeq + 1;
    local n = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or 'x';
    return ('%s-%x-%x-%x'):format(n, os.time(), idSeq, math.random(0, 0xFFFF));
end

local applying = false;   -- true while applying someone else's change, so it is not sent back
local syncSoon = nil;
local function synced() return bookKey ~= 'local'; end
local function read_only()
    local b = access.books[bookKey];
    return synced() and (b ~= nil) and ((b.role == 'viewer') or b.revoked);
end

-- Queue a change for the server (shared books only).
local function emit(kind, body)
    if (not synced()) or applying then return; end
    -- a viewer's client sends the ToDs
    -- it sees (the server accepts 'tod' from viewers); every other change still needs officer.
    local b = access.books[bookKey];
    if (b ~= nil) and b.revoked then return; end
    if read_only() and (kind ~= 'tod') then return; end
    if ((kind == 'tod') or (kind == 'tod_clear')) and (db.cfg.shareTod == false) then return; end   -- DO NOT SHARE
    local cid = new_id();
    if (type(body) == 'table') and (body.shot ~= nil) then   -- the picture's path is this PC's business
        local copy = {};
        for k2, v2 in pairs(body) do copy[k2] = v2; end
        copy.shot = nil;
        body = copy;
    end
    db.outbox[#db.outbox + 1] = { cid = cid, kind = kind, body = body };
    db.sent[cid] = true;
    syncSoon = os.clock() + 1.5;
    dirty = true;
end

---------------------------------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------------------------------
local function N(name)
    name = tostring(name or ''):gsub('%s', '');
    return name:sub(1, 1):upper() .. name:sub(2):lower();
end

local function me()
    local n = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0);
    return (n ~= nil and n ~= '') and N(n) or nil;
end

local function role_of(name)
    local r = db.perms[N(name)];
    if (N(name) == me()) and ((not synced()) or (r == nil)) then return 'admin'; end
    if (r == 'owner') then return 'admin'; end
    if (r == 'viewer') or (r == nil) then return 'member'; end
    return r;
end

local function allowed(name, action)
    return LEVEL[role_of(name)] >= LEVEL[db.cfg.need[action] or 'admin'];
end

local function member(name)
    local k = N(name);
    local m = db.members[k];
    if (m == nil) then
        m = { dkp = 0, earned = 0, spent = 0, ticks = 0, joined = os.time() };
        db.members[k] = m;
    end
    return m, k;
end

local function item_key(s) return tostring(s or ''):lower():gsub('^%s+', ''):gsub('%s+$', ''); end

local function item_name(id)
    local it = AshitaCore:GetResourceManager():GetItemById(id);
    if (it ~= nil) and (it.Name ~= nil) and (it.Name[1] ~= nil) and (it.Name[1] ~= '') then return it.Name[1]; end
    return ('item %d'):format(id);
end

local function clean(s)
    s = tostring(s or '');
    s = s:gsub('\30.', ''):gsub('\31.', ''):gsub('\127\49', ''):gsub('[\r\n]', '');
    return s;
end

local function dur(s)
    s = math.max(0, math.floor(s));
    local h, m, x = math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60;
    if (h > 0) then return ('%dh %02dm'):format(h, m); end
    return ('%d:%02d'):format(m, x);
end

local function clock(t) return (os.date('%a %I:%M %p', t):gsub(' 0', ' ')); end

-- This PC's time zone as players say it (PT, MT, CT, ET...), else UTC+/-N. Windows gives "Pacific Daylight Time".
local zoneCache = nil;
local function zone()
    if (zoneCache ~= nil) then return zoneCache; end
    local name = tostring(os.date('%Z') or '');
    for k, v in pairs({ Pacific = 'PT', Mountain = 'MT', Central = 'CT', Eastern = 'ET', Alaska = 'AKT', Hawaii = 'HT',
                        Atlantic = 'AT', Newfoundland = 'NT', ['GMT Standard'] = 'UK', ['W. Europe'] = 'CET', ['Central Europe'] = 'CET',
                        ['Romance'] = 'CET', ['AUS Eastern'] = 'AET', ['Tokyo'] = 'JST' }) do
        if name:find(k, 1, true) then zoneCache = v; return v; end
    end
    local now = os.rawtime();
    local u = os.date('!*t', now);
    u.isdst = os.date('*t', now).isdst;
    local off = (now - os.rawtime(u)) / 3600;
    zoneCache = (off == math.floor(off)) and ('UTC%+d'):format(off) or ('UTC%+.1f'):format(off);
    return zoneCache;
end

-- A time for an LS post: the poster's local time with their zone, plus a countdown that reads the same everywhere.
local function pclock(t)
    local rel = t - os.time();
    local h, m = math.floor(math.abs(rel) / 3600), math.floor(math.abs(rel) % 3600 / 60);
    local d = (h > 0) and ('%dh%02d'):format(h, m) or ('%dm'):format(m);
    return (('%s %s (%s %s)'):format(clock(t), zone(), (rel >= 0) and 'in' or '', (rel >= 0) and d or (d .. ' ago')):gsub('%(%s+', '('));
end
local function stamp(t) return (os.date('%m/%d %I:%M %p', t):gsub(' 0', ' ')); end

local function sorted_members()
    local out = {};
    for k, v in pairs(db.members) do out[#out + 1] = { name = k, m = v }; end
    table.sort(out, function (a, b)
        if (a.m.dkp ~= b.m.dkp) then return a.m.dkp > b.m.dkp; end
        return a.name < b.name;
    end);
    return out;
end

---------------------------------------------------------------------------------------------------------------------
-- Outgoing chat (queued, 1.6 s apart so the game's spam filter never trips)
---------------------------------------------------------------------------------------------------------------------
local outq, lastSend, lastTell = {}, 0, {};

local ls_guard;   -- set in the Linkshells section: may this post go out, and where (shared books)

local function post(msg)
    if (not db.cfg.announce) then print(TAG .. msg); return; end
    local ch, why = db.cfg.channel, nil;
    if (ls_guard ~= nil) then ch, why = ls_guard(); end
    if (ch == nil) then print(TAG .. ('(not posted: %s) %s'):format(why or '?', msg)); return; end
    outq[#outq + 1] = ('/%s [DKP] %s'):format(ch, msg:sub(1, 110));
end

local function tell(name, msg, force)
    if (N(name) == me()) then print(TAG .. msg); return; end
    if (not db.cfg.replyTells) and (not force) then return; end
    -- never an auto-responder to strangers: only names in the roster or with access get a reply
    if (not force) and (db.members[N(name)] == nil) and (db.perms[N(name)] == nil) then return; end
    local now = os.clock();
    if (now - (lastTell[name] or -99)) < 3 then return; end
    lastTell[name] = now;
    outq[#outq + 1] = ('/t %s [DKP] %s'):format(name, msg:sub(1, 110));
end

local function pump()
    if (#outq == 0) or ((os.clock() - lastSend) < 1.6) then return; end
    AshitaCore:GetChatManager():QueueCommand(1, table.remove(outq, 1));
    lastSend = os.clock();
end

---------------------------------------------------------------------------------------------------------------------
-- Ledger: every DKP change is a history entry with its deltas, so any of it can be undone.
---------------------------------------------------------------------------------------------------------------------
local recIds = {};   -- history ids already in this book

local function index_history()
    recIds = {};
    for _, e in ipairs(db.history) do if (e.id ~= nil) then recIds[e.id] = true; end end
end

local function apply_rec(entry)
    if (entry.id ~= nil) and recIds[entry.id] then return; end
    if (entry.id ~= nil) then recIds[entry.id] = true; end
    for _, d in ipairs(entry.deltas or {}) do
        local m = member(d.n);
        m.dkp = m.dkp + d.d;
        if (d.d > 0) then m.earned = m.earned + d.d; else m.spent = m.spent - d.d; end
        if (entry.kind == 'tick') then m.ticks = m.ticks + 1; m.last = entry.t; end
    end
    if (entry.kind == 'win') and (entry.drop ~= nil) then
        local want = (db.aliases or {})[entry.drop] or entry.drop;
        for _, dr in ipairs(db.drops) do
            if (dr.id == want) then dr.awarded, dr.price = entry.deltas[1].n, -entry.deltas[1].d; end
        end
    end
    db.history[#db.history + 1] = entry;
    touch();
end

local function record(entry)
    entry.id = new_id();
    entry.t = entry.t or os.time();
    apply_rec(entry);
    emit('rec', entry);
    return entry;
end

local function apply_undo(e)
    if e.undone then return; end
    for _, d in ipairs(e.deltas or {}) do
        local m = member(d.n);
        m.dkp = m.dkp - d.d;
        if (d.d > 0) then m.earned = m.earned - d.d; else m.spent = m.spent + d.d; end
        if (e.kind == 'tick') then m.ticks = math.max(0, m.ticks - 1); end
    end
    e.undone = true;
    if (e.drop ~= nil) and (e.kind == 'win') then
        for _, dr in ipairs(db.drops) do if (dr.id == e.drop) then dr.awarded, dr.price = nil, nil; end end
    end
    touch();
end

local function undo_last(by)
    for i = #db.history, 1, -1 do
        local e = db.history[i];
        if (not e.undone) and (e.deltas ~= nil) and (#e.deltas > 0) then
            apply_undo(e);
            emit('undo', { id = e.id });
            record({ kind = 'undo', by = by, text = 'undid: ' .. (e.text or e.kind) });
            return e;
        end
    end
    return nil;
end

-- Book edits that also go to the server.
local build_mobs_ref;   -- set once build_mobs exists

local function add_member(name)
    local _, k = member(name);
    emit('member', { n = k });
    return k;
end

local function remove_member(k)
    db.members[k] = nil;
    if (not synced()) then db.perms[k] = nil; end
    emit('member_rm', { n = k });
    touch();
end

-- Local books: member/officer/admin for chat control. Shared books: the server's roles (member = no addon access).
local function set_role(name, r)
    local k = N(name);
    if synced() then
        db.perms[k] = (r ~= 'member' and r ~= 'none') and r or nil;
        emit('role', { n = k, r = (r == 'member') and 'none' or r });
    else
        db.perms[k] = (r ~= 'member' and r ~= 'none') and r or nil;
    end
    touch();
end

local function set_price(k, name, min)
    db.prices[k] = { name = name, min = min };
    emit('price', { k = k, name = name, min = min });
    touch();
end

local function del_price(k)
    db.prices[k] = nil;
    emit('price_rm', { k = k });
    touch();
end

local function set_custom(name, minS, maxS)
    db.custom[name] = { minS = minS, maxS = maxS };
    emit('custom', { name = name, minS = minS, maxS = maxS });
    if build_mobs_ref then build_mobs_ref(); end
    touch();
end

local function del_custom(name)
    db.custom[name] = nil;
    emit('custom_rm', { name = name });
    if build_mobs_ref then build_mobs_ref(); end
    touch();
end

local function clear_tod(key)
    db.tods[key] = nil;
    emit('tod_clear', { key = key });
    touch();
end

local function del_drop(id)
    for i, x in ipairs(db.drops) do if (x.id == id) then table.remove(db.drops, i); break; end end
    emit('drop_rm', { id = id });
    touch();
end

local function adjust(name, amount, reason, by)
    local _, k = member(name);
    return record({ kind = 'adjust', by = by, deltas = { { n = k, d = amount } },
        text = ('%s %+d%s'):format(k, amount, (reason and reason ~= '') and (' (' .. reason .. ')') or '') });
end

---------------------------------------------------------------------------------------------------------------------
-- Alliance snapshot
---------------------------------------------------------------------------------------------------------------------
local function alliance_here()
    local p = AshitaCore:GetMemoryManager():GetParty();
    local zone = p:GetMemberZone(0);
    local out = {};
    for i = 0, 17 do
        if (p:GetMemberIsActive(i) == 1) then
            local n = p:GetMemberName(i);
            if (n ~= nil) and (n ~= '') and (p:GetMemberZone(i) == zone) then out[N(n)] = true; end
        end
    end
    return out;
end

---------------------------------------------------------------------------------------------------------------------
-- Events and ready checks
---------------------------------------------------------------------------------------------------------------------
local function open_rc(by)
    if (db.rc ~= nil) then return false, 'a ready check is already open'; end
    local ev = db.event;
    local n = ev and (ev.ticks + 1) or 0;
    db.rc = { n = n, opened = os.time(), closes = os.time() + db.cfg.rcWindow, by = by, replied = {}, auto = alliance_here() };
    local where = (db.cfg.channel == 'p') and 'party' or 'LS';
    if db.cfg.chatHere then
        post(('Ready check%s%s: say "here" in %s or /tell %s within %s.'):format(
            ev and (' #' .. n) or '', ev and (' - ' .. ev.name) or '', where, me() or 'me', dur(db.cfg.rcWindow)));
    else
        post(('Ready check%s%s: taking attendance.'):format(ev and (' #' .. n) or '', ev and (' - ' .. ev.name) or ''));
    end
    touch();
    return true;
end

local function close_rc()
    local rc = db.rc;
    if (rc == nil) then return; end
    db.rc = nil;
    local present = {};
    for k in pairs(rc.auto) do present[k] = true; end
    for k in pairs(alliance_here()) do present[k] = true; end
    for k in pairs(rc.replied) do present[k] = true; end
    for k in pairs(rc.excluded or {}) do present[k] = nil; end   -- unticked in the menu
    local names = {};
    for k in pairs(present) do names[#names + 1] = k; end
    table.sort(names);
    local ev = db.event;
    if (ev == nil) then
        record({ kind = 'check', by = rc.by, names = names, text = ('ready check: %d present'):format(#names) });
        post(('Ready check closed: %d present.'):format(#names));
        return;
    end
    ev.ticks = ev.ticks + 1;
    local deltas = {};
    for _, n in ipairs(names) do deltas[#deltas + 1] = { n = n, d = db.cfg.dkpPerTick }; end
    record({ kind = 'tick', by = rc.by, event = ev.name, names = names, deltas = deltas,
        text = ('%s tick #%d: %d present, +%d each'):format(ev.name, ev.ticks, #names, db.cfg.dkpPerTick) });
    post(('Tick #%d (%s): %d present, +%d DKP each.'):format(ev.ticks, ev.name, #names, db.cfg.dkpPerTick));
end

-- `mob` is the timer key being camped (optional): its kill ends the event, and the header shows its window.
local function start_event(name, by, mob)
    if (db.event ~= nil) then return false, ('%s is already running'):format(db.event.name); end
    name = (name and name ~= '') and name or (mob and (mob .. ' camp')) or 'Camp';
    db.event = { name = name, mob = mob, started = os.time(), ticks = 0, nextRc = os.time() + db.cfg.tickMin * 60, by = by };
    record({ kind = 'event', by = by, event = name, text = 'started ' .. name });
    post(('%s started. Ready check now and every %d min.'):format(name, db.cfg.tickMin));
    open_rc(by);
    return true;
end

local function stop_event(by)
    local ev = db.event;
    if (ev == nil) then return false, 'no event running'; end
    if (db.rc ~= nil) then close_rc(); end
    db.event = nil;
    record({ kind = 'event', by = by, event = ev.name,
        text = ('ended %s after %s, %d ticks'):format(ev.name, dur(os.time() - ev.started), ev.ticks) });
    post(('%s ended: %d ticks over %s.'):format(ev.name, ev.ticks, dur(os.time() - ev.started)));
    return true;
end

---------------------------------------------------------------------------------------------------------------------
-- Auctions
---------------------------------------------------------------------------------------------------------------------
local function price_for(item)
    local p = db.prices[item_key(item)];
    return p and p.min or db.cfg.defaultMin;
end

local function start_auction(item, min, by, dropId)
    if (db.auction ~= nil) then return false, ('bidding on %s is still open'):format(db.auction.item); end
    if (item == nil) or (item == '') then return false, 'which item?'; end
    min = tonumber(min) or price_for(item);
    if (dropId == nil) then   -- tie it to the newest unawarded drop of that item, if there is one
        for i = #db.drops, 1, -1 do
            local d = db.drops[i];
            if (d.awarded == nil) and (item_key(d.item) == item_key(item)) and (os.time() - d.t < 6 * 3600) then dropId = d.id; break; end
        end
    end
    db.auction = { item = item, min = min, ends = os.time() + db.cfg.bidSec, by = by, drop = dropId, bids = {},
                   sealed = db.cfg.sealed, warned = false };
    if db.cfg.sealed then
        post(('Sealed bids: %s, min %d DKP, %ds. /tell %s <amount>.'):format(item, min, db.cfg.bidSec, me() or 'me'));
    else
        post(('Bidding open: %s, min %d DKP, %ds. Say "bid <amount>".'):format(item, min, db.cfg.bidSec));
    end
    touch();
    return true;
end

local function high_bid(a)
    a = a or db.auction;
    local best = nil;
    for _, b in ipairs(a and a.bids or {}) do
        if (not b.void) and ((best == nil) or (b.amt > best.amt)) then best = b; end   -- ties keep the earlier bid
    end
    return best;
end

local announceHigh = 0;

-- Returns true, or false and the reason. `via` is a chat kind or 'menu'.
local function place_bid(name, amt, via)
    local a = db.auction;
    if (a == nil) then return false, 'No auction is open.'; end
    name = N(name);
    local m = db.members[name];
    if (m == nil) then return false, ("%s isn't on the DKP roster yet."):format(name); end
    if (amt == 'max') then amt = m.dkp; end
    amt = math.floor(tonumber(amt) or -1);
    if (amt < a.min) then return false, ('%s minimum is %d.'):format(a.item, a.min); end
    if (not db.cfg.allowNeg) and (amt > m.dkp) then return false, ('%s has %d DKP.'):format(name, m.dkp); end
    local best = high_bid();
    if (not a.sealed) and (best ~= nil) and (best.name ~= name) and (amt < best.amt + db.cfg.increment) then
        return false, ('High bid is %d. Bid at least %d.'):format(best.amt, best.amt + db.cfg.increment);
    end
    for _, b in ipairs(a.bids) do if (b.name == name) then b.void = true; end end   -- one live bid per person
    a.bids[#a.bids + 1] = { name = name, amt = amt, t = os.time(), via = via };
    if (a.ends - os.time() < db.cfg.bidExtend) then a.ends = os.time() + db.cfg.bidExtend; end
    if a.sealed then
        if (via ~= 'menu') then tell(name, ('Sealed bid of %d on %s received.'):format(amt, a.item)); end
    else
        announceHigh = os.clock() + 2.5;
    end
    touch();
    return true;
end

local function award(name, price, item, by, dropId)
    local _, k = member(name);
    price = math.floor(tonumber(price) or 0);
    local shot = nil;
    for _, dr in ipairs(db.drops) do if (dr.id == dropId) then shot = dr.shot; end end
    return record({ kind = 'win', by = by, item = item, drop = dropId, shot = shot, deltas = { { n = k, d = -price } },
        event = db.event and db.event.name, text = ('%s won %s for %d'):format(k, item, price) });
end

local function close_auction(by, cancel)
    local a = db.auction;
    if (a == nil) then return false, 'no auction open'; end
    db.auction = nil;
    touch();
    if cancel then post(('Bidding on %s cancelled.'):format(a.item)); return true; end
    local best = high_bid(a);
    if (best == nil) then
        record({ kind = 'nobid', by = by, item = a.item, text = 'no bids on ' .. a.item });
        post(('No bids on %s. Free lot.'):format(a.item));
        return true;
    end
    award(best.name, best.amt, a.item, by or a.by, a.drop);
    post(('%s goes to %s for %d DKP.'):format(a.item, best.name, best.amt));
    return true;
end

---------------------------------------------------------------------------------------------------------------------
-- HNM / NM timers
---------------------------------------------------------------------------------------------------------------------
local mobs, mobIndex = {}, {};

local function build_mobs()
    mobs, mobIndex = {}, {};
    local function add(e, custom)
        local k = (e.sharesWith or e.name);
        mobIndex[e.name:lower()] = k;
        if (e.sharesWith == nil) then mobs[#mobs + 1] = { e = e, key = k, custom = custom }; end
    end
    for _, e in ipairs(HNM) do if (type(e) == 'table') and (e.name ~= nil) then add(e, false); end end
    for name, c in pairs(db.custom) do
        if (mobIndex[name:lower()] == nil) then add({ name = name, minS = c.minS, maxS = c.maxS, group = 'Custom', zone = c.zone or '' }, true); end
    end
end

build_mobs_ref = function () build_mobs(); end

local function mob_def(key)
    for _, m in ipairs(mobs) do if (m.key == key) then return m.e; end end
    return nil;
end

-- Short names people type: !event start ka
HK.ALIAS = {
    ka = 'King Arthro', kb = 'King Behemoth', behe = 'Behemoth', faf = 'Fafnir', nid = 'Nidhogg', ada = 'Adamantoise',
    aspid = 'Aspidochelone', asp = 'Aspidochelone', sim = 'Simurgh', serk = 'Serket', tia = 'Tiamat', jorm = 'Jormungand',
    kv = 'King Vinegarroon', cerb = 'Cerberus', khim = 'Khimaira', jol = 'Jailer of Love', shiki = 'Shikigami Weapon',
    bs = 'Bloodsucker', kreu = 'Kreutzet', xol = 'Xolotl', ya = 'Yagudo Avatar', tzee = 'Tzee Xicu the Manifest',
    oo = 'Orcish Overlord', bak = 'Overlord Bakgodek', dq = 'Diamond Quadav', zadha = "Za'Dha Adamantking",
    dl = 'Dynamis Lord', sc = 'Steam Cleaner', mg = 'Mother Globe', zip = 'Zipacna', ulli = 'Ullikummi', jot = 'Jailer of Temperance',
    jof = 'Jailer of Fortitude', joh = 'Jailer of Hope', joj = 'Jailer of Justice', jop = 'Jailer of Prudence', jofa = 'Jailer of Faith',
    cr = 'Cactrot Rapido', ash = 'Ash Dragon', pu = 'Proto-Ultima', po = 'Proto-Omega',
};
local function resolve_mob(text)
    text = tostring(text or ''):lower():gsub('^the ', ''):gsub('^%s+', ''):gsub('%s+$', '');
    if (HK.ALIAS[text] ~= nil) and (mobIndex[HK.ALIAS[text]:lower()] ~= nil) then return mobIndex[HK.ALIAS[text]:lower()]; end
    if (mobIndex[text] ~= nil) then return mobIndex[text]; end
    for n, k in pairs(mobIndex) do if (n:find(text, 1, true) == 1) then return k; end end
    return nil;
end

-- "now", "21:43", "9:43pm", "-15m", "-2h" -> epoch seconds
local function parse_when(s)
    s = tostring(s or 'now'):lower();
    if (s == '' or s == 'now') then return os.time(); end
    local n, u = s:match('^%-(%d+)([mh]?)$');
    if n then return os.time() - tonumber(n) * ((u == 'h') and 3600 or 60); end
    local h, mi, ap = s:match('^(%d%d?):(%d%d)%s*([ap]?)m?$');
    if h then
        h, mi = tonumber(h), tonumber(mi);
        if (ap == 'p') and (h < 12) then h = h + 12; end
        if (ap == 'a') and (h == 12) then h = 0; end
        local d = os.date('*t');
        d.hour, d.min, d.sec = h, mi, 0;
        local t = os.time(d);
        if (t > os.time() + 60) then t = t - 86400; end
        return t;
    end
    return nil;
end

local function window_text(e, tod, now)
    if (e == nil) or (e.minS == nil) then return 'no timer', 'dim'; end
    local open, close = tod + e.minS, tod + (e.maxS or e.minS);
    if (now < open) then return ('opens %s (in %s)'):format(clock(open), dur(open - now)), 'wait'; end
    if (now <= close) then
        if (e.windowS ~= nil) and (e.windowS > 0) then
            local total = math.floor((close - open) / e.windowS) + 1;
            local w = math.floor((now - open) / e.windowS) + 1;
            local nextW = open + w * e.windowS;
            if (w < total) then return ('window %d/%d, next in %s'):format(w, total, dur(nextW - now)), 'open'; end
            return ('last window %d/%d'):format(w, total), 'open';
        end
        return ('OPEN, closes in %s'):format(dur(close - now)), 'open';
    end
    return ('window closed %s ago'):format(dur(now - close)), 'late';
end

local function set_tod(key, t, by, form, silent)
    local e = mob_def(key);
    local prev = db.tods[key];
    if (prev ~= nil) and (math.abs(prev.t - t) < 90) then return; end   -- the game repeats some lines
    local hq = (e ~= nil) and (e.hq ~= nil) and (form == e.hq);
    local streak = (prev and prev.streak or 0);
    if (form ~= nil) then streak = hq and 0 or (streak + 1); end
    db.tods[key] = { t = t, by = by, form = form or (prev and prev.form) or key, streak = streak };
    emit('tod', { key = key, v = db.tods[key] });
    local entry = { kind = 'tod', by = by, mob = key, text = ('%s ToD %s'):format(form or key, stamp(t)), id = new_id(), t = os.time() };
    apply_rec(entry);
    if (db.cfg.shareTod ~= false) then emit('rec', entry); end
    -- only officers put ToDs in the LS. In a shared book that is your server role (officer / admin /
    -- owner); everyone else still records the ToD on their own screen. The This-PC book is yours, so it always posts.
    local myRole = db.perms[me() or ''];
    local officer = (not synced()) or (myRole == 'officer') or (myRole == 'admin') or (myRole == 'owner');
    -- ...and only while an event is running.
    if officer and (db.event ~= nil) and db.cfg.todPost and (not silent) and (e ~= nil) and (e.minS ~= nil) then
        local auto =(db.autoCamp[key] ~= nil) and (' Camp auto-starts %s.'):format(clock(t + e.minS - db.cfg.autoLead * 60)) or '';
        post(('%s ToD %s %s. Window opens %s.%s'):format(form or key, clock(t), zone(), pclock(t + e.minS), auto));
    end
end

HK.norm = function (x) return (tostring(x or ''):lower():gsub('[^%w]', '')); end
HK.zone_name = function ()
    local ok, n = pcall(function ()
        local z = AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
        return AshitaCore:GetResourceManager():GetString('zones.names', z);
    end);
    return (ok and type(n) == 'string' and n ~= '') and n or nil;
end
HK.killSeen = {};
local function on_kill(mobName)
    local key = mobIndex[mobName:lower()];
    if (key == nil) then return; end
    local e = mob_def(key);
    if (e ~= nil) and (e.zone ~= nil) then   -- a same-name mob in another zone is not this timer
        local zn = HK.zone_name();
        if (zn ~= nil) and (HK.norm(zn) ~= HK.norm(e.zone)) then return; end
    end
    if (e ~= nil) and (e.count or 1) > 1 then   -- e.g. Jailer of Prudence: two mobs, the timer starts at the last death
        local ks = HK.killSeen[key] or { n = 0, at = 0 };
        if (os.time() - ks.at > 1800) then ks.n = 0; end
        ks.n, ks.at = ks.n + 1, os.time();
        HK.killSeen[key] = ks;
        if (ks.n < e.count) then return; end
        HK.killSeen[key] = nil;
    end
    local prev = db.tods[key];
    if (prev ~= nil) and (os.time() - prev.t < 90) then return; end
    set_tod(key, os.time(), 'auto', mobName);
    local ev = db.event;
    if (ev ~= nil) and (db.cfg.killBonus > 0) then
        local deltas, names = {}, {};
        for n in pairs(alliance_here()) do names[#names + 1] = n; deltas[#deltas + 1] = { n = n, d = db.cfg.killBonus }; end
        table.sort(names);
        record({ kind = 'kill', by = 'auto', mob = mobName, event = ev.name, names = names, deltas = deltas,
            text = ('%s killed: +%d to %d present'):format(mobName, db.cfg.killBonus, #names) });
        post(('%s down! +%d DKP to the %d here.'):format(mobName, db.cfg.killBonus, #names));
    end
    if (ev ~= nil) and (ev.mob == key) and db.cfg.endOnKill and (ev.killedAt == nil) then
        ev.killedAt = os.time();
        if (db.cfg.endAfterKill > 0) then post(('%s ends in %d min.'):format(ev.name, db.cfg.endAfterKill)); end
        touch();
    end
end

-- When the next auto camp for `key` starts (nil if it can't: no ToD, no timer, or the window already closed).
local function auto_start_time(key)
    local e, t = mob_def(key), db.tods[key];
    if (e == nil) or (t == nil) or (e.minS == nil) or e.forced then return nil; end
    if (os.time() > t.t + (e.maxS or e.minS)) then return nil; end
    return t.t + e.minS - db.cfg.autoLead * 60;
end

local function set_auto(key, on, by)
    if on then local cur = db.autoCamp[key] or {}; cur.by = me(); db.autoCamp[key] = cur; else db.autoCamp[key] = nil; end
    emit('auto', { key = key, on = on, by = me() });
    touch();
    local at = on and auto_start_time(key);
    if (not on) then return ('%s auto camp off.'):format(key); end
    if at then return ('%s camp starts by itself %s.'):format(key, clock(at)); end
    return ('%s camp will start by itself once it has a ToD.'):format(key);
end

---------------------------------------------------------------------------------------------------------------------
-- Drops and screenshots
---------------------------------------------------------------------------------------------------------------------
local poolSlot = {};      -- treasure pool slot -> drop id
local shot = nil;         -- pending screenshot { at, ids, before, fired, tries }
local hideUntil = 0;

local function png_set()
    local s = {};
    for _, f in ipairs(ashita.fs.get_dir(SSDIR, '.*\\.png', true) or {}) do s[f] = true; end
    return s;
end

local function copy_file(src, dst)
    local i = io.open(src, 'rb');
    if (i == nil) then return false; end
    local data = i:read('*a');
    i:close();
    local o = io.open(dst, 'wb');
    if (o == nil) then return false; end
    o:write(data);
    o:close();
    return true;
end

local function want_shot(mobName, itemName)
    local mode = db.cfg.shotMode;
    if (mode == 'off') then return false; end
    if (mode == 'all') then return true; end
    return (db.event ~= nil) or (mobIndex[(mobName or ''):lower()] ~= nil) or (db.prices[item_key(itemName)] ~= nil);
end

local function on_drop(itemId, slot, mobIndexId)
    poolSlot[slot] = nil;   -- whatever was in this slot before is gone
    local item = item_name(itemId);
    local mob = '';
    if (mobIndexId ~= nil) and (mobIndexId > 0) then mob = AshitaCore:GetMemoryManager():GetEntity():GetName(mobIndexId) or ''; end
    local last = db.drops[#db.drops];
    if (last ~= nil) and (last.slot == slot) and (last.item == item) and (os.time() - last.t < 60) then return; end
    if (mobIndex[mob:lower()] == nil) and (db.event == nil) and (db.prices[item_key(item)] == nil) and (db.cfg.shotMode ~= 'all') then
        return;   -- not linkshell loot; keep the log to what matters
    end
    local d = { id = new_id(), t = os.time(), item = item, itemId = itemId, mob = mob, slot = slot,
                event = db.event and db.event.name, seenBy = me() };
    db.drops[#db.drops + 1] = d;
    emit('drop', d);
    while (#db.drops > 500) do table.remove(db.drops, 1); end
    poolSlot[slot] = d.id;
    touch();
    print(TAG .. ('%s dropped %s.'):format(mob ~= '' and mob or 'Something', item));
    if want_shot(mob, item) then
        if (shot == nil) then
            shot = { at = os.clock() + 0.8, ids = { d.id }, before = png_set(), fired = false, tries = 0 };
        elseif (not shot.fired) then
            shot.ids[#shot.ids + 1] = d.id;
        end
    end
end

local function drop_by_id(id)
    id = (db.aliases or {})[id] or id;
    for _, d in ipairs(db.drops) do if (d.id == id) then return d; end end
    return nil;
end

local function shot_tick()
    if (shot == nil) then return; end
    local now = os.clock();
    if (not shot.fired) then
        if (now >= shot.at - 0.3) then hideUntil = now + 1.5; end   -- keep this window out of the picture
        if (now >= shot.at) then
            AshitaCore:GetChatManager():QueueCommand(1, '/screenshot');
            shot.fired, shot.next = true, now + 1.5;
        end
        return;
    end
    if (now < shot.next) then return; end
    shot.tries = shot.tries + 1;
    local found = nil;
    for f in pairs(png_set()) do if (not shot.before[f]) then found = f; end end
    if (found ~= nil) then
        local first = drop_by_id(shot.ids[1]);
        local label = first and first.item:gsub('[^%w]+', '_') or 'drop';
        local dst = ('%s\\%s_%s.png'):format(DROPDIR, os.date('%Y%m%d_%H%M%S'), label);
        if (not copy_file(SSDIR .. '\\' .. found, dst)) then dst = SSDIR .. '\\' .. found; end
        for _, id in ipairs(shot.ids) do
            local d = drop_by_id(id);
            if (d ~= nil) then d.shot = dst; end
        end
        touch();
        shot = nil;
    elseif (shot.tries >= 4) then
        print(TAG .. 'screenshot did not appear (is the screenshot plugin loaded?)');
        shot = nil;
    else
        shot.next = now + 1.5;
    end
end

local function on_lot_result(slot, winner)
    local id = poolSlot[slot];
    poolSlot[slot] = nil;
    local d = id and drop_by_id(id);
    if (d == nil) then return; end
    d.lotted = winner;
    emit('drop_upd', { id = d.id, lotted = winner });
    if (d.awarded ~= nil) and (d.awarded ~= N(winner)) then
        print(TAG .. ('%s was awarded to %s but %s lotted it.'):format(d.item, d.awarded, winner));
    end
    touch();
end

---------------------------------------------------------------------------------------------------------------------
-- Commands (shared by /dkp and remote chat)
---------------------------------------------------------------------------------------------------------------------
local function reply(to, msg)
    if (to == nil) or (N(to) == me()) then print(TAG .. msg); else tell(to, msg); end
end

local function split_tod(rest)
    local words = {};
    for w in rest:gmatch('%S+') do words[#words + 1] = w; end
    local when = nil;
    if (#words > 1) and (parse_when(words[#words]) ~= nil) and (words[#words]:match('%d') or words[#words]:lower() == 'now') then
        when = table.remove(words);
    end
    return table.concat(words, ' '), when;
end

local KNOWN = { camp = 1, event = 1, help = 1, commands = 1, backfill = 1, invite = 1, rollcall = 1, start = 1, stop = 1, rc = 1, auction = 1, bid = 1, close = 1, cancel = 1, award = 1, add = 1, adjust = 1,
                undo = 1, tod = 1, role = 1, price = 1, track = 1, export = 1 };

HK.approve_join = function (name, role)
    HK.joinReq = HK.joinReq or {};
    add_member(name);
    send_invite(name, role or 'viewer');
    HK.joinReq[name] = nil;
end

HK.target_name = function ()
    local ok, name = pcall(function ()
        local t = AshitaCore:GetMemoryManager():GetTarget();
        local idx = t:GetTargetIndex(t:GetIsSubTargetActive());
        if (idx == nil) or (idx == 0) then return nil; end
        local ent = AshitaCore:GetMemoryManager():GetEntity();
        local flags = ent:GetSpawnFlags(idx) or 0;
        if (flags % 2 ~= 1) then return nil; end   -- 0x01 = a player character
        local n = ent:GetName(idx);
        return (n ~= nil and n ~= '' and n ~= me()) and N(n) or nil;
    end);
    return ok and name or nil;
end

HK.help_lines = function (chat)
    if chat then
        return {
            '!event start <mob> | !event stop | !event auto <mob> | !rc | !auction <item> [min] | !close',
            'bid <n> / bid max | here | !dkp | !join heaphkp (ask to be added) | aliases: ka kb faf nid sim serk tia jorm kv cerb khim',
        };
    end
    return {
        '/hkp (window) | start <event> | stop | rc | event start <mob> | event stop | event auto <mob>',
        'auction <item> [min] | close | cancel | award <name> <price> <item> | add <name> <+/-n> [why]',
        'tod <mob> [now|21:43|-15m] | role <name> <role> | price <item> <min> | track <mob> <minH> <maxH>',
        'invite <name|t> [viewer|officer|admin] (t = your target) | rollcall [t] (who has HeaphKP) | undo | export | backfill | help',
        'Mob aliases: ka kb behe faf nid ada aspid sim serk tia jorm kv cerb khim jol shiki bs kreu xol ya tzee oo dq dl',
    };
end

-- ToDs from your own chat log for the last 24 hours (Ashita's logs addon writes chatlogs\<Name>_YYYY.MM.DD.log).
-- Only lines the game wrote ("[hh:mm:ss] Name defeats the Mob." right after the time stamp) count; player chat never
-- starts that way. Found ToDs are set silently (no LS post) and only when newer than what the book has.
HK.backfill = function (verbose)
    local my = me();
    if (my == nil) then return 0; end
    local now, found = os.time(), 0;
    for _, back in ipairs({ 0, 86400 }) do
        local day = now - back;
        local path = ('%s\\chatlogs\\%s_%s.log'):format(INSTALL, my, os.date('%Y.%m.%d', day));
        local f = io.open(path, 'r');
        if (f ~= nil) then
            local d = os.date('*t', day);
            for line in f:lines() do
                local hh, mm, ss, rest = line:match('^%[(%d%d):(%d%d):(%d%d)%] (.+)$');
                if (hh ~= nil) then
                    local mob = rest:match('^%a+ defeats (.-)%.%s*$') or rest:match('^(.-) falls to the ground%.%s*$');
                    if (mob ~= nil) then
                        mob = mob:gsub('^[Tt]he ', '');
                        local key = mobIndex[mob:lower()];
                        if (key ~= nil) then
                            local t = os.time({ year = d.year, month = d.month, day = d.day, hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) });
                            local prev = db.tods[key];
                            if (t ~= nil) and (now - t <= 86400) and (t <= now + 60) and ((prev == nil) or (t > prev.t + 90)) then
                                set_tod(key, t, 'log', mob, true);
                                found = found + 1;
                            end
                        end
                    end
                end
            end
            f:close();
        end
    end
    if verbose or (found > 0) then print(TAG .. ('Chat log check: %d ToD%s from the last 24 hours.'):format(found, found == 1 and '' or 's')); end
    return found;
end

-- config\addons\heaphkp\state.json, rewritten every 5 s: what other addons (and anything else on this PC) can
-- read. Commands are the write side: any addon can queue '/hkp tod ka now', '/hkp add Name 5 why', '/hkp event start kb'.
HK.write_state = function ()
    local now = os.time();
    local bk = access.books[bookKey];   -- book() is defined further down the file
    local st = { version = addon.version, time = now, me = me(), book = { name = bk and bk.ls or 'This PC only', role = bk and bk.role or 'admin', shared = synced() } };
    st.standings = {};
    for _, r in ipairs(sorted_members()) do st.standings[#st.standings + 1] = { name = r.name, dkp = r.m.dkp, earned = r.m.earned, spent = r.m.spent, ticks = r.m.ticks }; end
    st.timers = {};
    for _, m in ipairs(mobs) do
        local t, e = db.tods[m.key], m.e;
        if (t ~= nil) then
            local row = { mob = m.key, form = t.form, zone = e.zone or '', tod = t.t, by = t.by };
            if (e.minS ~= nil) and (not e.forced) then
                row.opens, row.closes = t.t + e.minS, t.t + (e.maxS or e.minS);
                local txt, state = window_text(e, t.t, now);
                row.state, row.text = ({ wait = 'waiting', open = 'open', late = 'closed', dim = 'no-timer' })[state] or state, txt;
            else row.state = e.forced and 'forced' or 'no-timer'; end
            st.timers[#st.timers + 1] = row;
        end
    end
    table.sort(st.timers, function (a, b) return (a.opens or 1e12) < (b.opens or 1e12); end);
    local ev, rc, a = db.event, db.rc, db.auction;
    if ev then st.event = { name = ev.name, mob = ev.mob, started = ev.started, ticks = ev.ticks, nextRc = ev.nextRc }; end
    if rc then st.readyCheck = { closes = rc.closes, answered = (function () local c = 0; for _ in pairs(rc.replied) do c = c + 1; end; return c; end)() }; end
    if a then
        local best = high_bid(a);
        st.auction = { item = a.item, min = a.min, ends = a.ends, sealed = a.sealed, high = (not a.sealed and best) and best.amt or nil, bidder = (not a.sealed and best) and best.name or nil };
    end
    st.drops, st.history = {}, {};
    for i = math.max(1, #db.drops - 19), #db.drops do local d = db.drops[i]; st.drops[#st.drops + 1] = { t = d.t, item = d.item, mob = d.mob, awarded = d.awarded, price = d.price, lotted = d.lotted }; end
    for i = math.max(1, #db.history - 19), #db.history do local h = db.history[i]; st.history[#st.history + 1] = { t = h.t, kind = h.kind, by = h.by, text = h.text, undone = h.undone }; end
    local okE, raw = pcall(json.encode, st);
    if (not okE) then return; end
    local path = ROOT .. '\\state.json';
    local f = io.open(path .. '.tmp', 'w');
    if (f == nil) then return; end
    f:write(raw);
    f:close();
    os.remove(path);
    os.rename(path .. '.tmp', path);
end

-- Runs one command. `who` is the player asking (nil = you at the keyboard). Returns nothing; replies by chat/print.
local function run(cmd, rest, who)
    local by = who and N(who) or me();
    local function gate(action)
        if allowed(by, action) then return true; end
        reply(who, ('That needs %s.'):format(db.cfg.need[action]));
        return false;
    end
    rest = rest or '';
    if (cmd == 'event') then cmd = 'camp'; end
    if (cmd == 'help') or (cmd == 'commands') then
        for _, line in ipairs(HK.help_lines(who ~= nil)) do
            if (who == nil) then print(TAG .. line); else outq[#outq + 1] = ('/t %s [DKP] %s'):format(who, line:sub(1, 110)); end
        end
        return;
    end
    if (cmd == 'backfill') then
        if (who ~= nil) then return; end
        HK.backfill(true);
        return;
    end
    if (cmd == 'rollcall') then
        if (who ~= nil) then return; end   -- keeper only
        local ask = '[DKP] Roll call: if you run HeaphKP it answers this for you.';
        if (rest:lower() == 't') or (rest == '<t>') then
            local tn = HK.target_name();
            if (tn == nil) then print(TAG .. 'Target a player first.'); return; end
            outq[#outq + 1] = ('/t %s %s'):format(tn, ask);
            print(TAG .. ('Asked %s. Their answer shows on the Linkshells tab.'):format(tn));
        else
            HK.rollcall = {};
            HK.rollcallAt = os.time();
            post(ask:gsub('^%[DKP%] ', ''));
            print(TAG .. 'Roll call posted. Answers show on the Linkshells tab.');
        end
        return;
    end
    if (cmd == 'invite') then
        if (who ~= nil) then return; end   -- keeper only
        local nm, role = rest:match('^(%S*)%s*(%a*)$');
        if (nm == nil) or (nm == '') or (nm:lower() == 't') or (nm == '<t>') then nm = HK.target_name(); end
        if (nm == nil) then print(TAG .. 'Target a player first, or give a name: /hkp invite <name> [role].'); return; end
        if (not synced()) then
            local _, k = member(nm);
            record({ kind = 'roster', by = me(), text = 'added ' .. k .. ' to the roster' });
            print(TAG .. ('%s added to the roster (This PC book; share the book to send invites).'):format(k));
            return;
        end
        if (not can_manage()) then print(TAG .. 'Only the owner or an admin invites.'); return; end
        role = (role ~= '') and role:lower() or 'viewer';
        if (role ~= 'viewer') and (role ~= 'officer') and (role ~= 'admin') then print(TAG .. 'Role: viewer, officer or admin.'); return; end
        add_member(nm);
        send_invite(N(nm), role);
        return;
    end
    if (cmd == 'camp') then
        if not gate('rc') then return; end
        local sub, arg = rest:match('^(%S*)%s*(.-)%s*$');
        sub = (sub or ''):lower();
        local key = (arg ~= '') and resolve_mob(arg) or nil;
        if (sub == 'start') then
            local ok, err = start_event((key == nil and arg ~= '') and arg or nil, by, key);
            if not ok then reply(who, err); end
        elseif (sub == 'stop') or (sub == 'end') then
            local ok, err = stop_event(by); if not ok then reply(who, err); end
        elseif (sub == 'auto') or (sub == 'noauto') then
            if (key == nil) then reply(who, ('No tracked mob called "%s".'):format(arg)); return; end
            local msg = set_auto(key, sub == 'auto' and (db.autoCamp[key] == nil or arg ~= ''), by);
            if (who == nil) then post(msg); else reply(who, msg); end
        else
            reply(who, 'camp start <mob> | camp stop | camp auto <mob> | camp noauto <mob>');
        end
    elseif (cmd == 'start') then
        if not gate('rc') then return; end
        local ok, err = start_event(rest, by); if not ok then reply(who, err); end
    elseif (cmd == 'stop') then
        if not gate('rc') then return; end
        local ok, err = stop_event(by); if not ok then reply(who, err); end
    elseif (cmd == 'rc') then
        if not gate('rc') then return; end
        local ok, err = open_rc(by); if not ok then reply(who, err); end
    elseif (cmd == 'auction') or (cmd == 'bid' and who == nil) then
        if not gate('auction') then return; end
        local item, min = rest:match('^(.-)%s+(%d+)$');
        if (item == nil) then item = rest; end
        local ok, err = start_auction(item, min, by); if not ok then reply(who, err); end
    elseif (cmd == 'close') or (cmd == 'cancel') then
        if not gate('auction') then return; end
        local ok, err = close_auction(by, cmd == 'cancel'); if not ok then reply(who, err); end
    elseif (cmd == 'award') then
        if not gate('award') then return; end
        local name, price, item = rest:match('^(%S+)%s+(%d+)%s+(.+)$');
        if (name == nil) then reply(who, 'award <name> <price> <item>'); return; end
        award(name, price, item, by);
        post(('%s goes to %s for %s DKP.'):format(item, N(name), price));
    elseif (cmd == 'add') or (cmd == 'adjust') then
        if not gate('adjust') then return; end
        local name, amt, why = rest:match('^(%S+)%s+([%+%-]?%d+)%s*(.*)$');
        if (name == nil) then reply(who, 'adjust <name> <+/-n> [reason]'); return; end
        adjust(name, tonumber(amt), why, by);
        reply(who, ('%s now has %d DKP.'):format(N(name), db.members[N(name)].dkp));
    elseif (cmd == 'undo') then
        if not gate('undo') then return; end
        local e = undo_last(by);
        reply(who, e and ('Undid: ' .. (e.text or e.kind)) or 'Nothing to undo.');
    elseif (cmd == 'tod') then
        if not gate('tod') then return; end
        local mob, when = split_tod(rest);
        local key = resolve_mob(mob);
        if (key == nil) then reply(who, ('No tracked mob called "%s". /dkp track adds one.'):format(mob)); return; end
        local t = parse_when(when);
        if (t == nil) then reply(who, 'Time: now, 21:43, 9:43pm or -15m.'); return; end
        local form = key;   -- the typed name when it is an exact mob (e.g. the HQ "Nidhogg"), else the timer's name
        for _, e in ipairs(HNM) do if (type(e) == 'table') and (e.name ~= nil) and (e.name:lower() == mob:lower()) then form = e.name; end end
        set_tod(key, t, by, form, false);
        reply(who, ('%s ToD set to %s.'):format(form, stamp(t)));
    elseif (cmd == 'role') then
        if not gate('adjust') then return; end
        local name, r = rest:match('^(%S+)%s+(%a+)$');
        if (name == nil) or ((LEVEL[r] == nil) and r ~= 'none') then reply(who, 'role <name> <admin|officer|member|none>'); return; end
        set_role(name, r);
        reply(who, ('%s is now %s.'):format(N(name), r));
    elseif (cmd == 'price') then
        if not gate('adjust') then return; end
        local item, min = rest:match('^(.-)%s+(%d+)$');
        if (item == nil) then reply(who, 'price <item> <min>'); return; end
        set_price(item_key(item), item, tonumber(min));
        reply(who, ('%s minimum: %s DKP.'):format(item, min));
    elseif (cmd == 'track') then
        if not gate('adjust') then return; end
        local name, lo, hi = rest:match('^(.-)%s+([%d%.]+)%s+([%d%.]+)$');
        if (name == nil) then reply(who, 'track <mob> <min hours> <max hours>'); return; end
        set_custom(name, math.floor(tonumber(lo) * 3600), math.floor(tonumber(hi) * 3600));
        reply(who, ('Tracking %s (%s-%sh).'):format(name, lo, hi));
    elseif (cmd == 'export') then
        if not gate('adjust') then return; end
        local stamp_ = os.date('%Y%m%d_%H%M');
        local f = io.open(('%s\\standings_%s.csv'):format(ROOT, stamp_), 'w');
        if f then
            f:write('name,dkp,earned,spent,ticks,role\n');
            for _, r in ipairs(sorted_members()) do
                f:write(('%s,%d,%d,%d,%d,%s\n'):format(r.name, r.m.dkp, r.m.earned, r.m.spent, r.m.ticks, role_of(r.name)));
            end
            f:close();
        end
        local h = io.open(('%s\\history_%s.csv'):format(ROOT, stamp_), 'w');
        if h then
            h:write('id,time,kind,by,text,undone,screenshot\n');
            for _, e in ipairs(db.history) do
                h:write(('%s,%s,%s,%s,"%s",%s,%s\n'):format(tostring(e.id), os.date('%Y-%m-%d %H:%M:%S', e.t), e.kind, e.by or '',
                    tostring(e.text or ''):gsub('"', '""'), e.undone and 'yes' or '', e.shot or ''));
            end
            h:close();
        end
        reply(who, 'Exported to config\\addons\\heaphkp\\ (standings_' .. stamp_ .. '.csv, history_' .. stamp_ .. '.csv).');
    else
        return false;
    end
    return true;
end

---------------------------------------------------------------------------------------------------------------------
-- Incoming chat: ready-check answers, bids, remote commands
---------------------------------------------------------------------------------------------------------------------
local CHAT_TELL, CHAT_PARTY, CHAT_LS, CHAT_LS2 = 3, 4, 5, 27;

local pendingInvites = {};
local ui_badge = false;

local function on_chat(kind, from, msg)
    from = N(from);
    if (from == '') or (from == me()) then return; end
    msg = clean(msg):gsub('^%s+', ''):gsub('%s+$', '');
    local low = msg:lower();

    -- Roll call: a keeper asks the LS (or one player by tell) who runs HeaphKP; the addon answers for you by tell,
    -- once per asker per 10 minutes. Off in Settings > Chat control if you would rather not.
    if msg:find('^%[DKP%] Roll call') then
        if (db.cfg.answerRollCall ~= false) and ((kind == CHAT_LS) or (kind == CHAT_LS2) or (kind == CHAT_TELL) or (kind == CHAT_PARTY)) then
            HK.rcAnswered = HK.rcAnswered or {};
            if (os.time() - (HK.rcAnswered[from] or 0) > 600) then
                HK.rcAnswered[from] = os.time();
                outq[#outq + 1] = ('/t %s [DKP] present %s'):format(from, addon.version);
            end
        end
        return;
    end
    if ((low == '!join heaphkp') or (low == '!join hkp') or (low == '!join')) and ((kind == CHAT_LS) or (kind == CHAT_LS2) or (kind == CHAT_PARTY)) then
        HK.joinReq = HK.joinReq or {};
        if (HK.joinReq[from] == nil) then ui_badge = true; end
        HK.joinReq[from] = os.time();
        return;
    end
    if (kind == CHAT_TELL) then
        local ver = msg:match('^%[DKP%] present (%S+)');
        if (ver ~= nil) then
            HK.rollcall = HK.rollcall or {};
            HK.rollcall[from] = { ver = ver, t = os.time() };
            ui_badge = true;
            return;
        end
    end
    if (kind == CHAT_TELL) then
        local ls, role, code = msg:match('^%[DKP%] Invite: (%w+) as (%a+)%. Code ([%w%-]+)%.');
        if (ls ~= nil) then
            for _, v in ipairs(pendingInvites) do if (v.code == code) then return; end end
            pendingInvites[#pendingInvites + 1] = { from = from, ls = ls, role = role, code = code, t = os.time() };
            ui_badge = true;
            print(TAG .. ('%s invited you to %s DKP as %s. Open HeaphKP > Linkshells to accept.'):format(from, ls, role));
            return;
        end
    end
    if read_only() then return; end

    if db.cfg.chatHere and (db.rc ~= nil) and (low == 'here' or low == '!here' or low == 'x' or low == 'present') then
        if allowed(from, 'here') and (db.members[from] ~= nil or db.cfg.openRoster) then
            member(from);
            db.rc.replied[from] = true;
            if (db.rc.excluded ~= nil) then db.rc.excluded[from] = nil; end
            touch();
        end
        return;
    end

    if db.cfg.chatBids and (db.auction ~= nil) then
        local amt = low:match('^!?bid%s+(%d+)$') or low:match('^!?bid%s+(max)$');
        if (amt == nil) and (kind == CHAT_TELL) then amt = low:match('^(%d+)$') or low:match('^(max)$'); end
        if (amt == nil) and db.auction.sealed then return; end
        if (amt ~= nil) then
            if db.auction.sealed and (kind ~= CHAT_TELL) then tell(from, 'This auction is sealed: send your bid by tell.'); return; end
            if allowed(from, 'bid') then
                local ok, err = place_bid(from, amt, kind);
                if (not ok) then tell(from, err); end
            end
            return;
        end
    end

    if (low == '!dkp') then
        if (not db.cfg.chatBalance) or (not allowed(from, 'balance')) then return; end
        local m = db.members[from];
        tell(from, m and ('You have %d DKP (%d earned, %d spent, %d ticks).'):format(m.dkp, m.earned, m.spent, m.ticks)
                     or "You're not on the roster yet.");
        return;
    end

    local cmd, rest = msg:match('^!(%a+)%s*(.*)$');
    if (not db.cfg.chatCommands) then return; end
    if (cmd ~= nil) and (cmd:lower() ~= 'dkp') then
        cmd = cmd:lower();
        if (cmd == 'bid') or (KNOWN[cmd] == nil) then return; end   -- a bid with no auction open, or plain chat
        run(cmd, rest, from);
    end
end

---------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------
-- Linkshells, sync and alerts
---------------------------------------------------------------------------------------------------------------------
local okNet, net = pcall(require, 'net');
if (not okNet) then net = nil; end
local sync = { inflight = false, next = 0, gen = 0 };
local lsMsg = nil;   -- last message for the Linkshells tab

local function book() return access.books[bookKey]; end
local function server() return (tostring(access.server or '')):gsub('/+$', ''); end

local function can_manage()
    local b = book();
    return (b ~= nil) and (not b.revoked) and ((b.role == 'owner') or (b.role == 'admin'));
end

-- Equipped linkshells from your inventory: item 513 Linkshell (owner), 514 Pearlsack, 515 Linkpearl.
-- The name is 6 bits per letter, packed high bit first, starting at byte 9 of the item's extra data (LSB utils.cpp
-- EncodeStringLinkshell / DecodeStringLinkshell; checked against a port of the server's packBitsLE).
local LS_KIND = { [513] = 'Linkshell', [514] = 'Pearlsack', [515] = 'Linkpearl' };

local function ls_name_from(extra)
    if (type(extra) ~= 'string') or (#extra < 24) then return nil; end
    local bytes = { extra:byte(10, 24) };
    local out = {};
    for i = 0, 19 do
        local v = 0;
        for b = 0, 5 do
            local pos = i * 6 + b;
            local byte = bytes[math.floor(pos / 8) + 1] or 0;
            v = v * 2 + (math.floor(byte / 2 ^ (7 - pos % 8)) % 2);
        end
        if (v == 63) then break; end
        if (v == 0) then out[#out] = nil; break; end   -- same as the server's decoder: a 0 drops the padding char before it
        if (v <= 26) then out[#out + 1] = string.char(96 + v);
        elseif (v <= 52) then out[#out + 1] = string.char(64 + v - 26);
        else out[#out + 1] = string.char(48 + v - 53); end
    end
    return (#out > 0) and table.concat(out) or nil;
end

local lsCache, lsCacheAt = {}, -99;
-- . A shared book posts only into its own linkshell:
-- that LS must be equipped, and with two linkshells on you pick once (Linkshells tab) which slot it is, because the
-- game does not tell the addon which pearl is LS1. Party posts (channel p) need nothing. The This-PC book posts as set.
local equipped_ls;
ls_guard = function ()
    local ch = db.cfg.channel;
    if (bookKey == 'local') or (ch == 'p') then return ch; end
    local b = access.books[bookKey];
    if (b == nil) then return ch; end
    local eq, mine = equipped_ls(), nil;
    for _, l in ipairs(eq) do if (l.name:lower() == b.ls:lower()) then mine = l; end end
    if (mine == nil) then return nil, ('%s is not equipped'):format(b.ls); end
    if (mine.slot ~= nil) then return (mine.slot == 2) and 'l2' or 'l'; end
    if (#eq < 2) then return 'l'; end
    return nil, ('re-equip %s so HeaphKP can see which slot it is in'):format(b.ls);
end

equipped_ls = function ()
    if (os.clock() - lsCacheAt < 2) then return lsCache; end
    lsCacheAt = os.clock();
    local out = {};
    local ok = pcall(function ()
        local inv = AshitaCore:GetMemoryManager():GetInventory();
        -- equipment slots 16 and 17 are Linkshell 1 and 2 (SLOT_BACK + 1/2 in the server source)
        local slotOf = {};
        for slotNo = 1, 2 do
            local okE, eq = pcall(function () return inv:GetEquippedItem(15 + slotNo); end);
            if okE and (type(eq) == 'table') and (eq.Index ~= nil) and (eq.Index ~= 0) then
                local idx = eq.Index % 256;
                local cont = math.floor(eq.Index / 256);
                if (cont == 0) then slotOf[idx] = slotNo; end
            end
        end
        for i = 0, inv:GetContainerCountMax(0) do
            local it = inv:GetContainerItem(0, i);
            if (it ~= nil) and (LS_KIND[it.Id] ~= nil) and (it.Flags == 19) then
                local name = ls_name_from(it.Extra);
                if (name ~= nil) then out[#out + 1] = { name = name, kind = LS_KIND[it.Id], owner = (it.Id == 513), slot = slotOf[i] }; end
            end
        end
    end);
    lsCache = ok and out or {};
    return lsCache;
end;

-- Alerts: a chime, a note by the moogle, and a red dot until you look.
local alerts = {};
local function notify(text)
    alerts[#alerts + 1] = { text = text, t = os.time() };
    while (#alerts > 6) do table.remove(alerts, 1); end
    ui_badge = true;
    print(TAG .. text);
    if db.cfg.notifySound then
        pcall(ashita.misc.play_sound, (addon.path or ''):gsub('[\\/]+$', '') .. '\\assets\\window.wav');
    end
end

local function switch_book(key)
    if dirty then save_db(); end
    bookKey = key;
    access.active = key;
    save_access();
    load_db();
    index_history();
    build_mobs();
    sync.gen, sync.next, sync.inflight = sync.gen + 1, 0, false;
    alerts = {};
end

-- Someone else's change from the server.
local function apply_op(op)
    local b = op.body or {};
    local k = op.kind;
    -- identity: the server stamped the author from the sender's token; the body's own claim is ignored
    if (type(b) == 'table') and (op.author ~= nil) then
        if (b.by ~= nil) then b.by = op.author; end
        if (b.seenBy ~= nil) then b.seenBy = op.author; end
        if (type(b.v) == 'table') and (b.v.by ~= nil) then b.v.by = op.author; end
    end
    if (k == 'rec') then apply_rec(b);
    elseif (k == 'undo') then
        for _, e in ipairs(db.history) do if (e.id == b.id) then apply_undo(e); end end
    elseif (k == 'member') then member(b.n);
    elseif (k == 'member_rm') then db.members[b.n] = nil;
    elseif (k == 'role') then db.perms[N(b.n)] = (b.r ~= 'none') and b.r or nil;
    elseif (k == 'price') then db.prices[b.k] = { name = b.name, min = b.min };
    elseif (k == 'price_rm') then db.prices[b.k] = nil;
    elseif (k == 'custom') then db.custom[b.name] = { minS = b.minS, maxS = b.maxS }; build_mobs();
    elseif (k == 'custom_rm') then db.custom[b.name] = nil; build_mobs();
    elseif (k == 'auto') then db.autoCamp[b.key] = b.on and { by = b.by } or nil;
    elseif (k == 'tod') then
        if (type(b.key) ~= 'string') or (type(b.v) ~= 'table') or (type(b.v.t) ~= 'number') then return; end
        if (math.abs(b.v.t - (op.t or os.time())) > 3 * 86400) then return; end   -- a ToD days away from when it was sent
        db.tods[b.key] = { t = b.v.t, by = tostring(b.v.by or op.author or '?'), form = tostring(b.v.form or b.key), streak = tonumber(b.v.streak) or 0 };
    elseif (k == 'tod_clear') then db.tods[b.key] = nil;
    elseif (k == 'drop') then
        for _, d in ipairs(db.drops) do
            if (d.id == b.id) then return; end   -- our own, echoed back
            -- two of us in the same party saw the same drop: keep one, remember the other id
            if (d.item == b.item) and (d.mob == b.mob) and (d.slot == b.slot) and (d.itemId == b.itemId)
                and (math.abs((d.t or 0) - (b.t or 0)) < 60) then
                db.aliases = db.aliases or {};
                db.aliases[b.id] = d.id;
                return;
            end
        end
        b.shot = nil;   -- the picture is on their PC
        db.drops[#db.drops + 1] = b;
    elseif (k == 'drop_upd') then
        local d = drop_by_id(b.id);
        if (d ~= nil) then d.lotted = b.lotted or d.lotted; end
    elseif (k == 'drop_rm') then
        local want = (db.aliases or {})[b.id] or b.id;
        for i, d in ipairs(db.drops) do if (d.id == want) then table.remove(db.drops, i); break; end end
    elseif (k == 'live') then
        db.live[op.author] = { t = op.t, s = b };
    end
    touch();
end

local function sync_tick()
    if (net ~= nil) then net.step(); end
    local b = book();
    if (net == nil) or (b == nil) or b.revoked or sync.inflight then return; end
    local now = os.clock();
    if (now < sync.next) and ((syncSoon == nil) or (now < syncSoon)) then return; end
    syncSoon = nil;
    local batch = {};
    for i = 1, math.min(100, #db.outbox) do batch[i] = db.outbox[i]; end
    sync.inflight = true;
    local sentFor, gen = bookKey, sync.gen;
    net.post(server() .. '/sync', { token = b.token, since = db.seq or 0, ops = batch }, function (ok, status, r)
        if (gen ~= sync.gen) then return; end   -- the book changed or was reloaded while this was in flight
        sync.inflight = false;
        if (sentFor ~= bookKey) then sync.next = 0; return; end
        if (not ok) then
            b.err = (type(r) == 'table' and r.error) or tostring(r);
            if (status == 401) then
                b.revoked = true;
                print(TAG .. ('Your access to %s was removed.'):format(b.ls));
            end
            sync.next = os.clock() + 30;
            save_access();
            return;
        end
        b.err, b.lastSync, b.role = nil, os.time(), r.role;
        if (type(r.time) == 'number') then   -- this PC vs the server's clock; ignore under 2 s (network delay)
            local off = r.time - os.rawtime();
            if (math.abs(off) >= 2) and (math.abs(off) < 86400) then access.clockOffset = off; else access.clockOffset = 0; end
        end
        local acked = {};
        for _, o in ipairs(batch) do acked[o.cid] = true; end
        for i = #db.outbox, 1, -1 do if acked[db.outbox[i].cid] then table.remove(db.outbox, i); end end
        for _, rj in ipairs(r.rejected or {}) do
            db.sent[rj.cid] = nil;
            print(TAG .. ('The server refused a change: %s.'):format(rj.why));
        end
        applying = true;
        for _, op in ipairs(r.ops or {}) do
            db.sent[op.cid] = nil;
            local okA, err = pcall(apply_op, op);   -- our own changes too: every client applies the log in the same order
            if (not okA) then print(TAG .. 'sync: ' .. tostring(err)); end
            db.seq = math.max(db.seq or 0, op.seq or 0);
        end
        applying = false;
        if (r.keys ~= nil) then db.keys = r.keys; end
        db.perms, db.seen = {}, {};   -- the server's roles are the truth; seen = who has actually joined
        for _, x in ipairs(r.roles or {}) do
            db.perms[N(x.name)] = x.role;
            db.seen[N(x.name)] = { joined = x.joined, last = x.last_seen };
        end
        touch();
        save_access();
        sync.next = os.clock() + ((r.more or #db.outbox > 0) and 0.5 or 15);
    end);
end

-- Start over from the server's copy (fixes a book that drifted, e.g. after changes made while view-only).
local function reload_from_server()
    local cfg = db.cfg;
    db = defaults();
    db.cfg = cfg;
    index_history();
    build_mobs();
    touch();
    sync.gen, sync.inflight, sync.next = sync.gen + 1, false, 0;
end

-- Copy a This-PC book into a newly shared one, as changes for the server.
local function import_book(old)
    for _, e in ipairs(old.history or {}) do
        local copy = {};
        for kk, v in pairs(e) do copy[kk] = v; end
        copy.undone = nil;
        copy.id = copy.id or new_id();
        apply_rec(copy);
        emit('rec', copy);
        if e.undone then apply_undo(copy); emit('undo', { id = copy.id }); end
    end
    for n in pairs(old.members or {}) do if (db.members[n] == nil) then add_member(n); end end
    for kk, p in pairs(old.prices or {}) do set_price(kk, p.name, p.min); end
    for n, c in pairs(old.custom or {}) do set_custom(n, c.minS, c.maxS); end
    for key, v in pairs(old.tods or {}) do db.tods[key] = v; emit('tod', { key = key, v = v }); end
    for i = math.max(1, #(old.drops or {}) - 100), #(old.drops or {}) do
        local d = old.drops[i];
        if (d ~= nil) then db.drops[#db.drops + 1] = d; emit('drop', d); end
    end
    db.cfg = old.cfg or db.cfg;
    touch();
end

local function register_ls(lsName, bring)
    if (net == nil) then lsMsg = 'The network library did not load.'; return; end
    if (server() == '') then lsMsg = 'Set the sync server first: Settings > Sync server.'; return; end
    lsMsg = ('Turning on DKP for %s...'):format(lsName);
    local old = bring and db or nil;
    net.post(server() .. '/register', { ls = lsName, name = me() }, function (ok, _, r)
        if (not ok) then lsMsg = (type(r) == 'table' and r.error) or tostring(r); return; end
        local key = r.ls:lower();
        access.books[key] = { ls = r.ls, name = me(), token = r.token, role = r.role };
        save_access();
        switch_book(key);
        db.perms[me()] = 'owner';
        if (old ~= nil) then import_book(old); end
        lsMsg = ('DKP is on for %s. You are the owner. Invite officers from Standings or Settings.'):format(r.ls);
        sync.next = 0;
    end);
end

local function join_ls(lsName, code, onDone)
    if (net == nil) then lsMsg = 'The network library did not load.'; return; end
    if (server() == '') then lsMsg = 'Set the sync server first: Settings > Sync server.'; return; end
    lsMsg = ('Joining %s...'):format(lsName);
    net.post(server() .. '/join', { ls = lsName, name = me(), code = code }, function (ok, _, r)
        if (not ok) then lsMsg = (type(r) == 'table' and r.error) or tostring(r); return; end
        local key = r.ls:lower();
        access.books[key] = { ls = r.ls, name = me(), token = r.token, role = r.role };
        save_access();
        switch_book(key);
        lsMsg = ("You're in %s as %s."):format(r.ls, r.role);
        if onDone then onDone(); end
    end);
end

local function send_invite(name, role)
    local b = book();
    if (net == nil) or (b == nil) then return; end
    if (server() == '') then print(TAG .. 'Set the sync server first: Settings > Sync server.'); return; end
    net.post(server() .. '/invite', { token = b.token, name = name, role = role }, function (ok, _, r)
        if (not ok) then print(TAG .. ((type(r) == 'table' and r.error) or tostring(r))); return; end
        tell(name, ('Invite: %s as %s. Code %s. Good for 1 hour: HeaphKP > Linkshells > Accept.'):format(r.ls, r.role, r.code), true);
        print(TAG .. ('Invite sent to %s (%s).'):format(r.name, r.role));
    end);
end

-- API keys for bots and outside tools (owner/admin). A key is the name 'bot:<label>' on the server.
HK.make_key = function (label, role)
    local b = book();
    if (net == nil) or (b == nil) or (server() == '') then return; end
    net.post(server() .. '/keys', { token = b.token, label = label, role = role }, function (ok, _, r)
        if (not ok) then lsMsg = (type(r) == 'table' and r.error) or tostring(r); return; end
        ui.newKey[1] = r.key;
        lsMsg = ('Key for %s made (%s). Copy it now: it is shown once.'):format(r.name, r.role);
        sync.next = 0;
    end);
end
HK.revoke_key = function (label)
    local b = book();
    if (net == nil) or (b == nil) or (server() == '') then return; end
    net.post(server() .. '/keys/revoke', { token = b.token, label = label }, function (ok, _, r)
        lsMsg = ok and ('Key %s revoked.'):format(label) or ((type(r) == 'table' and r.error) or tostring(r));
        sync.next = 0;
    end);
end

-- Live status (event, ready check, auction) so other officers see what this client is running.
local liveSig = '';
local function live_tick()
    if (not synced()) or read_only() then return; end
    local ev, a, rc = db.event, db.auction, db.rc;
    local best = a and high_bid() or nil;
    local sig = table.concat({ ev and ev.name or '', ev and ev.ticks or '', rc and rc.closes or '', a and a.item or '',
        a and a.ends or '', best and best.amt or '' }, '|');
    if (sig == liveSig) then return; end
    liveSig = sig;
    emit('live', {
        event = ev and { name = ev.name, mob = ev.mob, ticks = ev.ticks, started = ev.started } or nil,
        rc = rc and { closes = rc.closes } or nil,
        auction = a and { item = a.item, min = a.min, ends = a.ends, sealed = a.sealed,
                          high = (not a.sealed and best) and best.amt or nil, bidder = (not a.sealed and best) and best.name or nil } or nil,
    });
end

-- Window alerts: N minutes before a known window opens, and when it opens.
local notifyCheck = 0;
local function notify_tick()
    local now = os.time();
    if (now < notifyCheck) or (not db.cfg.notifyOn) then return; end
    notifyCheck = now + 5;
    for _, m in ipairs(mobs) do
        local t, e = db.tods[m.key], m.e;
        if (t ~= nil) and (e.minS ~= nil) and (not e.forced) then
            local open = t.t + e.minS;
            local n = db.notified[m.key] or {};
            if (now >= open - db.cfg.notifyLead * 60) and (now < open) and (n.pre ~= t.t) then
                n.pre = t.t;
                notify(('%s window opens in %d min (%s).'):format(m.key, math.ceil((open - now) / 60), clock(open)));
                if db.cfg.notifyLS and (db.event ~= nil) and ((not synced()) or (db.perms[me() or ''] == 'officer') or (db.perms[me() or ''] == 'admin') or (db.perms[me() or ''] == 'owner')) then post(('%s window opens in %d min (%s %s).'):format(m.key, math.ceil((open - now) / 60), clock(open), zone())); end
            elseif (now >= open) and (now < open + 300) and (n.open ~= t.t) then
                n.open, n.pre = t.t, t.t;
                notify(('%s window is open.'):format(m.key));
                if db.cfg.notifyLS and (db.event ~= nil) and ((not synced()) or (db.perms[me() or ''] == 'officer') or (db.perms[me() or ''] == 'admin') or (db.perms[me() or ''] == 'owner')) then post(('%s window is open.'):format(m.key)); end
            end
            db.notified[m.key] = n;
        end
    end
end

---------------------------------------------------------------------------------------------------------------------
-- UI. Everything can be done from here; chat is optional (Settings > Chat control).
---------------------------------------------------------------------------------------------------------------------
local ui = {
    open = { false },
    filter = { '' }, histFilter = { '' },
    sel = nil, adjAmt = { 0 }, adjWhy = { '' }, newName = { '' }, confirmRemove = nil,
    aucItem = { '' }, aucMin = { 0 }, aucLastItem = '', aucDrop = nil,
    bidName = nil, bidAmt = { 0 },
    awardName = nil, awardPrice = { 0 }, awardItem = { '' }, awardDrop = nil,
    evName = { '' }, rcAdd = nil, rcNew = { '' }, campMob = nil, mobFilter = { '' }, autoMob = nil,
    todMob = nil, todWhen = { '' }, todAll = { false }, todFilter = { '' },
    lootSel = nil,
    joinLs = { '' }, joinCode = { '' }, bring = { true }, confirmLeave = nil, serverBuf = nil,
    permName = nil, permRole = 'officer',
    priceItem = { '' }, priceMin = { 0 },
    trackName = { '' }, trackLo = { 0 }, trackHi = { 0 },
    goTab = nil,
    S = 1, font = nil, dragging = false,
    keyLabel = { '' }, keyRole = 'viewer', newKey = { '' },   -- size factor from the font (draw()), Verdana Bold, moogle drag state
};
function ui.px(n) return math.floor(n * ui.S + 0.5); end

local C = {
    accent = { 1.00, 0.84, 0.45, 1.0 },   -- the HUD's gold
    dim    = { 0.92, 0.92, 0.95, 1.0 },   -- white like the HUD
    text   = { 0.92, 0.92, 0.95, 1.0 },
    good   = { 0.46, 0.84, 0.56, 1.0 },
    warn   = { 0.95, 0.80, 0.35, 1.0 },
    bad    = { 0.95, 0.45, 0.42, 1.0 },
};
local STATE_COL = { wait = C.dim, open = C.good, late = C.warn, dim = C.dim };
local TABLE_FLAGS = nil;

local function label(s) imgui.TextColored(C.dim, s); end
local function section(s) imgui.Spacing(); imgui.TextColored(C.accent, s); end

local function small_input_int(id, buf, w)
    imgui.SetNextItemWidth(ui.px(w or 90));
    imgui.InputInt(id, buf, 0, 0);
end

local function combo(id, cur, list, w)
    imgui.SetNextItemWidth(ui.px(w or 100));
    local out = cur;
    if imgui.BeginCombo(id, cur or '') then
        for _, v in ipairs(list) do if imgui.Selectable(v, v == cur) then out = v; end end
        imgui.EndCombo();
    end
    return out;
end

-- Pick a roster member; the last entry lets you type a new name.
local function member_combo(id, cur, w)
    local names = {};
    for _, r in ipairs(sorted_members()) do names[#names + 1] = r.name; end
    table.sort(names);
    return combo(id, cur or (names[1] and 'Pick a name' or 'Roster is empty'), names, w or 130);
end

local function button(lbl, enabled)
    if (enabled == false) then imgui.BeginDisabled(true); end
    local hit = imgui.Button(lbl);
    if (enabled == false) then imgui.EndDisabled(); end
    return hit and (enabled ~= false);
end

local function check(lbl, key, tip)
    local b = { db.cfg[key] };
    if imgui.Checkbox(lbl, b) then db.cfg[key] = b[1]; touch(); end
    if (tip ~= nil) and imgui.IsItemHovered() then imgui.SetTooltip(tip); end
end

local function valid_name(n) return (n ~= nil) and db.members[n] ~= nil; end

local function count(t) local c = 0; for _ in pairs(t or {}) do c = c + 1; end; return c; end

-- Every timed/pop mob, soonest window first, then A-Z.
local function mob_list()
    local out = {};
    for _, m in ipairs(mobs) do
        local t = db.tods[m.key];
        out[#out + 1] = { key = m.key, e = m.e, s = (t and m.e.minS) and (t.t + m.e.minS) or math.huge };
    end
    table.sort(out, function (a, b) if (a.s ~= b.s) then return a.s < b.s; end; return a.key < b.key; end);
    return out;
end

-- Dropdown of tracked mobs with a search box at the top. `extra` adds a first entry (e.g. 'Other').
local function mob_combo(id, cur, w, timedOnly, extra)
    imgui.SetNextItemWidth(ui.px(w or 220));
    local out = cur;
    if imgui.BeginCombo(id, cur or 'Pick what you are camping') then
        imgui.SetNextItemWidth(-1);
        imgui.InputTextWithHint('##f' .. id, 'Type to search', ui.mobFilter, 32);
        local f = ui.mobFilter[1]:lower();
        if (extra ~= nil) and imgui.Selectable(extra, cur == extra) then out = extra; end
        local now = os.time();
        for _, m in ipairs(mob_list()) do
            local okTimed = (not timedOnly) or ((m.e.minS ~= nil) and not m.e.forced);
            if okTimed and ((f == '') or m.key:lower():find(f, 1, true) or (m.e.zone or ''):lower():find(f, 1, true)) then
                if imgui.Selectable(m.key .. id, m.key == cur) then out = m.key; ui.mobFilter[1] = ''; end
                imgui.SameLine(ui.px(190));
                local t = db.tods[m.key];
                if (t ~= nil) and (m.e.minS ~= nil) then
                    local txt, st = window_text(m.e, t.t, now);
                    imgui.TextColored(STATE_COL[st], txt);
                else
                    imgui.TextColored(C.dim, m.e.forced and ('pop  ' .. (m.e.zone or '')) or (m.e.zone or ''));
                end
            end
        end
        imgui.EndCombo();
    end
    return out;
end

local function header()
    local now = os.time();
    local b = book();
    imgui.TextColored(C.accent, b and b.ls or 'This PC only');
    imgui.SameLine();
    if (b ~= nil) then
        local st = b.revoked and 'access removed' or (b.err and ('sync problem: ' .. b.err))
            or (b.lastSync and ('synced %s ago'):format(dur(now - b.lastSync)) or 'connecting...');
        imgui.TextColored((b.err or b.revoked) and C.warn or C.dim, ('  %s  |  %s%s'):format(b.role or '?', st,
            (#db.outbox > 0) and ('  |  %d to send'):format(#db.outbox) or ''));
        if read_only() then imgui.TextColored(C.warn, 'View only: you can look, officers run the book.'); end
    else
        label('  not shared (Linkshells tab to share it)');
    end
    for who, l in pairs(db.live or {}) do
        local sv = l.s or {};
        if (who ~= me()) and (now - (l.t or 0) < 3 * 3600) and ((sv.event ~= nil) or (sv.auction ~= nil)) then
            local parts = {};
            if sv.event then parts[#parts + 1] = ('%s (%d ticks)'):format(sv.event.name, sv.event.ticks or 0); end
            if sv.auction then
                parts[#parts + 1] = ('bidding on %s%s'):format(sv.auction.item,
                    sv.auction.high and (', %d by %s'):format(sv.auction.high, sv.auction.bidder) or '');
            end
            imgui.TextColored(C.good, ('%s is running: %s'):format(who, table.concat(parts, ', ')));
        end
    end
    local ev = db.event;
    if (ev ~= nil) then
        imgui.TextColored(C.accent, ev.name);
        imgui.SameLine();
        local rcText = (db.rc ~= nil) and ('ready check open, %s left (%d answered)'):format(dur(db.rc.closes - now), count(db.rc.replied))
            or ('next ready check in %s'):format(dur(ev.nextRc - now));
        imgui.TextColored(C.dim, ('  %s  |  %d ticks  |  %s'):format(dur(now - ev.started), ev.ticks, rcText));
        if (ev.mob ~= nil) and (db.tods[ev.mob] ~= nil) and (mob_def(ev.mob) ~= nil) then
            local txt, st = window_text(mob_def(ev.mob), db.tods[ev.mob].t, now);
            imgui.TextColored(STATE_COL[st], ('  %s: %s'):format(ev.mob, txt));
            if (ev.killedAt ~= nil) then imgui.SameLine(); imgui.TextColored(C.good, ('  killed, ends in %s'):format(dur(ev.killedAt + db.cfg.endAfterKill * 60 - now))); end
        end
    else
        imgui.TextColored(C.dim, 'No event running.');
        imgui.SameLine();
        label(' Start one on the Attendance tab.');
    end
    local a = db.auction;
    if (a ~= nil) then
        local best = high_bid();
        imgui.TextColored(C.accent, a.item);
        imgui.SameLine();
        imgui.TextColored(C.text, ('  %s  |  %s left'):format(
            a.sealed and ('%d sealed bids'):format(count(a.bids)) or (best and ('%d by %s'):format(best.amt, best.name) or ('min %d, no bids'):format(a.min)),
            dur(a.ends - now)));
    end
    imgui.Separator();
end

---------------------------------------------------------------------------------------------------------------------
local function tab_standings()
    imgui.SetNextItemWidth(ui.px(160));
    imgui.InputTextWithHint('##filter', 'Find a name', ui.filter, 32);
    imgui.SameLine();
    imgui.SetNextItemWidth(ui.px(130));
    imgui.InputTextWithHint('##newn', 'New member', ui.newName, 16);
    imgui.SameLine();
    if button('Add to roster', ui.newName[1] ~= '') then
        local k = add_member(ui.newName[1]);
        record({ kind = 'roster', by = me(), text = 'added ' .. k .. ' to the roster' });
        ui.sel, ui.newName[1] = k, '';
    end
    imgui.SameLine();
    local tn = HK.target_name();
    if button(tn and ('Add target: ' .. tn) or 'Add target', tn ~= nil) then
        local k = add_member(tn);
        record({ kind = 'roster', by = me(), text = 'added ' .. k .. ' to the roster' });
        ui.sel = k;
    end
    local f = ui.filter[1]:lower();
    if imgui.BeginTable('##standings', 6, TABLE_FLAGS, { 0, ui.sel and -ui.px(128) or 0 }) then
        imgui.TableSetupScrollFreeze(0, 1);
        imgui.TableSetupColumn('Name', ImGuiTableColumnFlags_WidthStretch, 2.0);
        imgui.TableSetupColumn('DKP', ImGuiTableColumnFlags_WidthStretch, 1.0);
        imgui.TableSetupColumn('Earned', ImGuiTableColumnFlags_WidthStretch, 1.0);
        imgui.TableSetupColumn('Spent', ImGuiTableColumnFlags_WidthStretch, 1.0);
        imgui.TableSetupColumn('Ticks', ImGuiTableColumnFlags_WidthStretch, 0.8);
        imgui.TableSetupColumn('Role', ImGuiTableColumnFlags_WidthStretch, 1.0);
        imgui.TableHeadersRow();
        for _, r in ipairs(sorted_members()) do
            if (f == '') or r.name:lower():find(f, 1, true) then
                imgui.TableNextRow();
                imgui.TableNextColumn();
                if imgui.Selectable(r.name .. '##m', ui.sel == r.name, ImGuiSelectableFlags_SpanAllColumns) then
                    ui.sel = (ui.sel == r.name) and nil or r.name;
                    ui.confirmRemove = nil;
                end
                imgui.TableNextColumn(); imgui.TextColored(r.m.dkp < 0 and C.bad or C.text, tostring(r.m.dkp));
                imgui.TableNextColumn(); imgui.TextColored(C.dim, tostring(r.m.earned));
                imgui.TableNextColumn(); imgui.TextColored(C.dim, tostring(r.m.spent));
                imgui.TableNextColumn(); imgui.TextColored(C.dim, tostring(r.m.ticks));
                imgui.TableNextColumn();
                local role = role_of(r.name);
                imgui.TextColored(role == 'member' and C.dim or C.accent, role);
            end
        end
        if (next(db.members) == nil) then
            imgui.TableNextRow(); imgui.TableNextColumn();
            label('Nobody yet. Add names above, or start an event and run a ready check.');
        end
        imgui.EndTable();
    end
    local k = ui.sel;
    if (k == nil) or (db.members[k] == nil) then ui.sel = nil; return; end
    if read_only() then return; end
    local m = db.members[k];
    imgui.Separator();
    imgui.TextColored(C.accent, k);
    imgui.SameLine();
    imgui.TextColored(C.text, ('%d DKP'):format(m.dkp));
    imgui.SameLine();
    label(('  earned %d, spent %d, %d ticks'):format(m.earned, m.spent, m.ticks));
    for _, n in ipairs({ -10, -5, -1, 1, 5, 10 }) do
        if imgui.Button(('%+d##q%d'):format(n, n)) then adjust(k, n, ui.adjWhy[1], me()); end
        imgui.SameLine();
    end
    small_input_int('##adja', ui.adjAmt, 70);
    imgui.SameLine();
    if button('Apply', ui.adjAmt[1] ~= 0) then adjust(k, ui.adjAmt[1], ui.adjWhy[1], me()); ui.adjAmt[1] = 0; end
    imgui.SetNextItemWidth(ui.px(260));
    imgui.InputTextWithHint('##adjw', 'Reason (optional, goes in history)', ui.adjWhy, 64);
    imgui.SameLine();
    label('Role');
    imgui.SameLine();
    if synced() then
        local r = db.perms[k] or 'member';
        if (r == 'owner') then imgui.TextColored(C.accent, 'owner');
        elseif can_manage() then
            local nr = combo('##role', r, SROLES, 100);
            if (nr ~= r) then set_role(k, nr); end
            imgui.SameLine();
            if imgui.Button('Send invite') then send_invite(k, (r == 'member') and 'viewer' or r); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Tells them a one-use code. Their HeaphKP shows an Accept button.'); end
        else imgui.TextColored(C.dim, r); end
    elseif (k == me()) then
        imgui.TextColored(C.accent, 'admin (you)');
    else
        local r = role_of(k);
        local nr = combo('##role', r, ROLES, 100);
        if (nr ~= r) then set_role(k, nr); end
    end
    imgui.SameLine();
    if synced() and (not can_manage()) then
        label('(an admin removes)');
    elseif (ui.confirmRemove == k) then
        imgui.PushStyleColor(ImGuiCol_Button, { 0.55, 0.18, 0.16, 1.0 });
        if imgui.Button('Really remove?') then
            record({ kind = 'roster', by = me(), text = ('removed %s from the roster (had %d DKP)'):format(k, m.dkp) });
            remove_member(k);
            ui.sel, ui.confirmRemove = nil, nil;
        end
        imgui.PopStyleColor(1);
    elseif imgui.Button('Remove') then
        ui.confirmRemove = k;
    end
end

---------------------------------------------------------------------------------------------------------------------
local function award_panel()
    section('Award by hand');
    ui.awardName = member_combo('##awn', ui.awardName);
    imgui.SameLine(); small_input_int('##awp', ui.awardPrice, 70);
    imgui.SameLine(); imgui.SetNextItemWidth(ui.px(180)); imgui.InputTextWithHint('##awi', 'Item', ui.awardItem, 64);
    imgui.SameLine();
    if button('Award', valid_name(ui.awardName) and ui.awardItem[1] ~= '') then
        award(ui.awardName, ui.awardPrice[1], ui.awardItem[1], me(), ui.awardDrop);
        post(('%s goes to %s for %d DKP.'):format(ui.awardItem[1], ui.awardName, ui.awardPrice[1]));
        ui.awardItem[1], ui.awardPrice[1], ui.awardDrop = '', 0, nil;
    end
end

local function tab_auction()
    local a = db.auction;
    local now = os.time();
    if (a == nil) then
        section('Open bidding');
        imgui.SetNextItemWidth(ui.px(220));
        imgui.InputTextWithHint('##auci', 'Item name', ui.aucItem, 64);
        if (ui.aucItem[1] ~= ui.aucLastItem) then ui.aucLastItem = ui.aucItem[1]; ui.aucMin[1] = price_for(ui.aucItem[1]); end
        imgui.SameLine(); label('min'); imgui.SameLine(); small_input_int('##aucm', ui.aucMin, 70);
        imgui.SameLine(); label('seconds'); imgui.SameLine();
        local bs = { db.cfg.bidSec }; small_input_int('##aucs', bs, 50);
        if (bs[1] ~= db.cfg.bidSec) then db.cfg.bidSec = math.max(10, bs[1]); touch(); end
        imgui.SameLine(); check('Sealed', 'sealed', 'Sealed: bids are hidden until the close (by tell, or added below).');
        if button('Open bidding', ui.aucItem[1] ~= '') then
            start_auction(ui.aucItem[1], ui.aucMin[1], me(), ui.aucDrop);
            ui.aucDrop = nil;
        end
        imgui.SameLine();
        label(db.cfg.chatBids and 'Bids come from chat and from the box below.' or 'Chat bids are off: add bids in the box below.');
    else
        local best = high_bid();
        section(a.item);
        imgui.SameLine();
        imgui.TextColored(C.dim, ('min %d  |  %s left%s'):format(a.min, dur(a.ends - now), a.sealed and '  |  sealed' or ''));
        if imgui.Button('+15s') then a.ends = a.ends + 15; touch(); end
        imgui.SameLine(); if imgui.Button('+60s') then a.ends = a.ends + 60; touch(); end
        imgui.SameLine(); if button('Close and award', best ~= nil) then close_auction(me()); end
        imgui.SameLine(); if imgui.Button(best and 'Cancel' or 'Close (no bids)') then close_auction(me(), best ~= nil); end
        label('Add a bid');
        ui.bidName = member_combo('##bidn', ui.bidName);
        imgui.SameLine(); small_input_int('##bida', ui.bidAmt, 70);
        imgui.SameLine();
        if button('Add bid', valid_name(ui.bidName) and ui.bidAmt[1] > 0) then
            local ok, err = place_bid(ui.bidName, ui.bidAmt[1], 'menu');
            if (not ok) then print(TAG .. err); else ui.bidAmt[1] = 0; end
        end
        if imgui.BeginChild('##bids', { 0, ui.px(110) }, ImGuiChildFlags_Borders) then
            for i = #a.bids, 1, -1 do
                local b = a.bids[i];
                local col = b.void and C.dim or ((best ~= nil and b == best) and C.good or C.text);
                imgui.TextColored(col, ('%s  %d%s'):format(b.name, b.amt, b.void and '  (replaced)' or ''));
                if (not b.void) then
                    imgui.SameLine(ui.px(220));
                    if imgui.SmallButton('Award##b' .. i) then
                        db.auction = nil;
                        award(b.name, b.amt, a.item, me(), a.drop);
                        post(('%s goes to %s for %d DKP.'):format(a.item, b.name, b.amt));
                        touch();
                    end
                    imgui.SameLine();
                    if imgui.SmallButton('Remove##b' .. i) then b.void = true; touch(); end
                end
            end
            if (#a.bids == 0) then label('No bids yet.'); end
        end
        imgui.EndChild();
        if (db.auction == nil) then return; end
    end
    section('Unawarded drops (last 6 hours)');
    if imgui.BeginChild('##recent', { 0, ui.px(-78) }, ImGuiChildFlags_Borders) then
        local shown = 0;
        for i = #db.drops, 1, -1 do
            local d = db.drops[i];
            if (d.awarded == nil) and (now - d.t < 6 * 3600) then
                shown = shown + 1;
                imgui.TextColored(C.text, d.item);
                imgui.SameLine(); imgui.TextColored(C.dim, ('%s  %s'):format(d.mob ~= '' and d.mob or '', clock(d.t)));
                imgui.SameLine(ui.px(380));
                if (db.auction == nil) and imgui.SmallButton('Auction##d' .. d.id) then start_auction(d.item, nil, me(), d.id); end
                imgui.SameLine();
                if imgui.SmallButton('Award##d' .. d.id) then ui.awardItem[1], ui.awardDrop = d.item, d.id; ui.awardPrice[1] = price_for(d.item); end
            end
        end
        if (shown == 0) then label('Nothing waiting.'); end
    end
    imgui.EndChild();
    award_panel();
end

---------------------------------------------------------------------------------------------------------------------
local function tab_timers()
    local now = os.time();
    local f = ui.todFilter[1]:lower();
    local rows = {};
    for _, m in ipairs(mobs) do
        local t = db.tods[m.key];
        local match = (f == '') or m.key:lower():find(f, 1, true) or (m.e.zone or ''):lower():find(f, 1, true);
        if match and ((t ~= nil) or ui.todAll[1] or (f ~= '')) then
            rows[#rows + 1] = { m = m, t = t, s = t and (t.t + (m.e.minS or 0)) or math.huge };
        end
    end
    table.sort(rows, function (a, b) if (a.s ~= b.s) then return a.s < b.s; end; return a.m.key < b.m.key; end);
    imgui.SetNextItemWidth(ui.px(170));
    imgui.InputTextWithHint('##todf', 'Find a mob or zone', ui.todFilter, 32);
    imgui.SameLine();
    imgui.Checkbox('Show every mob', ui.todAll);
    if (bookKey ~= 'local') then ui.share_switch(); end
    if imgui.BeginTable('##tods', 4, TABLE_FLAGS, { 0, ui.todMob and -ui.px(90) or 0 }) then
        imgui.TableSetupScrollFreeze(0, 1);
        imgui.TableSetupColumn('Mob', ImGuiTableColumnFlags_WidthStretch, 1.4);
        imgui.TableSetupColumn('Zone', ImGuiTableColumnFlags_WidthStretch, 1.4);
        imgui.TableSetupColumn('Last ToD', ImGuiTableColumnFlags_WidthStretch, 1.2);
        imgui.TableSetupColumn('Window', ImGuiTableColumnFlags_WidthStretch, 2.2);
        imgui.TableHeadersRow();
        for _, r in ipairs(rows) do
            local e = r.m.e;
            imgui.TableNextRow();
            imgui.TableNextColumn();
            local nm = r.m.key;
            if (r.t ~= nil) and (r.t.form ~= nil) and (r.t.form ~= r.m.key) then nm = ('%s (%s)'):format(r.m.key, r.t.form); end
            if imgui.Selectable(nm .. '##t', ui.todMob == r.m.key, ImGuiSelectableFlags_SpanAllColumns) then
                ui.todMob = (ui.todMob == r.m.key) and nil or r.m.key;
            end
            if imgui.IsItemHovered() and ((e.note or e.hqRule) ~= nil) then
                imgui.SetTooltip(table.concat({ e.hqRule or '', e.note or '' }, (e.hqRule and e.note) and '\n' or ''));
            end
            imgui.TableNextColumn(); imgui.TextColored(C.dim, e.zone or '');
            imgui.TableNextColumn();
            if (r.t ~= nil) then
                imgui.TextColored(C.text, stamp(r.t.t));
                if (e.hq ~= nil) and ((r.t.streak or 0) > 0) then imgui.SameLine(); imgui.TextColored(C.dim, ('%d since HQ'):format(r.t.streak)); end
            else imgui.TextColored(C.dim, '-'); end
            imgui.TableNextColumn();
            if e.forced then imgui.TextColored(C.dim, 'pop: ' .. (e.pop or 'forced'));
            elseif (r.t ~= nil) then
                local txt, st = window_text(e, r.t.t, now);
                imgui.TextColored(STATE_COL[st], txt);
            else
                imgui.TextColored(C.dim, (e.minS ~= nil) and ('%s-%s after ToD'):format(dur(e.minS), dur(e.maxS or e.minS)) or '');
            end
        end
        if (#rows == 0) then
            imgui.TableNextRow(); imgui.TableNextColumn();
            label('No ToDs yet. Kills you see log themselves; tick "Show every mob" to set one.');
        end
        imgui.EndTable();
    end
    local key = ui.todMob;
    if (key == nil) or read_only() then return; end
    local e = mob_def(key);
    imgui.Separator();
    imgui.TextColored(C.accent, key);
    imgui.SameLine();
    if e and e.hq then
        if imgui.Button('Killed NQ now') then set_tod(key, os.time(), me(), key, false); end
        imgui.SameLine();
        if imgui.Button(('Killed %s now'):format(e.hq)) then set_tod(key, os.time(), me(), e.hq, false); end
    elseif imgui.Button('Killed now') then
        set_tod(key, os.time(), me(), key, false);
    end
    imgui.SameLine();
    imgui.SetNextItemWidth(ui.px(130));
    imgui.InputTextWithHint('##todw', '21:43 or -15m', ui.todWhen, 16);
    imgui.SameLine();
    if button('Set time', ui.todWhen[1] ~= '') then
        local t = parse_when(ui.todWhen[1]);
        if (t ~= nil) then set_tod(key, t, me(), key, false); ui.todWhen[1] = ''; else print(TAG .. 'Time: 21:43, 9:43pm or -15m.'); end
    end
    imgui.SameLine();
    if button('Post to LS', db.tods[key] ~= nil) then
        local t = db.tods[key];
        post(('%s ToD %s, %s.'):format(key, stamp(t.t), (window_text(e, t.t, now))));
    end
    imgui.SameLine();
    if button('Clear', db.tods[key] ~= nil) then clear_tod(key); end
    if (e ~= nil) and (e.minS ~= nil) and (not e.forced) then
        local b = { db.autoCamp[key] ~= nil };
        if imgui.Checkbox('Auto-start the camp from the ToD', b) then print(TAG .. set_auto(key, b[1])); end
        imgui.SameLine();
    end
    if button('Start camp now', db.event == nil) then start_event(nil, me(), key); end
end

---------------------------------------------------------------------------------------------------------------------
local function tab_attendance()
    local ev = db.event;
    if (ev == nil) then
        label('Camping');
        imgui.SameLine();
        ui.campMob = mob_combo('##camp', ui.campMob, 220, false, 'Other (type a name)');
        if (ui.campMob == 'Other (type a name)') then
            imgui.SameLine(); imgui.SetNextItemWidth(ui.px(170));
            imgui.InputTextWithHint('##evn', 'e.g. Dynamis Xarcabard', ui.evName, 48);
        end
        imgui.SameLine();
        local other = (ui.campMob == 'Other (type a name)');
        if button('Start camp', (ui.campMob ~= nil) and ((not other) or ui.evName[1] ~= '')) then
            if other then start_event(ui.evName[1], me()); else start_event(nil, me(), ui.campMob); end
            ui.evName[1] = '';
        end
        imgui.SameLine();
        if button('One-off ready check', db.rc == nil) then open_rc(me()); end
    else
        imgui.TextColored(C.accent, ev.name);
        imgui.SameLine();
        if imgui.Button('End event') then stop_event(me()); end
        imgui.SameLine();
        if (db.rc == nil) then
            if imgui.Button('Ready check now') then open_rc(me()); ev.nextRc = os.time() + db.cfg.tickMin * 60; end
        end
    end
    local t = { db.cfg.tickMin }; local w = { db.cfg.rcWindow }; local p = { db.cfg.dkpPerTick }; local k = { db.cfg.killBonus };
    label('Every'); imgui.SameLine(); small_input_int('min##tick', t, 50);
    imgui.SameLine(); label('answer within'); imgui.SameLine(); small_input_int('s##win', w, 50);
    imgui.SameLine(); label('DKP per tick'); imgui.SameLine(); small_input_int('##dpt', p, 40);
    imgui.SameLine(); label('kill bonus'); imgui.SameLine(); small_input_int('##kb', k, 40);
    if (t[1] ~= db.cfg.tickMin) or (w[1] ~= db.cfg.rcWindow) or (p[1] ~= db.cfg.dkpPerTick) or (k[1] ~= db.cfg.killBonus) then
        db.cfg.tickMin, db.cfg.rcWindow = math.max(5, t[1]), math.max(20, w[1]);
        db.cfg.dkpPerTick, db.cfg.killBonus = math.max(0, p[1]), math.max(0, k[1]);
        touch();
    end

    section('Auto camps');
    label('Once one of these has a ToD, its camp starts by itself before the window opens.');
    local lead = { db.cfg.autoLead }; local after = { db.cfg.endAfterKill };
    label('Start'); imgui.SameLine(); small_input_int('min before the window##lead', lead, 40);
    imgui.SameLine(); check('End', 'endOnKill'); imgui.SameLine(); small_input_int('min after the kill##after', after, 40);
    if (lead[1] ~= db.cfg.autoLead) or (after[1] ~= db.cfg.endAfterKill) then
        db.cfg.autoLead, db.cfg.endAfterKill = math.max(0, lead[1]), math.max(0, after[1]); touch();
    end
    local autos = {};
    for key in pairs(db.autoCamp) do autos[#autos + 1] = key; end
    table.sort(autos);
    for _, key in ipairs(autos) do
        imgui.TextColored(C.text, key);
        imgui.SameLine(ui.px(160));
        local at = auto_start_time(key);
        if (db.event ~= nil) and (db.event.mob == key) then imgui.TextColored(C.good, 'running now');
        elseif at then imgui.TextColored(C.accent, ('starts %s (in %s)'):format(clock(at), dur(at - os.time())));
        else imgui.TextColored(C.dim, 'waiting for a ToD'); end
        imgui.SameLine(ui.px(420));
        if imgui.SmallButton('Remove##au' .. key) then set_auto(key, false); end
    end
    ui.autoMob = mob_combo('##automob', ui.autoMob, 220, true);
    imgui.SameLine();
    if button('Auto-start this camp', (ui.autoMob ~= nil) and db.autoCamp[ui.autoMob] == nil) then
        print(TAG .. set_auto(ui.autoMob, true)); ui.autoMob = nil;
    end

    local rc = db.rc;
    if (rc ~= nil) then
        section(('Ready check: %s left'):format(dur(rc.closes - os.time())));
        imgui.SameLine();
        if imgui.SmallButton('Close now') then close_rc(); return; end
        imgui.SameLine(); if imgui.SmallButton('+1 min') then rc.closes = rc.closes + 60; touch(); end
        label('Ticked = gets the DKP. Alliance in your zone is ticked for you; untick anyone who should not count.');
        rc.excluded = rc.excluded or {};
        local here = alliance_here();
        local names, seen = {}, {};
        local function add(n) if not seen[n] then seen[n] = true; names[#names + 1] = n; end end
        for n in pairs(here) do add(n); end
        for n in pairs(rc.auto) do add(n); end
        for n in pairs(rc.replied) do add(n); end
        for n in pairs(db.members) do add(n); end
        table.sort(names);
        if imgui.BeginChild('##rcl', { 0, ui.px(150) }, ImGuiChildFlags_Borders) then
            local col = 0;
            for _, n in ipairs(names) do
                local on = (here[n] or rc.auto[n] or rc.replied[n]) and not rc.excluded[n];
                local b = { on and true or false };
                if (col > 0) then imgui.SameLine(col * 150); end
                if imgui.Checkbox(n .. '##rc', b) then
                    if b[1] then rc.excluded[n] = nil; rc.replied[n] = true; member(n);
                    else rc.excluded[n] = true; rc.replied[n] = nil; end
                    touch();
                end
                col = (col + 1) % 4;
            end
        end
        imgui.EndChild();
        imgui.SetNextItemWidth(ui.px(130));
        imgui.InputTextWithHint('##rcn', 'Someone not listed', ui.rcNew, 16);
        imgui.SameLine();
        if button('Mark present', ui.rcNew[1] ~= '') then
            local _, n = member(ui.rcNew[1]);
            rc.replied[n], rc.excluded[n] = true, nil;
            ui.rcNew[1] = '';
            touch();
        end
    end

    section('Recent ticks');
    if imgui.BeginChild('##ticks', { 0, 0 }, ImGuiChildFlags_Borders) then
        local shown = 0;
        for i = #db.history, 1, -1 do
            local e = db.history[i];
            if (e.kind == 'tick' or e.kind == 'kill' or e.kind == 'check') and (shown < 12) then
                shown = shown + 1;
                imgui.TextColored(e.undone and C.dim or C.accent, ('%s  %s%s'):format(stamp(e.t), e.text, e.undone and '  (undone)' or ''));
                imgui.TextWrapped(table.concat(e.names or {}, ', '));
            end
        end
        if (shown == 0) then label('None yet.'); end
    end
    imgui.EndChild();
end

---------------------------------------------------------------------------------------------------------------------
local function tab_loot()
    if imgui.BeginTable('##loot', 5, TABLE_FLAGS, { 0, ui.lootSel and -ui.px(40) or 0 }) then
        imgui.TableSetupScrollFreeze(0, 1);
        imgui.TableSetupColumn('When', ImGuiTableColumnFlags_WidthStretch, 1.1);
        imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch, 1.6);
        imgui.TableSetupColumn('From', ImGuiTableColumnFlags_WidthStretch, 1.2);
        imgui.TableSetupColumn('Went to', ImGuiTableColumnFlags_WidthStretch, 1.6);
        imgui.TableSetupColumn('Shot', ImGuiTableColumnFlags_WidthFixed, ui.px(30));
        imgui.TableHeadersRow();
        for i = #db.drops, 1, -1 do
            local d = db.drops[i];
            imgui.TableNextRow();
            imgui.TableNextColumn();
            if imgui.Selectable(stamp(d.t) .. '##l' .. d.id, ui.lootSel == d.id, ImGuiSelectableFlags_SpanAllColumns) then
                ui.lootSel = (ui.lootSel == d.id) and nil or d.id;
            end
            imgui.TableNextColumn(); imgui.TextColored(C.text, d.item);
            imgui.TableNextColumn(); imgui.TextColored(C.dim, d.mob or '');
            imgui.TableNextColumn();
            if (d.awarded ~= nil) then
                imgui.TextColored(C.good, ('%s, %d DKP'):format(d.awarded, d.price or 0));
                if (d.lotted ~= nil) and (d.lotted ~= d.awarded) then imgui.SameLine(); imgui.TextColored(C.warn, '(lot: ' .. d.lotted .. ')'); end
            elseif (d.lotted ~= nil) then imgui.TextColored(C.text, d.lotted .. ' (lot)');
            else imgui.TextColored(C.dim, '-'); end
            imgui.TableNextColumn();
            imgui.TextColored(d.shot and C.accent or C.dim, d.shot and 'yes' or '');
        end
        if (#db.drops == 0) then
            imgui.TableNextRow(); imgui.TableNextColumn();
            label('Drops from tracked mobs (and anything during an event) show up here.');
        end
        imgui.EndTable();
    end
    local d = ui.lootSel and drop_by_id(ui.lootSel);
    if (d == nil) then ui.lootSel = nil; return; end
    if read_only() then return; end
    imgui.Separator();
    imgui.TextColored(C.accent, d.item);
    imgui.SameLine();
    if button('Auction it', (db.auction == nil) and (d.awarded == nil)) then start_auction(d.item, nil, me(), d.id); ui.goTab = 'Auction'; end
    imgui.SameLine();
    if button('Award by hand', d.awarded == nil) then
        ui.awardItem[1], ui.awardDrop, ui.awardPrice[1] = d.item, d.id, price_for(d.item);
        ui.goTab = 'Auction';
    end
    imgui.SameLine();
    if button('Open screenshot', d.shot ~= nil) then ashita.misc.open_url(d.shot); end
    imgui.SameLine(); label('min price'); imgui.SameLine();
    ui.lootMin = ui.lootMin or { 0 };
    if (ui.lootMinFor ~= d.id) then ui.lootMinFor, ui.lootMin[1] = d.id, price_for(d.item); end
    small_input_int('##lootmin', ui.lootMin, 60);
    imgui.SameLine();
    if button('Set', (not read_only()) and (ui.lootMin[1] ~= price_for(d.item))) then set_price(item_key(d.item), d.item, math.max(0, ui.lootMin[1])); end
    imgui.SameLine();
    if imgui.Button('Delete entry') then
        del_drop(d.id);
        ui.lootSel = nil;
    end
end

---------------------------------------------------------------------------------------------------------------------
local function tab_history()
    imgui.SetNextItemWidth(ui.px(180));
    imgui.InputTextWithHint('##hf', 'Filter (name, item, mob)', ui.histFilter, 32);
    imgui.SameLine();
    if button('Undo last change', not read_only()) then
        local e = undo_last(me());
        print(TAG .. (e and ('Undid: ' .. (e.text or e.kind)) or 'Nothing to undo.'));
    end
    imgui.SameLine();
    if imgui.Button('Export CSV') then run('export', ''); end
    imgui.SameLine();
    if imgui.Button('Open folder') then ashita.misc.open_url(ROOT); end
    local f = ui.histFilter[1]:lower();
    if imgui.BeginChild('##hist', { 0, 0 }, ImGuiChildFlags_Borders) then
        for i = #db.history, 1, -1 do
            local e = db.history[i];
            local line = tostring(e.text or e.kind);
            if (f == '') or line:lower():find(f, 1, true) or table.concat(e.names or {}, ' '):lower():find(f, 1, true) then
                imgui.TextColored(C.dim, stamp(e.t));
                imgui.SameLine();
                imgui.TextColored(e.undone and C.dim or (e.kind == 'win' and C.accent or C.text), line .. (e.undone and '  (undone)' or ''));
                if (e.by ~= nil) and (e.by ~= 'auto') then imgui.SameLine(); imgui.TextColored(C.dim, 'by ' .. e.by); end
            end
        end
    end
    imgui.EndChild();
end

---------------------------------------------------------------------------------------------------------------------
local function tab_settings()
    -- Five short pages instead of one long scroll.
    if imgui.BeginTabBar('##settabs') then
        if imgui.BeginTabItem('General') then
            if imgui.BeginChild('##set_general', { 0, 0 }, ImGuiChildFlags_None) then
                section('Window style');
                local names = {};
                for _, t in ipairs(ui.THEMES) do names[#names + 1] = t.name; end
                local pickT = combo('##theme', ui.theme().name, names, 170);
                for _, t in ipairs(ui.THEMES) do if (t.name == pickT) and (t.key ~= db.cfg.theme) then db.cfg.theme = t.key; touch(); end end
                imgui.SameLine(); label('opacity'); imgui.SameLine();
                local op = { db.cfg.opacity or 100 }; small_input_int('%##opac', op, 60);
                if (op[1] ~= db.cfg.opacity) then db.cfg.opacity = math.max(30, math.min(100, op[1])); touch(); end
                section('Moogle button');
                check('Show the moogle on screen', 'showPill', 'Click it to open or close HeaphKP. Drag it to move it.');
                local st = combo('##istyle', (db.cfg.iconStyle == 'round') and 'Round moogle' or 'Clock moogle', { 'Clock moogle', 'Round moogle' }, 150);
                local want = (st == 'Round moogle') and 'round' or 'clock';
                if (want ~= (db.cfg.iconStyle or 'clock')) then db.cfg.iconStyle = want; touch(); end
                imgui.SameLine(); label('size'); imgui.SameLine();
                local isz = { db.cfg.iconSize or 70 }; small_input_int('##isize', isz, 60);
                if (isz[1] ~= db.cfg.iconSize) then db.cfg.iconSize = math.max(40, math.min(200, isz[1])); touch(); end
                imgui.SameLine(); check('Bob', 'iconBob');
                label('The clock counts down to the next known window: 21h05, then 05:00, then OPEN. Gold within your alert time.');
                section('Window alerts');
                check('Alert before known windows', 'notifyOn');
                imgui.SameLine(); local nl = { db.cfg.notifyLead }; small_input_int('min before##nl', nl, 50);
                if (nl[1] ~= db.cfg.notifyLead) then db.cfg.notifyLead = math.max(1, nl[1]); touch(); end
                check('Chime', 'notifySound'); imgui.SameLine(); check('Also post them to the LS (during events)', 'notifyLS');
                imgui.SameLine();
                if imgui.SmallButton('Test') then notify('Test: King Arthro window opens in 30 min.'); end
                section('Time');
                label(('Times show in your zone (%s). LS posts say the zone and a countdown, so every member reads them right.'):format(zone()));
                label(((access.clockOffset or 0) ~= 0) and ('Your PC clock is %+ds off the server; HeaphKP corrects it.'):format(-(access.clockOffset or 0))
                    or 'Your PC clock matches the sync server.');
            end
            imgui.EndChild();
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Chat') then
            if imgui.BeginChild('##set_chat', { 0, 0 }, ImGuiChildFlags_None) then
                section('Chat control');
                label('Everything works from this window. Turn on only the chat you want the addon to listen to or say.');
                check('Post announcements', 'announce', 'Ready checks, ticks, auctions and results go to the channel below. Off = only you see them.');
                imgui.SameLine();
                local ch = combo('##ch', db.cfg.channel, { 'l', 'l2', 'p' }, 60);
                if (ch ~= db.cfg.channel) then db.cfg.channel = ch; touch(); end
                imgui.SameLine(); label('l = linkshell, l2 = second linkshell, p = party');
                check('People can answer ready checks by saying "here"', 'chatHere');
                check('People can bid in chat ("bid 120")', 'chatBids');
                check('People can ask their balance ("!dkp")', 'chatBalance');
                check('Officers can run things from chat (!auction, !tod, !award...)', 'chatCommands',
                    'Off by default. When on, the roles below decide who can use which.');
                check('Answer people by tell', 'replyTells', 'Bid refusals, sealed-bid receipts and balances.');
                check('Answer roll calls', 'answerRollCall', 'When a keeper posts "[DKP] Roll call", tell them you run HeaphKP (once per asker per 10 min).');
                check('Post HNM ToDs to the LS', 'todPost', 'Only while an event is running, and only from officers, admins and the owner. Everyone else just records them.');
                imgui.Spacing();
                label('What each role can do from chat:');
                for _, a in ipairs(ACTIONS) do
                    imgui.TextColored(C.text, a.label); imgui.SameLine(ui.px(210));
                    local nr = combo('##need' .. a.key, db.cfg.need[a.key], ROLES, 100);
                    if (nr ~= db.cfg.need[a.key]) then db.cfg.need[a.key] = nr; touch(); end
                end
            end
            imgui.EndChild();
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Bidding') then
            if imgui.BeginChild('##set_bid', { 0, 0 }, ImGuiChildFlags_None) then
                section('Bidding');
                local x = { db.cfg.bidExtend }; local inc = { db.cfg.increment }; local mn = { db.cfg.defaultMin };
                label('late-bid reset'); imgui.SameLine(); small_input_int('s##be', x, 50);
                imgui.SameLine(); label('min raise'); imgui.SameLine(); small_input_int('##inc', inc, 50);
                imgui.SameLine(); label('default min price'); imgui.SameLine(); small_input_int('##dm', mn, 60);
                if (x[1] ~= db.cfg.bidExtend) or (inc[1] ~= db.cfg.increment) or (mn[1] ~= db.cfg.defaultMin) then
                    db.cfg.bidExtend, db.cfg.increment, db.cfg.defaultMin = math.max(0, x[1]), math.max(1, inc[1]), math.max(0, mn[1]);
                    touch();
                end
                check('Allow bidding past your balance', 'allowNeg');
                imgui.SameLine(); check('Anyone who answers a ready check joins the roster', 'openRoster');
                section('Minimum prices');
                local keys = {};
                for kk in pairs(db.prices) do keys[#keys + 1] = kk; end
                table.sort(keys);
                for _, kk in ipairs(keys) do
                    local p = db.prices[kk];
                    imgui.TextColored(C.text, p.name); imgui.SameLine(ui.px(220));
                    local v = { p.min }; small_input_int('##pv' .. kk, v, 70);
                    if (v[1] ~= p.min) and not imgui.IsItemActive() then set_price(kk, p.name, math.max(0, v[1])); end
                    if (v[1] ~= p.min) and imgui.IsItemActive() then p.min = math.max(0, v[1]); end
                    if imgui.IsItemDeactivatedAfterEdit() then set_price(kk, p.name, p.min); end
                    imgui.SameLine(); if imgui.SmallButton('Remove##pr' .. kk) then del_price(kk); end
                end
                imgui.SetNextItemWidth(ui.px(210)); imgui.InputTextWithHint('##pi', 'Item name', ui.priceItem, 64);
                imgui.SameLine(); small_input_int('##pm', ui.priceMin, 70);
                imgui.SameLine();
                if button('Add price', ui.priceItem[1] ~= '') then
                    set_price(item_key(ui.priceItem[1]), ui.priceItem[1], math.max(0, ui.priceMin[1]));
                    ui.priceItem[1], ui.priceMin[1] = '', 0;
                end
            end
            imgui.EndChild();
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Timers & loot') then
            if imgui.BeginChild('##set_timers', { 0, 0 }, ImGuiChildFlags_None) then
                section('Drop screenshots');
                local sm = combo('##shot', db.cfg.shotMode, { 'tracked', 'all', 'off' }, 100);
                if (sm ~= db.cfg.shotMode) then db.cfg.shotMode = sm; touch(); end
                imgui.SameLine(); label('tracked = HNM/NM drops, priced items, anything during an event');
                section('Extra mobs to time');
                for name, c in pairs(db.custom) do
                    imgui.TextColored(C.text, name); imgui.SameLine(ui.px(200));
                    imgui.TextColored(C.dim, ('%s - %s'):format(dur(c.minS), dur(c.maxS)));
                    imgui.SameLine(ui.px(330)); if imgui.SmallButton('Remove##c' .. name) then del_custom(name); end
                end
                imgui.SetNextItemWidth(ui.px(160)); imgui.InputTextWithHint('##tn', 'Mob name', ui.trackName, 32);
                imgui.SameLine(); label('respawn'); imgui.SameLine(); small_input_int('##tl', ui.trackLo, 40);
                imgui.SameLine(); label('to'); imgui.SameLine(); small_input_int('h##th', ui.trackHi, 40);
                imgui.SameLine();
                if button('Track', (ui.trackName[1] ~= '') and (ui.trackHi[1] >= ui.trackLo[1]) and ui.trackHi[1] > 0) then
                    set_custom(ui.trackName[1], ui.trackLo[1] * 3600, ui.trackHi[1] * 3600);
                    ui.trackName[1] = '';
                end
            end
            imgui.EndChild();
            imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Server') then
            if imgui.BeginChild('##set_server', { 0, 0 }, ImGuiChildFlags_None) then
                section('Sync server');
                if (ui.serverBuf == nil) then ui.serverBuf = { access.server or '' }; end
                imgui.SetNextItemWidth(ui.px(320)); imgui.InputText('##srv', ui.serverBuf, 128);
                imgui.SameLine();
                if button('Save', ui.serverBuf[1] ~= access.server) then access.server = ui.serverBuf[1]; save_access(); end
                local simple = { net ~= nil and net.blocking or false };
                if imgui.Checkbox('Simple network mode', simple) and (net ~= nil) then net.blocking = simple[1]; access.blocking = simple[1]; save_access(); end
                if imgui.IsItemHovered() then imgui.SetTooltip('Use only if syncing keeps failing. The game pauses briefly on each sync.'); end
                imgui.SameLine();
                local skip = { access.tlsSkip and true or false };
                if imgui.Checkbox('Skip certificate check', skip) and (net ~= nil) then access.tlsSkip = skip[1]; net.verify = not skip[1]; save_access(); end
                if imgui.IsItemHovered() then imgui.SetTooltip('The server certificate is checked against assets\\cacert.pem. Skip only if that check fails on your PC.'); end
                imgui.Spacing();
                if (bookKey ~= 'local') and can_manage() then
                    section('API keys (bots, Discord, websites)');
                    label('A key reads the book (viewer) or also writes ToDs, adjustments and awards (officer), signed as bot:<label>.');
                    for _, k in ipairs(db.keys or {}) do
                        imgui.TextColored(C.text, k.name); imgui.SameLine(ui.px(170));
                        imgui.TextColored(C.dim, ('%s, used %s'):format(k.role, (k.last_seen or 0) > 0 and (dur(os.time() - k.last_seen) .. ' ago') or 'never'));
                        imgui.SameLine(ui.px(360));
                        if imgui.SmallButton('Revoke##k' .. k.name) then HK.revoke_key(k.label); end
                    end
                    imgui.SetNextItemWidth(ui.px(140)); imgui.InputTextWithHint('##klabel', 'Label, e.g. Discord', ui.keyLabel, 20);
                    imgui.SameLine(); ui.keyRole = combo('##krole', ui.keyRole, { 'viewer', 'officer' }, 90);
                    imgui.SameLine();
                    if button('Make key', ui.keyLabel[1] ~= '') then HK.make_key(ui.keyLabel[1], ui.keyRole); ui.keyLabel[1] = ''; end
                    if (ui.newKey[1] ~= '') then
                        imgui.TextColored(C.warn, 'New key (select and Ctrl+C; it will not be shown again):');
                        imgui.SetNextItemWidth(ui.px(420)); imgui.InputText('##knew', ui.newKey, 80);
                        imgui.SameLine(); if imgui.SmallButton('Hide') then ui.newKey[1] = ''; end
                    end
                end
            end
            imgui.EndChild();
            imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
end

---------------------------------------------------------------------------------------------------------------------
-- Members: who is in the book, who to invite, who asked to join.
local function tab_members()
    if imgui.BeginChild('##members', { 0, 0 }, ImGuiChildFlags_None) then
        section('Roles');
        if synced() then
            label('Shared book: roles live on the server. viewer = can open the book, officer = can run it,');
            label('admin = also roles and roster. Only the owner makes admins. Invites go out by tell to that character,');
            label('so a name is registered only by the player who holds it; every change is signed with the sender\'s name.');
            for name, r in pairs(db.perms) do
                imgui.TextColored(C.text, name); imgui.SameLine(ui.px(150));
                local sn = db.seen[name];
                if (sn ~= nil) and (sn.joined ~= nil) then
                    imgui.TextColored(C.dim, ('joined %s, seen %s ago'):format(os.date('%m/%d', sn.joined), dur(os.time() - (sn.last or sn.joined))));
                else
                    imgui.TextColored(C.warn, 'invited, not joined');
                end
                imgui.SameLine(ui.px(390));
                if (r == 'owner') or (not can_manage()) then imgui.TextColored(C.accent, r);
                else
                    local nr = combo('##pr' .. name, r, SROLES, 90);
                    if (nr ~= r) then set_role(name, nr); end
                    imgui.SameLine(); if imgui.SmallButton('Remove##p' .. name) then set_role(name, 'member'); end
                end
            end
            if can_manage() then
                ui.permName = member_combo('##pn', ui.permName);
                imgui.SameLine(); ui.permRole = combo('##prole', ui.permRole, { 'viewer', 'officer', 'admin' }, 100);
                imgui.SameLine();
                if button('Send invite', valid_name(ui.permName)) then send_invite(ui.permName, ui.permRole); end
                imgui.SameLine();
                local tn = HK.target_name();
                if button(tn and ('Invite target: ' .. tn) or 'Invite target', tn ~= nil) then add_member(tn); send_invite(tn, ui.permRole); end
                if imgui.IsItemHovered() then imgui.SetTooltip('The player you have targeted gets the role picked on the left.'); end
            end
        else
            label(('You (%s) are always admin. Anyone not listed here is a member. Roles only matter for chat control.'):format(me() or '?'));
            for name, r in pairs(db.perms) do
                imgui.TextColored(C.text, name); imgui.SameLine(ui.px(150));
                local nr = combo('##pr' .. name, r, ROLES, 100);
                if (nr ~= r) then set_role(name, nr); end
                imgui.SameLine(); if imgui.SmallButton('Remove##p' .. name) then set_role(name, 'member'); end
            end
            ui.permName = member_combo('##pn', ui.permName);
            imgui.SameLine(); ui.permRole = combo('##prole', ui.permRole, ROLES, 100);
            imgui.SameLine();
            if button('Set role', valid_name(ui.permName)) then set_role(ui.permName, ui.permRole); end
        end
        section('Who has HeaphKP?');
        if imgui.Button('Ask the linkshell') then run('rollcall', ''); end
        if imgui.IsItemHovered() then imgui.SetTooltip('Posts one line in the LS; everyone running HeaphKP answers you by tell.'); end
        imgui.SameLine();
        local tn = HK.target_name();
        if button(tn and ('Ask target: ' .. tn) or 'Ask target', tn ~= nil) then run('rollcall', 't'); end
        imgui.SameLine(); label('as'); imgui.SameLine();
        ui.rcRole = combo('##rcrole', ui.rcRole or 'viewer', { 'viewer', 'officer', 'admin' }, 90);
        local names = {};
        for n in pairs(HK.rollcall or {}) do names[#names + 1] = n; end
        table.sort(names);
        if (#names == 0) then
            label(HK.rollcallAt and ('No answers yet (asked %s ago).'):format(dur(os.time() - HK.rollcallAt)) or 'Nobody asked yet.');
        else
            local canInv = (bookKey ~= 'local') and can_manage();
            local fresh = 0;
            for _, n in ipairs(names) do
                local a = HK.rollcall[n];
                local inBook = (db.perms[n] ~= nil);
                imgui.TextColored(C.text, n); imgui.SameLine(ui.px(150));
                imgui.TextColored(inBook and C.good or C.dim, inBook and ('in the book (%s)'):format(db.perms[n]) or ('has HeaphKP %s'):format(a.ver));
                imgui.SameLine(ui.px(340));
                if (not inBook) then
                    fresh = fresh + 1;
                    if button('Invite##rc' .. n, canInv) then add_member(n); send_invite(n, ui.rcRole or 'viewer'); end
                end
            end
            if (fresh > 0) and button(('Invite all %d as %s'):format(fresh, ui.rcRole or 'viewer'), canInv) then
                for _, n in ipairs(names) do if (db.perms[n] == nil) then add_member(n); send_invite(n, ui.rcRole or 'viewer'); end end
            end
            if (not canInv) then label(bookKey == 'local' and 'Share the book (Turn on DKP) to invite them.' or 'Only the owner or an admin invites.'); end
            imgui.SameLine(); if imgui.SmallButton('Clear##rc') then HK.rollcall = {}; end
        end

        local reqs = {};
        for n in pairs(HK.joinReq or {}) do reqs[#reqs + 1] = n; end
        table.sort(reqs);
        if (#reqs > 0) then
            section(('Join requests (%d typed !join heaphkp)'):format(#reqs));
            local canInv = (bookKey ~= 'local') and can_manage();
            for _, n in ipairs(reqs) do
                imgui.TextColored(C.text, n); imgui.SameLine(ui.px(150));
                if (db.perms[n] ~= nil) then
                    imgui.TextColored(C.good, ('already in the book (%s)'):format(db.perms[n]));
                    imgui.SameLine(); if imgui.SmallButton('Dismiss##jr' .. n) then HK.joinReq[n] = nil; end
                else
                    imgui.TextColored(C.dim, ('asked %s ago'):format(dur(os.time() - HK.joinReq[n])));
                    imgui.SameLine(ui.px(340));
                    if button('Approve##jr' .. n, canInv) then HK.approve_join(n, ui.rcRole or 'viewer'); end
                    imgui.SameLine(); if imgui.SmallButton('Dismiss##jd' .. n) then HK.joinReq[n] = nil; end
                end
            end
            if button(('Approve all as %s'):format(ui.rcRole or 'viewer'), canInv) then
                for _, n in ipairs(reqs) do if (db.perms[n] == nil) then HK.approve_join(n, ui.rcRole or 'viewer'); else HK.joinReq[n] = nil; end end
            end
            if (not canInv) then label(bookKey == 'local' and 'Share the book (Turn on DKP) to approve them.' or 'Only the owner or an admin approves.'); end
        end

        local reqs = {};
        for n in pairs(HK.joinReq or {}) do reqs[#reqs + 1] = n; end
        table.sort(reqs);
        if (#reqs > 0) then
            section(('Join requests (%d typed !join heaphkp)'):format(#reqs));
            local canInv = (bookKey ~= 'local') and can_manage();
            for _, n in ipairs(reqs) do
                imgui.TextColored(C.text, n); imgui.SameLine(ui.px(150));
                if (db.perms[n] ~= nil) then
                    imgui.TextColored(C.good, ('already in the book (%s)'):format(db.perms[n]));
                    imgui.SameLine(); if imgui.SmallButton('Dismiss##jr' .. n) then HK.joinReq[n] = nil; end
                else
                    imgui.TextColored(C.dim, ('asked %s ago'):format(dur(os.time() - HK.joinReq[n])));
                    imgui.SameLine(ui.px(340));
                    if button('Approve##jr' .. n, canInv) then HK.approve_join(n, ui.rcRole or 'viewer'); end
                    imgui.SameLine(); if imgui.SmallButton('Dismiss##jd' .. n) then HK.joinReq[n] = nil; end
                end
            end
            if button(('Approve all as %s'):format(ui.rcRole or 'viewer'), canInv) then
                for _, n in ipairs(reqs) do if (db.perms[n] == nil) then HK.approve_join(n, ui.rcRole or 'viewer'); else HK.joinReq[n] = nil; end end
            end
            if (not canInv) then label(bookKey == 'local' and 'Share the book (Turn on DKP) to approve them.' or 'Only the owner or an admin approves.'); end
        else
            label('When someone types !join heaphkp in the LS, they show up here for you to approve.');
        end
    end
    imgui.EndChild();
end

---------------------------------------------------------------------------------------------------------------------
local function tab_linkshells()
    local now = os.time();
    if (bookKey ~= 'local') then section('ToD sharing'); ui.share_switch(); end
    section('Your linkshells');
    local eq = equipped_ls();
    if (#eq == 0) then label('No linkshell or pearl equipped.'); end
    for _, l in ipairs(eq) do
        local key = l.name:lower();
        imgui.TextColored(C.text, l.name);
        imgui.SameLine(ui.px(170));
        imgui.TextColored(l.owner and C.accent or C.dim, l.owner and 'Linkshell (you own it)' or l.kind);
        imgui.SameLine(ui.px(340));
        local b = access.books[key];
        if (b ~= nil) then
            if (bookKey == key) then imgui.TextColored(C.good, 'open now');
            elseif imgui.SmallButton('Open##ls' .. key) then switch_book(key); end
        elseif l.owner then
            if imgui.SmallButton('Turn on DKP##reg' .. key) then register_ls(l.name, ui.bring[1] and (bookKey == 'local')); end
            if imgui.IsItemHovered() then imgui.SetTooltip('Registers this LS on the sync server with you as owner.'); end
        else
            label('ask the owner for an invite');
        end
    end
    if (bookKey == 'local') then
        imgui.Checkbox("Bring this PC's book along when turning DKP on", ui.bring);
    end
    label('Only whoever has the LS item itself (not a sack or pearl) equipped can turn DKP on for it.');

    if (#pendingInvites > 0) then
        section('Invites');
        for i = #pendingInvites, 1, -1 do
            local v = pendingInvites[i];
            imgui.TextColored(C.text, ('%s as %s'):format(v.ls, v.role));
            imgui.SameLine(); label(('from %s, %s'):format(v.from, clock(v.t)));
            imgui.SameLine();
            if imgui.SmallButton('Accept##inv' .. i) then join_ls(v.ls, v.code); table.remove(pendingInvites, i);
            else
                imgui.SameLine();
                if imgui.SmallButton('Ignore##inv' .. i) then table.remove(pendingInvites, i); end
            end
        end
    end

    section('Books you can open');
    imgui.TextColored(C.text, 'This PC only');
    imgui.SameLine(ui.px(170)); label('not shared');
    imgui.SameLine(ui.px(340));
    if (bookKey == 'local') then imgui.TextColored(C.good, 'open now'); elseif imgui.SmallButton('Open##local') then switch_book('local'); end
    local keys = {};
    for k in pairs(access.books) do keys[#keys + 1] = k; end
    table.sort(keys);
    for _, k in ipairs(keys) do
        local b = access.books[k];
        imgui.TextColored(C.text, b.ls);
        imgui.SameLine(ui.px(170));
        imgui.TextColored(b.revoked and C.bad or C.dim, b.revoked and 'access removed' or (b.role or '?'));
        imgui.SameLine(ui.px(340));
        if (bookKey == k) then imgui.TextColored(C.good, 'open now');
        elseif imgui.SmallButton('Open##b' .. k) then switch_book(k); end
        imgui.SameLine();
        if (ui.confirmLeave == k) then
            if imgui.SmallButton('Really forget it?##lv' .. k) then
                if (bookKey == k) then switch_book('local'); end
                access.books[k] = nil;
                save_access();
                ui.confirmLeave = nil;
            end
        elseif imgui.SmallButton('Forget##lv' .. k) then
            ui.confirmLeave = k;
        end
        if imgui.IsItemHovered() then imgui.SetTooltip('Removes it from this PC. Your access on the server stays until an admin removes it.'); end
    end
    if (bookKey ~= 'local') and (book() ~= nil) then
        local b = book();
        label(('Sync: %s%s'):format(b.lastSync and ('last %s ago'):format(dur(now - b.lastSync)) or 'not yet',
            b.err and ('  |  ' .. b.err) or ''));
        if imgui.SmallButton('Sync now') then sync.next = 0; end
        imgui.SameLine();
        if imgui.SmallButton('Reload from server') then reload_from_server(); end
        if imgui.IsItemHovered() then imgui.SetTooltip("Throws away this PC's copy and pulls the whole book again."); end
    end

    section('Join with a code');
    imgui.SetNextItemWidth(ui.px(150)); imgui.InputTextWithHint('##jls', 'Linkshell name', ui.joinLs, 24);
    imgui.SameLine(); imgui.SetNextItemWidth(ui.px(110)); imgui.InputTextWithHint('##jcode', 'ABCD-EFGH', ui.joinCode, 12);
    imgui.SameLine();
    if button('Join', (ui.joinLs[1] ~= '') and (ui.joinCode[1] ~= '')) then
        join_ls(ui.joinLs[1], ui.joinCode[1], function () ui.joinLs[1], ui.joinCode[1] = '', ''; end);
    end
    if (bookKey ~= 'local') and (book() ~= nil) then
        section(('Where %s posts'):format(book().ls));
        local pp = { db.cfg.channel == 'p' };
        if imgui.Checkbox('Party chat instead of the linkshell', pp) then db.cfg.channel = pp[1] and 'p' or 'l'; touch(); end
        imgui.SameLine();
        local ch, why = ls_guard();
        if ch then imgui.TextColored(C.good, ('posting to /%s'):format(ch)); else imgui.TextColored(C.warn, 'not posting: ' .. why); end
        label('Only this LS hears its ToDs, ready checks and auctions. Which slot it is in (LS1/LS2) is read from your equipment.');
    end
    if (lsMsg ~= nil) then imgui.TextWrapped(lsMsg); end
end

local function tab_help()
    section('Commands');
    for _, line in ipairs(HK.help_lines(false)) do imgui.TextWrapped(line); end
    section('In chat (when switched on in Settings)');
    for _, line in ipairs(HK.help_lines(true)) do imgui.TextWrapped(line); end
    section('Mob aliases');
    local keys = {};
    for k in pairs(HK.ALIAS) do keys[#keys + 1] = k; end
    table.sort(keys);
    local col = 0;
    for _, k in ipairs(keys) do
        if (col > 0) then imgui.SameLine(ui.px(col * 150)); end
        imgui.TextColored(C.accent, k); imgui.SameLine(); imgui.TextColored(C.text, HK.ALIAS[k]);
        col = (col + 1) % 4;
    end
end

local TABS = {
    { 'Standings', tab_standings }, { 'Auction', tab_auction }, { 'Timers', tab_timers }, { 'Attendance', tab_attendance },
    { 'Loot', tab_loot }, { 'Members', tab_members }, { 'Linkshells', tab_linkshells }, { 'History', tab_history },
    { 'Settings', tab_settings }, { 'Help', tab_help },
};

-- Look: the same style as the luashitacast HUD windows - the FFXI Window1 card
-- texture behind every window, Verdana Bold at 1.5x the game's imgui font, gold and white text (no grey), and every
-- size scaled from the font so it reads the same on a 4K screen as on 1080p.
local STYLE_COLORS = {
    { ImGuiCol_Text,              { 0.92, 0.92, 0.95, 1.00 } },
    { ImGuiCol_WindowBg,          { 0.00, 0.00, 0.00, 0.00 } },
    { ImGuiCol_ChildBg,           { 0.00, 0.00, 0.00, 0.00 } },
    { ImGuiCol_PopupBg,           { 0.07, 0.07, 0.22, 0.97 } },
    { ImGuiCol_Border,            { 0.62, 0.60, 0.80, 0.40 } },
    { ImGuiCol_FrameBg,           { 0.05, 0.05, 0.18, 0.72 } },
    { ImGuiCol_FrameBgHovered,    { 0.12, 0.12, 0.32, 0.85 } },
    { ImGuiCol_FrameBgActive,     { 0.16, 0.16, 0.40, 0.90 } },
    { ImGuiCol_Tab,               { 0.14, 0.14, 0.36, 0.85 } },
    { ImGuiCol_TabHovered,        { 0.40, 0.36, 0.74, 0.95 } },
    { ImGuiCol_TabSelected,       { 0.32, 0.29, 0.62, 0.95 } },
    { ImGuiCol_TabSelectedOverline, { 1.00, 0.84, 0.45, 1.00 } },
    { ImGuiCol_Button,            { 0.20, 0.20, 0.48, 0.85 } },
    { ImGuiCol_ButtonHovered,     { 0.34, 0.31, 0.68, 0.95 } },
    { ImGuiCol_ButtonActive,      { 0.45, 0.40, 0.85, 1.00 } },
    { ImGuiCol_Header,            { 0.55, 0.45, 0.18, 0.45 } },
    { ImGuiCol_HeaderHovered,     { 0.38, 0.35, 0.72, 0.55 } },
    { ImGuiCol_HeaderActive,      { 0.55, 0.45, 0.18, 0.65 } },
    { ImGuiCol_Separator,         { 0.55, 0.60, 0.92, 0.35 } },
    { ImGuiCol_CheckMark,         { 1.00, 0.84, 0.45, 1.00 } },
    { ImGuiCol_TableHeaderBg,     { 0.14, 0.14, 0.36, 0.80 } },
    { ImGuiCol_TableBorderLight,  { 0.55, 0.60, 0.92, 0.22 } },
    { ImGuiCol_TableRowBgAlt,     { 1.00, 1.00, 1.00, 0.04 } },
    { ImGuiCol_ScrollbarBg,       { 0.00, 0.00, 0.00, 0.00 } },
    { ImGuiCol_ScrollbarGrab,     { 0.40, 0.38, 0.72, 0.70 } },
    { ImGuiCol_ResizeGrip,        { 0.55, 0.60, 0.92, 0.25 } },
};

-- Window styles. Each theme sets the window background
-- (the FFXI card or a flat fill), overrides some of the palette above, and sets the text colours used everywhere (C).
ui.THEMES = {
    { key = 'ffxi', name = 'FFXI Window', card = true,
      C = { accent = { 1.00, 0.84, 0.45, 1 }, text = { 0.92, 0.92, 0.95, 1 }, dim = { 0.92, 0.92, 0.95, 1 } } },
    { key = 'midnight', name = 'Midnight', bg = { 0.04, 0.05, 0.08 }, border = { 0.35, 0.40, 0.55, 0.50 },
      C = { accent = { 0.98, 0.78, 0.40, 1 }, text = { 0.90, 0.92, 0.96, 1 }, dim = { 0.70, 0.74, 0.82, 1 } },
      over = { [ImGuiCol_FrameBg] = { 0.10, 0.12, 0.17, 0.90 }, [ImGuiCol_Button] = { 0.15, 0.17, 0.24, 0.95 },
               [ImGuiCol_ButtonHovered] = { 0.26, 0.29, 0.40, 1 }, [ImGuiCol_Tab] = { 0.10, 0.12, 0.17, 0.95 },
               [ImGuiCol_TabSelected] = { 0.22, 0.25, 0.35, 1 }, [ImGuiCol_TabHovered] = { 0.28, 0.31, 0.43, 1 },
               [ImGuiCol_TableHeaderBg] = { 0.10, 0.12, 0.17, 0.95 }, [ImGuiCol_PopupBg] = { 0.06, 0.07, 0.11, 0.98 } } },
    { key = 'parchment', name = 'Parchment', bg = { 0.91, 0.85, 0.71 }, border = { 0.45, 0.32, 0.16, 0.70 },
      C = { accent = { 0.55, 0.16, 0.10, 1 }, text = { 0.20, 0.13, 0.06, 1 }, dim = { 0.36, 0.26, 0.14, 1 },
            good = { 0.16, 0.45, 0.18, 1 }, warn = { 0.62, 0.38, 0.02, 1 }, bad = { 0.70, 0.12, 0.10, 1 } },
      over = { [ImGuiCol_Text] = { 0.20, 0.13, 0.06, 1 }, [ImGuiCol_FrameBg] = { 0.98, 0.94, 0.84, 0.95 },
               [ImGuiCol_FrameBgHovered] = { 1.0, 0.97, 0.88, 1 }, [ImGuiCol_Button] = { 0.72, 0.58, 0.38, 0.95 },
               [ImGuiCol_ButtonHovered] = { 0.80, 0.66, 0.44, 1 }, [ImGuiCol_ButtonActive] = { 0.62, 0.48, 0.30, 1 },
               [ImGuiCol_Tab] = { 0.80, 0.70, 0.52, 0.95 }, [ImGuiCol_TabSelected] = { 0.98, 0.94, 0.84, 1 },
               [ImGuiCol_TabHovered] = { 0.90, 0.82, 0.64, 1 }, [ImGuiCol_TabSelectedOverline] = { 0.55, 0.16, 0.10, 1 },
               [ImGuiCol_Header] = { 0.80, 0.62, 0.34, 0.55 }, [ImGuiCol_HeaderHovered] = { 0.86, 0.72, 0.48, 0.60 },
               [ImGuiCol_TableHeaderBg] = { 0.80, 0.70, 0.52, 0.95 }, [ImGuiCol_CheckMark] = { 0.55, 0.16, 0.10, 1 },
               [ImGuiCol_PopupBg] = { 0.95, 0.90, 0.78, 0.99 }, [ImGuiCol_Separator] = { 0.45, 0.32, 0.16, 0.45 },
               [ImGuiCol_TableRowBgAlt] = { 0.45, 0.32, 0.16, 0.06 }, [ImGuiCol_ScrollbarGrab] = { 0.62, 0.48, 0.30, 0.80 } } },
    { key = 'crystal', name = 'Crystal', bg = { 0.02, 0.12, 0.14 }, border = { 0.35, 0.80, 0.85, 0.45 },
      C = { accent = { 0.55, 0.95, 1.00, 1 }, text = { 0.90, 0.97, 0.98, 1 }, dim = { 0.70, 0.86, 0.88, 1 } },
      over = { [ImGuiCol_FrameBg] = { 0.03, 0.20, 0.23, 0.85 }, [ImGuiCol_Button] = { 0.06, 0.32, 0.36, 0.90 },
               [ImGuiCol_ButtonHovered] = { 0.10, 0.46, 0.50, 1 }, [ImGuiCol_Tab] = { 0.04, 0.22, 0.25, 0.95 },
               [ImGuiCol_TabSelected] = { 0.08, 0.40, 0.44, 1 }, [ImGuiCol_TabHovered] = { 0.12, 0.48, 0.52, 1 },
               [ImGuiCol_TabSelectedOverline] = { 0.55, 0.95, 1.00, 1 }, [ImGuiCol_CheckMark] = { 0.55, 0.95, 1.00, 1 },
               [ImGuiCol_Header] = { 0.10, 0.45, 0.50, 0.50 }, [ImGuiCol_TableHeaderBg] = { 0.04, 0.22, 0.25, 0.95 },
               [ImGuiCol_PopupBg] = { 0.02, 0.14, 0.16, 0.98 } } },
};
ui.BASE_C = { good = { 0.46, 0.84, 0.56, 1.0 }, warn = { 0.95, 0.80, 0.35, 1.0 }, bad = { 0.95, 0.45, 0.42, 1.0 } };
function ui.theme()
    for _, t in ipairs(ui.THEMES) do if (t.key == db.cfg.theme) then return t; end end
    return ui.THEMES[1];
end
function ui.apply_theme_colors()
    local t = ui.theme();
    for _, k in ipairs({ 'accent', 'text', 'dim', 'good', 'warn', 'bad' }) do
        local v = (t.C and t.C[k]) or ui.BASE_C[k];
        if (v ~= nil) then C[k] = v; end
    end
end

local function push_style()
    local s = ui.S;
    ui.apply_theme_colors();
    imgui.PushStyleVar(ImGuiStyleVar_WindowRounding, 0);
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_FrameRounding, 2);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { math.floor(10 * s), math.floor(8 * s) });
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, { math.floor(5 * s), math.floor(3 * s) });
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { math.floor(6 * s), math.floor(4 * s) });
    local over = ui.theme().over or {};
    for _, c in ipairs(STYLE_COLORS) do imgui.PushStyleColor(c[1], over[c[1]] or c[2]); end
end
local function pop_style() imgui.PopStyleColor(#STYLE_COLORS); imgui.PopStyleVar(6); end

local okFfi, ffi = pcall(require, 'ffi');
local okD3d, d3d = pcall(require, 'd3d8');

-- Textures load once with an explicit alpha format (A8R8G8B8). The moogle is 128x128 (a power of two) so the driver
-- never pads it; the old 96 px ImageButton drew its frame as a dark square around the art.
local function load_texture(file)
    if (not okFfi) or (not okD3d) then return nil, nil; end
    local tex, id = nil, nil;
    pcall(function ()
        local path = (addon.path or ''):gsub('[\\/]+$', '') .. '\\assets\\' .. file;
        local ptr = ffi.new('IDirect3DTexture8*[1]');
        local C = ffi.C;
        if (C.D3DXCreateTextureFromFileExA(d3d.get_device(), path, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 1, 0, C.D3DFMT_A8R8G8B8,
                C.D3DPOOL_MANAGED, C.D3DX_DEFAULT, C.D3DX_DEFAULT, 0, nil, nil, ptr) == C.S_OK) then
            tex = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', ptr[0]));
            id = tonumber(ffi.cast('uint32_t', tex));
        end
    end);
    return tex, id;
end

local function load_icon()
    ui.moogleTex, ui.moogleId = load_texture('moogle_128.png');
    -- the clock moogle (Heaph's artwork, blank screen at 69-83% height).
    ui.timerTex, ui.timerId = load_texture('moogle_timer_256.png');
    local okD, fd = pcall(imgui.AddFontFromFileTTF, 'C:/Windows/Fonts/consolab.ttf', 32.0);
    if okD and fd then ui.digitFont = fd; end
    ui.cardTex, ui.cardId = load_texture('card.png');   -- our own navy card (no game texture ships with the addon)
    -- Verdana Bold like the game chat (same as the luashitacast HUD); loaded at addon load, never mid-frame.
    for _, f in ipairs({ 'verdanab.ttf', 'tahomabd.ttf', 'arialbd.ttf' }) do
        local ok, r = pcall(imgui.AddFontFromFileTTF, 'C:/Windows/Fonts/' .. f, 20.0);
        if ok and r then ui.font = r; break; end
    end
end

-- The FFXI window card behind the current window (from shared_meters.lua Card()).
local function card()
    local dl = imgui.GetWindowDrawList();
    local x, y = imgui.GetWindowPos();
    local w, h = imgui.GetWindowSize();
    x, y = math.floor(x), math.floor(y);
    local span, step = 2048, 8;
    for yy = 0, h - 1, step do
        local y1 = math.min(h, yy + step);
        local a = 0.55 + 0.43 * (math.max(0, math.min(1, ((yy + y1) / 2 / math.max(1, h)) / 0.65)) ^ 0.8);
        local th = ui.theme();
        a = a * (db.cfg.opacity or 100) / 100;
        if (not th.card) then
            local bg = th.bg;
            dl:AddRectFilled({ x, y + yy }, { x + w, y + y1 }, imgui.GetColorU32({ bg[1], bg[2], bg[3], 0.94 * (db.cfg.opacity or 100) / 100 }), 0);
        elseif (ui.cardId ~= nil) then
            dl:AddImage(ui.cardId, { x, y + yy }, { x + w, y + y1 }, { 0, yy / span }, { w / span, y1 / span }, imgui.GetColorU32({ 1, 1, 1, a }));
        else
            dl:AddRectFilled({ x, y + yy }, { x + w, y + y1 }, imgui.GetColorU32({ 40 / 255, 36 / 255, 82 / 255, a }), 0);
        end
    end
    dl:AddRect({ x, y }, { x + w, y + h }, imgui.GetColorU32(ui.theme().border or { 0.62, 0.60, 0.80, 0.40 }), 0, 0, 1);
end

-- A big on/off switch: a pill with a sliding knob and the state written next to it. Returns the new value.
function ui.toggle(id, on, onText, offText)
    local h = ui.px(22);
    local w = h * 2;
    local x, y = imgui.GetCursorScreenPos();
    local clicked = imgui.InvisibleButton(id, { w, h });
    local hov = imgui.IsItemHovered();
    local dl = imgui.GetWindowDrawList();
    local track = on and { 0.30, 0.72, 0.42, 1 } or { 0.45, 0.20, 0.20, 1 };
    if hov then track = { track[1] + 0.08, track[2] + 0.08, track[3] + 0.08, 1 }; end
    dl:AddRectFilled({ x, y }, { x + w, y + h }, imgui.GetColorU32(track), h / 2);
    local kx = on and (x + w - h / 2) or (x + h / 2);
    dl:AddCircleFilled({ kx, y + h / 2 }, h / 2 - 2, imgui.GetColorU32({ 0.97, 0.97, 0.97, 1 }), 24);
    imgui.SameLine();
    imgui.TextColored(on and C.good or C.bad, on and onText or offText);
    if clicked then return not on; end
    return on;
end

-- SHARE TOD / DO NOT SHARE for the open book.
function ui.share_switch()
    if (bookKey == 'local') then return; end
    local on = (db.cfg.shareTod ~= false);
    local nv = ui.toggle('##sharetod', on, 'SHARE TOD', 'DO NOT SHARE');
    if (nv ~= on) then db.cfg.shareTod = nv; touch(); end
    imgui.SameLine();
    label(nv and ('ToDs you see go to everyone in %s.'):format(book().ls) or 'ToDs you see stay on this PC.');
end

local function push_font()
    local base = imgui.GetFontSize();
    if ui.font then imgui.PushFont(ui.font, base * 1.5); else imgui.PushFont(imgui.GetFont(), base * 1.6); end
end

-- Bold title with the game's dark outline.
local function title_text(col, text)
    local x, y = imgui.GetCursorScreenPos();
    x, y = math.floor(x + 0.5), math.floor(y + 0.5);
    for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        imgui.SetCursorScreenPos({ x + d[1], y + d[2] });
        imgui.TextColored({ 0.02, 0.02, 0.06, 0.9 }, text);
    end
    imgui.SetCursorScreenPos({ x, y });
    imgui.TextColored(col, text);
end

-- The next known window: one that is open now wins, else the soonest to open. Returns key, seconds, isOpen, openAt.
function ui.next_window()
    local now = os.time();
    local best, bestT, bestOpen, bestAt = nil, nil, false, nil;
    for _, m in ipairs(mobs) do
        local t, e = db.tods[m.key], m.e;
        if (t ~= nil) and (e.minS ~= nil) and (not e.forced) then
            local open, close = t.t + e.minS, t.t + (e.maxS or e.minS);
            if (now >= open) and (now <= close) then
                if (not bestOpen) or (close - now < bestT) then best, bestT, bestOpen, bestAt = m.key, close - now, true, open; end
            elseif (now < open) and (not bestOpen) and ((bestT == nil) or (open - now < bestT)) then
                best, bestT, bestAt = m.key, open - now, open;
            end
        end
    end
    return best, bestT, bestOpen, bestAt;
end

-- 21h05 over an hour, 05:00 under it, OPEN in the window, --:-- with no ToD.
function ui.clock_text(secs, isOpen)
    if isOpen then return 'OPEN'; end
    if (secs == nil) then return '--:--'; end
    secs = math.max(0, math.floor(secs));
    if (secs >= 3600) then
        local h = math.floor(secs / 3600);
        return (h >= 100) and ('%dh'):format(h) or ('%dh%02d'):format(h, math.floor(secs % 3600 / 60));
    end
    return ('%02d:%02d'):format(math.floor(secs / 60), secs % 60);
end

local function draw_pill()
    if (not db.cfg.showPill) then return; end
    local clockStyle = (db.cfg.iconStyle == 'clock') and (ui.timerId ~= nil);
    local icon = ui.px(clockStyle and (db.cfg.iconSize or 70) or 46);
    imgui.SetNextWindowPos({ 20, 220 }, ImGuiCond_FirstUseEver);
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar,
        ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoBackground);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 });
    local wx, wy = 0, 0;
    if imgui.Begin('##heaphkp_moogle', true, flags) then
        wx, wy = imgui.GetWindowPos();
        local key, secs, isOpen, openAt = nil, nil, false, nil;
        if clockStyle then
            key, secs, isOpen, openAt = ui.next_window();
            -- gentle bob: the art moves inside a window that does not, so dragging stays steady
            local bob = db.cfg.iconBob and math.floor(math.sin(os.clock() * math.pi * 2 / 2.8) * math.max(1, icon / 60) + 0.5) or 0;
            local cx, cy = imgui.GetCursorScreenPos();
            imgui.Dummy({ icon, icon + 2 });
            local dl = imgui.GetWindowDrawList();
            dl:AddImage(ui.timerId, { cx, cy + 1 + bob }, { cx + icon, cy + 1 + icon + bob }, { 0, 0 }, { 1, 1 }, imgui.GetColorU32({ 1, 1, 1, 1 }));
            -- digits on the clock screen (screen box 0.16-0.84 wide, 0.69-0.83 high on the art)
            local text = ui.clock_text(secs, isOpen);
            local fsize = math.floor(icon * 0.13 + 0.5);
            imgui.PushFont(ui.digitFont or ui.font or imgui.GetFont(), fsize);
            local tw, th = imgui.CalcTextSize(text);
            local maxW = icon * 0.62;
            if (tw > maxW) then
                imgui.PopFont();
                fsize = math.floor(fsize * maxW / tw);
                imgui.PushFont(ui.digitFont or ui.font or imgui.GetFont(), fsize);
                tw, th = imgui.CalcTextSize(text);
            end
            local tx = math.floor(cx + icon * 0.50 - tw / 2 + 0.5);
            local ty = math.floor(cy + 1 + bob + icon * 0.76 - th / 2 + 0.5);
            local col = isOpen and { 0.55, 1.0, 0.62, 1 } or ((secs ~= nil and secs <= (db.cfg.notifyLead or 30) * 60) and { 1.0, 0.84, 0.45, 1 } or { 0.75, 1.0, 1.0, 1 });
            for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
                dl:AddText({ tx + d[1], ty + d[2] }, imgui.GetColorU32({ 0.03, 0.10, 0.11, 1 }), text);
            end
            dl:AddText({ tx, ty }, imgui.GetColorU32(col), text);
            imgui.PopFont();
            imgui.SetCursorScreenPos({ cx, cy });
            imgui.InvisibleButton('##moogle_hit', { icon, icon + 2 });
        elseif (ui.moogleId ~= nil) then
            imgui.Image(ui.moogleId, { icon, icon });
        else
            imgui.Dummy({ icon, icon });
            imgui.GetWindowDrawList():AddCircleFilled({ wx + icon / 2, wy + icon / 2 }, icon / 2, imgui.GetColorU32({ 0.32, 0.29, 0.62, 0.95 }), 32);
        end
        -- click toggles, drag moves (the moogle is the handle)
        local hovered = imgui.IsItemHovered();
        if imgui.IsMouseDragging(0, 4) then ui.dragging = true; end
        if clockStyle and imgui.IsItemActive() and imgui.IsMouseDragging(0, 4) then
            local dx, dy = imgui.GetMouseDragDelta(0);
            imgui.SetWindowPos({ wx + dx, wy + dy });
            imgui.ResetMouseDragDelta(0);
        end
        if hovered and imgui.IsMouseReleased(0) and not ui.dragging then
            ui.open[1] = not ui.open[1];
            ui_badge = false;
            if ui.open[1] then alerts = {}; end
        end
        if imgui.IsMouseReleased(0) then ui.dragging = false; end
        local dl = imgui.GetWindowDrawList();
        if hovered and (not clockStyle) then dl:AddCircle({ wx + icon / 2, wy + icon / 2 }, icon / 2 - 1, imgui.GetColorU32({ 1.0, 0.84, 0.45, 0.9 }), 48, 2); end
        -- no ImGui tooltip over the clock. Hovering adds one outlined line
        -- under the name instead, in the same font, no box.
        local hoverLine = nil;
        if hovered then
            if (not clockStyle) then hoverLine = ui.open[1] and 'click to close' or 'click to open';
            elseif (key == nil) then hoverLine = 'no known windows yet';
            elseif isOpen then hoverLine = ('open since %s %s'):format(clock(openAt), zone());
            else hoverLine = ('opens %s %s'):format(clock(openAt), zone()); end
        end
        if ui_badge or (#alerts > 0) then
            local r = math.max(5, icon / 7);
            dl:AddCircleFilled({ wx + icon - r, wy + r }, r, imgui.GetColorU32({ 0.89, 0.28, 0.25, 1.0 }), 20);
            dl:AddCircle({ wx + icon - r, wy + r }, r, imgui.GetColorU32({ 1, 1, 1, 1 }), 20, 1.5);
        end
        local now = os.time();
        local txt = (clockStyle and key) or nil;
        if (db.auction ~= nil) then txt = ('bid %s'):format(dur(db.auction.ends - now));
        elseif (db.rc ~= nil) then txt = ('check %s'):format(dur(db.rc.closes - now));
        elseif (db.event ~= nil) then txt = db.event.name; end
        -- the name is centred under the moogle. It is drawn on the foreground list so a
        -- long name can spill past the moogle on both sides without the window growing and the moogle jumping.
        local _, ly = imgui.GetCursorScreenPos();
        ly = math.floor(ly + 0.5);
        local fg = imgui.GetForegroundDrawList();
        local dark = imgui.GetColorU32({ 0.02, 0.02, 0.06, 0.9 });
        for _, line in ipairs({ { txt, C.accent, 1.0 }, { hoverLine, C.text, 0.8 } }) do
            if (line[1] ~= nil) then
                push_font();
                local fnt, fsz = imgui.GetFont(), imgui.GetFontSize() * line[3];
                imgui.PopFont();
                imgui.PushFont(fnt, fsz);
                local lw, lh = imgui.CalcTextSize(line[1]);
                imgui.PopFont();
                local lx = math.floor(wx + icon / 2 - lw / 2 + 0.5);
                for _, d in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
                    fg:AddText(fnt, fsz, { lx + d[1], ly + d[2] }, dark, line[1]);
                end
                fg:AddText(fnt, fsz, { lx, ly }, imgui.GetColorU32(line[2]), line[1]);
                if (line[3] == 1.0) then imgui.Dummy({ icon, lh }); end   -- the name keeps its row; the hover line floats
                ly = ly + math.floor(lh + 0.5);
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(1);
    -- the alert note sits beside the moogle until you open HeaphKP or dismiss it
    if (#alerts > 0) and (not ui.open[1]) then
        imgui.SetNextWindowPos({ wx + icon + ui.px(8), wy }, ImGuiCond_Always);
        if imgui.Begin('##heaphkp_alert', true, bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_AlwaysAutoResize,
                ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoSavedSettings)) then
            card();
            push_font();
            for i = math.max(1, #alerts - 2), #alerts do
                imgui.TextColored(C.accent, clock(alerts[i].t):match('%d+:%d+ %a+') or '');
                imgui.SameLine();
                imgui.TextColored(C.text, alerts[i].text);
            end
            if imgui.SmallButton('Got it') then alerts = {}; ui_badge = false; end
            imgui.PopFont();
        end
        imgui.End();
    end
end

local function draw()
    if (os.clock() < hideUntil) then return; end
    if (TABLE_FLAGS == nil) then
        TABLE_FLAGS = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_ScrollY, ImGuiTableFlags_SizingStretchProp);
    end
    ui.S = (imgui.GetFontSize() * (ui.font and 1.5 or 1.6)) / 13;   -- size factor: 1.0 = the stock 13 px font
    push_style();
    draw_pill();
    if ui.open[1] then
        imgui.SetNextWindowSize({ ui.px(720), ui.px(540) }, ImGuiCond_FirstUseEver);
        imgui.SetNextWindowSizeConstraints({ ui.px(520), ui.px(360) }, { 8000, 8000 });
        if imgui.Begin('##heaphkp_main', ui.open, bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse)) then
            card();
            push_font();
            title_text(C.accent, 'HeaphKP');
            imgui.SameLine(imgui.GetWindowWidth() - ui.px(34));
            if imgui.SmallButton(' x ') then ui.open[1] = false; end
            if imgui.IsItemHovered() then imgui.SetTooltip('Close (the moogle opens it again)'); end
            header();
            if imgui.BeginTabBar('##tabs') then
                for _, t in ipairs(TABS) do
                    local flags = (ui.goTab == t[1]) and ImGuiTabItemFlags_SetSelected or 0;
                    if imgui.BeginTabItem(t[1], nil, flags) then
                        local lock = read_only() and (t[1] == 'Auction' or t[1] == 'Attendance' or t[1] == 'Settings' or t[1] == 'Members');
                        if lock then imgui.BeginDisabled(true); end
                        t[2]();
                        if lock then imgui.EndDisabled(); end
                        imgui.EndTabItem();
                    end
                end
                ui.goTab = nil;
                imgui.EndTabBar();
            end
            imgui.PopFont();
        end
        imgui.End();
    end
    pop_style();
end

---------------------------------------------------------------------------------------------------------------------
-- Clock: ready checks, auction timer, screenshots, chat queue, saving
---------------------------------------------------------------------------------------------------------------------
local autoCheck = 0;
local function tick()
    local now = os.time();
    if (now >= autoCheck) then
        autoCheck = now + 5;
        for key, a in pairs(db.autoCamp) do
            local at = auto_start_time(key);
            local tod = db.tods[key];
            local mine = (not synced()) or (a.by == nil) or (a.by == me());
            if mine and (not read_only()) and (at ~= nil) and (now >= at) and (a.startedFor ~= tod.t) then
                if (db.event == nil) then
                    a.startedFor = tod.t;
                    start_event(key .. ' camp', 'auto', key);
                elseif (a.warned ~= tod.t) and (db.event.mob ~= key) then
                    a.warned = tod.t;
                    print(TAG .. ('%s auto camp is due, but %s is still running.'):format(key, db.event.name));
                end
            end
        end
    end
    if read_only() and ((db.event ~= nil) or (db.rc ~= nil) or (db.auction ~= nil)) then
        db.event, db.rc, db.auction = nil, nil, nil;
        touch();
        print(TAG .. 'You are view-only in this book now, so the running event or auction was stopped on this PC.');
    end
    local ev = db.event;
    if (ev ~= nil) and (ev.killedAt ~= nil) and (now >= ev.killedAt + db.cfg.endAfterKill * 60) then
        stop_event('auto');
        ev = nil;
    end
    if (ev ~= nil) and (db.rc == nil) and (now >= ev.nextRc) then
        ev.nextRc = now + db.cfg.tickMin * 60;
        open_rc('auto');
    end
    if (db.rc ~= nil) and (now >= db.rc.closes) then close_rc(); end
    local a = db.auction;
    if (a ~= nil) then
        if (not a.warned) and (a.ends - now <= 10) and (a.ends - now > 0) and (not a.sealed) then
            a.warned = true;
            local best = high_bid();
            post(('%s: 10s left, %s.'):format(a.item, best and ('high %d by %s'):format(best.amt, best.name) or 'no bids'));
        end
        if (announceHigh > 0) and (os.clock() >= announceHigh) and (not a.sealed) then
            announceHigh = 0;
            local best = high_bid();
            if (best ~= nil) then post(('%s: high bid %d by %s.'):format(a.item, best.amt, best.name)); end
        end
        if (now >= a.ends) then close_auction(nil); end
    end
    shot_tick();
    pump();
    if (not HK.backfilled) and (me() ~= nil) then HK.backfilled = true; pcall(HK.backfill, false); end
    pcall(sync_tick);
    if (os.clock() - (HK.stateAt or -99) >= 5) then HK.stateAt = os.clock(); pcall(HK.write_state); end
    live_tick();
    notify_tick();
    if dirty and (os.clock() - lastSave > 2) then save_db(); end
end

---------------------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------------------
ashita.events.register('load', 'heaphkp_load', function ()
    ashita.fs.create_directory(ROOT);
    ashita.fs.create_directory(DROPDIR);
    local old = INSTALL .. '\\config\\addons\\lsdkp\\db.json';   -- this addon's first name
    if (not ashita.fs.exists(DBFILE)) and ashita.fs.exists(old) then os.rename(old, DBFILE); end
    load_access();
    if (net ~= nil) then
        net.blocking = access.blocking and true or false;
        net.verify = not access.tlsSkip;
        net.cafile = (addon.path or ''):gsub('[\\/]+$', '') .. '\\assets\\cacert.pem';
    end
    bookKey = (access.active == 'local' or access.books[access.active] ~= nil) and access.active or 'local';
    load_db();
    index_history();
    build_mobs();
    pcall(load_icon);
    print(TAG .. ('%s loaded: %d members, %d timed mobs. Click the moogle (or /hkp) to open it.'):format(
        book() and book().ls or 'This PC only',
        (function () local c = 0; for _ in pairs(db.members) do c = c + 1; end; return c; end)(), #mobs));
end);

ashita.events.register('unload', 'heaphkp_unload', function ()
    if dirty then save_db(); end
end);

ashita.events.register('d3d_present', 'heaphkp_present', function ()
    tick();
    draw();
end);

ashita.events.register('packet_out', 'heaphkp_packet_out', function (e)
    if (e.id ~= 0x0B5) then return; end
    local kind = struct.unpack('B', e.data, 0x04 + 1);
    if (kind ~= 0x04) and (kind ~= 0x05) and (kind ~= 0x1B) then return; end   -- party, LS, LS2
    local msg = clean(e.data:sub(0x06 + 1):match('^[^%z]*'));
    local cmd, rest = msg:match('^!(%a+)%s*(.-)%s*$');
    if (cmd ~= nil) and (KNOWN[cmd:lower()] ~= nil) and (cmd:lower() ~= 'bid') then
        pcall(run, cmd:lower(), rest, nil);
    end
end);

ashita.events.register('packet_in', 'heaphkp_packet', function (e)
    if (e.id == 0x017) then
        local kind = struct.unpack('B', e.data, 0x04 + 1);
        if (kind == CHAT_TELL) or (kind == CHAT_PARTY) or (kind == CHAT_LS) or (kind == CHAT_LS2) then
            local from = e.data:sub(0x08 + 1, 0x08 + 15):match('^[^%z]*');
            local msg = e.data:sub(0x17 + 1):match('^[^%z]*');
            pcall(on_chat, kind, from, msg);
        end
    elseif (e.id == 0x029) then
        -- battle message: 6 = "<player> defeats <target>.", 20 = "<target> falls to the ground." (Phoenix MsgStd).
        -- A chat line can never produce this packet, so a typed "defeats King Arthro." changes nothing.
        local msg = struct.unpack('H', e.data, 0x18 + 1);
        if (msg == 6) or (msg == 20) then
            local idx = struct.unpack('H', e.data, 0x16 + 1);
            local ent = AshitaCore:GetMemoryManager():GetEntity();
            local name = (idx ~= nil and idx > 0) and ent:GetName(idx) or nil;
            local flags = 0;
            pcall(function () flags = ent:GetSpawnFlags(idx) or 0; end);
            local isMob = (flags == 0) or (math.floor(flags / 16) % 2 == 1);   -- 0x10 = monster
            if (name ~= nil) and (name ~= '') and isMob and (mobIndex[name:lower()] ~= nil) then pcall(on_kill, name); end
        end
    elseif (e.id == 0x0D2) then
        local itemId = struct.unpack('H', e.data, 0x10 + 1);
        local actIdx = struct.unpack('H', e.data, 0x12 + 1);
        local slot   = struct.unpack('B', e.data, 0x14 + 1);
        local old    = struct.unpack('B', e.data, 0x15 + 1);
        if (old == 0) and (itemId > 0) and (itemId ~= 0xFFFF) then pcall(on_drop, itemId, slot, actIdx); end
    elseif (e.id == 0x0D3) then
        local slot  = struct.unpack('B', e.data, 0x14 + 1);
        local judge = struct.unpack('B', e.data, 0x15 + 1);
        if (judge == 1) then
            local name = e.data:sub(0x16 + 1, 0x16 + 16):match('^[^%z]*');
            if (name ~= nil) and (name ~= '') then pcall(on_lot_result, slot, name); end
        elseif (judge == 2) then
            poolSlot[slot] = nil;   -- the item was lost (nobody could take it)
        end
    end
end);


ashita.events.register('command', 'heaphkp_command', function (e)
    local args = e.command:args();
    if (#args == 0) or ((args[1]:lower() ~= '/hkp') and (args[1]:lower() ~= '/dkp')) then return; end
    e.blocked = true;
    if (#args == 1) then ui.open[1] = not ui.open[1]; return; end
    local cmd = args[2]:lower();
    local rest = e.command:match('^%S+%s+%S+%s*(.*)$') or '';
    if (cmd == 'show') then ui.open[1] = true; return; end
    if (cmd == 'help') then
        print(TAG .. 'start <event> | stop | rc | auction <item> [min] | close | cancel | award <name> <price> <item>');
        print(TAG .. 'add <name> <+/-n> [why] | tod <mob> [now|21:43|-15m] | role <name> <role> | price <item> <min>');
        print(TAG .. 'track <mob> <minH> <maxH> | undo | export');
        return;
    end
    if (KNOWN[cmd] == nil) then print(TAG .. 'Unknown command. /dkp help'); return; end
    run(cmd, rest, nil);
end);
