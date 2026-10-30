// LS DKP sync server. The lsdkp Ashita addon talks to this over HTTPS (POST + JSON).
//
//   POST /register {ls, name}                 the LS owner turns DKP on (the addon only offers this to whoever has
//                                             that LS's Linkshell item equipped). First come; returns a token.
//   POST /invite   {token, name, role}        admin/owner: give `name` a role and a one-use code to join with (1 hour)
//   POST /join     {ls, name, code}           use that code; returns a token
//   POST /sync     {token, since, ops:[...]}  push your new ops, get everyone's ops after `since`
//
// Identity: a token is issued only at /register (to the name that registered) or at /join with a one-use code that was
// made out to that exact name and delivered to it by in-game tell. Every change is stored with the token's name as its
// author, and any author field inside the change is overwritten with it, so nothing can be written as someone else.
//
// Roles: owner > admin > officer > viewer. Viewers only read. Officers write the book (ticks, bids, awards, ToDs,
// drops, prices). Admins also change roles and remove members. Only the owner makes or removes admins.
// Viewers may still send ToDs, so every member's client keeps the LS's timers current.

import HNM from './hnm.json';

const LEVEL = { none: 0, viewer: 1, officer: 2, admin: 3, owner: 4 };
const KEY_RATE_PER_MIN = 120;  // API calls per key per minute
const KEY_PREFIX = 'hkp_';
const ROLE_SET = new Set(['none', 'viewer', 'officer', 'admin']);   // what a role op may set (never 'owner', never a prototype key)
const MAX_LS_OPS = 50000;      // a linkshell's log; past this, pushes are refused until the owner starts a new book
const MAX_LS = 500;            // linkshells on this server
const REG_PER_IP_DAY = 3;      // registrations per address per day
const ADMIN_KINDS = new Set(['role', 'member_rm', 'settings']);
// Heaph 10-30: everyone in the book shares the ToDs they see, so viewers may send 'tod'.
const VIEWER_KINDS = new Set(['tod']);
const INVITE_SECONDS = 3600;   // Heaph 10-30: join codes last one hour
const KINDS = new Set(['rec', 'undo', 'member', 'member_rm', 'role', 'price', 'price_rm', 'tod', 'tod_clear',
    'custom', 'custom_rm', 'auto', 'drop', 'drop_upd', 'drop_rm', 'live', 'settings']);
const MAX_OPS = 200;
const MAX_BODY = 4000;
const PULL = 500;

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
    status, headers: { 'content-type': 'application/json' },
});
const fail = (msg, status = 400) => json({ error: msg }, status);

const now = () => Math.floor(Date.now() / 1000);

// Same rule as the addon's N(): letters only, First-cap.
function charName(s) {
    s = String(s || '').replace(/[^A-Za-z]/g, '');
    if (s.length < 3 || s.length > 15) return null;
    return s[0].toUpperCase() + s.slice(1).toLowerCase();
}
// An API key acts as 'bot:<label>': never a character name, so a bot can never be mistaken for a player.
function botName(label) {
    label = String(label || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 20);
    return label.length >= 2 ? 'bot:' + label : null;
}
function anyName(s) {
    const str = String(s || '');
    return str.startsWith('bot:') ? botName(str.slice(4)) : charName(str);
}
function lsName(s) {
    s = String(s || '').replace(/[^A-Za-z0-9]/g, '');
    return (s.length >= 1 && s.length <= 20) ? s : null;
}

async function sha(s) {
    const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
    return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function randomToken() {
    const b = new Uint8Array(24);
    crypto.getRandomValues(b);
    return [...b].map(x => x.toString(16).padStart(2, '0')).join('');
}
function randomCode() {
    const A = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    const b = new Uint8Array(8);
    crypto.getRandomValues(b);
    const c = [...b].map(x => A[x % A.length]).join('');
    return c.slice(0, 4) + '-' + c.slice(4);
}

async function issueToken(db, lsId, name) {
    const token = randomToken();
    await db.prepare('INSERT INTO tokens (hash, ls_id, name, created, last_seen) VALUES (?, ?, ?, ?, ?)')
        .bind(await sha(token), lsId, name, now(), now()).run();
    return token;
}

// token -> { lsId, name, role, ls }
async function auth(db, token) {
    if (!token) return null;
    const row = await db.prepare(`SELECT t.ls_id, t.name, l.display, l.owner, COALESCE(r.role, 'none') AS role
        FROM tokens t JOIN ls l ON l.id = t.ls_id LEFT JOIN roles r ON r.ls_id = t.ls_id AND r.name = t.name
        WHERE t.hash = ?`).bind(await sha(token)).first();
    if (!row || !Object.hasOwn(LEVEL, row.role) || LEVEL[row.role] === 0) return null;
    return { lsId: row.ls_id, name: row.name, role: row.role, ls: row.display, owner: row.owner };
}

// The registry: every name with a role, when it first joined (a token was issued to it) and when it last synced.
// A name with no token has been invited but has not joined, so nothing can have been written as it.
async function roleList(db, lsId) {
    const r = await db.prepare(`SELECT r.name, r.role, MAX(t.last_seen) AS last_seen, MIN(t.created) AS joined
        FROM roles r LEFT JOIN tokens t ON t.ls_id = r.ls_id AND t.name = r.name
        WHERE r.ls_id = ? GROUP BY r.name, r.role ORDER BY r.name`).bind(lsId).all();
    return r.results;
}

// Identity: whatever a client claims inside a change, the author is the character the token was issued to.
function stampAuthor(body, name) {
    if (!body || typeof body !== 'object') return body;
    if ('by' in body) body.by = name;
    if ('seenBy' in body) body.seenBy = name;
    if (body.v && typeof body.v === 'object' && 'by' in body.v) body.v.by = name;
    return body;
}

async function register(db, b, req) {
    const ls = lsName(b.ls), name = charName(b.name);
    if (!ls || !name) return fail('Need a linkshell name and a character name.');
    const key = ls.toLowerCase();
    const ip = req.headers.get('CF-Connecting-IP') || 'local', day = Math.floor(now() / 86400);
    const reg = await db.prepare('SELECT n FROM regs WHERE ip = ? AND day = ?').bind(ip, day).first();
    if (ip !== 'local' && reg && reg.n >= REG_PER_IP_DAY) return fail('Too many registrations today from this address.', 429);   // 'local' = no CF header = wrangler dev
    const total = await db.prepare('SELECT COUNT(*) AS n FROM ls').first();
    if (total && total.n >= MAX_LS) return fail('This server is full.', 507);
    const have = await db.prepare('SELECT owner FROM ls WHERE key = ?').bind(key).first();
    if (have) return fail(`${ls} already has DKP, registered by ${have.owner}. Ask them for an invite.`, 409);
    const res = await db.prepare('INSERT INTO ls (key, display, owner, created) VALUES (?, ?, ?, ?)')
        .bind(key, ls, name, now()).run();
    const lsId = res.meta.last_row_id;
    await db.batch([
        db.prepare('INSERT INTO roles (ls_id, name, role) VALUES (?, ?, ?)').bind(lsId, name, 'owner'),
        db.prepare('INSERT INTO regs (ip, day, n) VALUES (?, ?, 1) ON CONFLICT(ip, day) DO UPDATE SET n = n + 1').bind(ip, day),
    ]);
    return json({ token: await issueToken(db, lsId, name), role: 'owner', ls, owner: name });
}

async function invite(db, b) {
    const me = await auth(db, b.token);
    if (!me) return fail('Your access was removed or the token is wrong.', 401);
    const name = charName(b.name), role = String(b.role || '');
    if (!name || !['viewer', 'officer', 'admin'].includes(role)) return fail('Need a name and a role (viewer, officer, admin).');
    if (LEVEL[me.role] < LEVEL.admin) return fail('Only the owner or an admin can invite.', 403);
    if (role === 'admin' && me.role !== 'owner') return fail('Only the owner can make admins.', 403);
    const cur = await db.prepare('SELECT role FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name).first();
    const selfOwner = (name === me.name && me.role === 'owner');   // a code for the owner's other PC; the role stays owner
    if (cur && cur.role === 'owner' && !selfOwner) return fail("That's the owner.");
    if (cur && cur.role === 'admin' && me.role !== 'owner') return fail('Only the owner can change an admin.', 403);
    const code = randomCode();
    const stmts = [];
    if (!selfOwner) stmts.push(db.prepare('INSERT OR REPLACE INTO roles (ls_id, name, role) VALUES (?, ?, ?)').bind(me.lsId, name, role));
    stmts.push(db.prepare('INSERT INTO invites (hash, ls_id, name, created, expires) VALUES (?, ?, ?, ?, ?)')
        .bind(await sha(code), me.lsId, name, now(), now() + INVITE_SECONDS));
    await db.batch(stmts);
    return json({ code, name, role: selfOwner ? 'owner' : role, ls: me.ls });
}

async function join(db, b) {
    const ls = lsName(b.ls), name = charName(b.name), code = String(b.code || '').toUpperCase().trim();
    if (!ls || !name || !code) return fail('Need the linkshell, your name and the code.');
    const l = await db.prepare('SELECT id, display FROM ls WHERE key = ?').bind(ls.toLowerCase()).first();
    if (!l) return fail(`${ls} has no DKP set up.`, 404);
    const inv = await db.prepare('SELECT hash FROM invites WHERE hash = ? AND ls_id = ? AND name = ? AND used = 0 AND expires > ?')
        .bind(await sha(code), l.id, name, now()).first();
    if (!inv) return fail('That code is wrong, used, expired, or for someone else.', 403);
    const r = await db.prepare('SELECT role FROM roles WHERE ls_id = ? AND name = ?').bind(l.id, name).first();
    if (!r) return fail('Your invite was withdrawn.', 403);
    await db.prepare('UPDATE invites SET used = 1 WHERE hash = ?').bind(inv.hash).run();
    return json({ token: await issueToken(db, l.id, name), role: r.role, ls: l.display });
}

// A role op: { n, r }. Returns an error string, or null when allowed (and applied to the roles table).
async function applyRole(db, me, body) {
    const name = anyName(body.n), r = String(body.r || '');
    if (!name || !ROLE_SET.has(r)) return 'bad role change';
    const cur = await db.prepare('SELECT role FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name).first();
    if (cur && cur.role === 'owner') return "can't change the owner";
    if ((r === 'admin' || (cur && cur.role === 'admin')) && me.role !== 'owner') return 'only the owner changes admins';
    if (r === 'none') {
        await db.batch([
            db.prepare('DELETE FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
            db.prepare('DELETE FROM tokens WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
            db.prepare('DELETE FROM apikeys WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
        ]);
    } else {
        await db.prepare('INSERT OR REPLACE INTO roles (ls_id, name, role) VALUES (?, ?, ?)').bind(me.lsId, name, r).run();
    }
    return null;
}

async function sync(db, b) {
    const me = await auth(db, b.token);
    if (!me) return fail('Your access was removed or the token is wrong.', 401);
    const ops = Array.isArray(b.ops) ? b.ops.slice(0, MAX_OPS) : [];
    const rejected = [];
    const inserts = [];
    const cnt = ops.length ? await db.prepare('SELECT COUNT(*) AS n FROM ops WHERE ls_id = ?').bind(me.lsId).first() : { n: 0 };
    const full = cnt.n + ops.length > MAX_LS_OPS;
    for (const op of ops) {
        const cid = String(op.cid || '').slice(0, 64), kind = String(op.kind || '');
        const stamped = stampAuthor((op.body && typeof op.body === 'object') ? op.body : {}, me.name);
        const body = JSON.stringify(stamped);
        let why = null;
        if (cid && await db.prepare('SELECT 1 FROM ops WHERE ls_id = ? AND cid = ?').bind(me.lsId, cid).first()) continue;   // already stored: a resend
        if (!cid || !KINDS.has(kind)) why = 'unknown change';
        else if (full) why = 'this book is full; the owner should start a new one';
        else if (body.length > MAX_BODY) why = 'too big';
        else if (LEVEL[me.role] < LEVEL.officer && !VIEWER_KINDS.has(kind)) why = 'viewers cannot change the book';
        else if (ADMIN_KINDS.has(kind) && LEVEL[me.role] < LEVEL.admin) why = 'needs admin';
        else if (kind === 'role') why = await applyRole(db, me, stamped);
        if (why) { rejected.push({ cid, why }); continue; }
        inserts.push(db.prepare('INSERT OR IGNORE INTO ops (ls_id, cid, author, kind, body, t) VALUES (?, ?, ?, ?, ?, ?)')
            .bind(me.lsId, cid, me.name, kind, body, now()));
    }
    if (inserts.length) await db.batch(inserts);
    const since = Math.max(0, Number(b.since) || 0);
    const rows = await db.prepare('SELECT seq, cid, author, kind, body, t FROM ops WHERE ls_id = ? AND seq > ? ORDER BY seq LIMIT ?')
        .bind(me.lsId, since, PULL).all();
    const out = rows.results.map(r => ({ seq: r.seq, cid: r.cid, author: r.author, kind: r.kind, body: JSON.parse(r.body), t: r.t }));
    await db.prepare('UPDATE tokens SET last_seen = ? WHERE hash = ?').bind(now(), await sha(b.token)).run();
    // the role may have changed during this call (a role op on yourself)
    const after = await auth(db, b.token);
    const keys = (after && LEVEL[after.role] >= LEVEL.admin) ? await keyList(db, me.lsId) : undefined;
    return json({
        ops: out, more: out.length === PULL, role: after ? after.role : 'none', ls: me.ls, owner: me.owner,
        roles: await roleList(db, me.lsId), keys, rejected, time: now(),
    });
}

// ---------------------------------------------------------------- API keys
async function keyList(db, lsId) {
    const r = await db.prepare('SELECT name, label, role, created, last_seen, by FROM apikeys WHERE ls_id = ? ORDER BY label').bind(lsId).all();
    return r.results;
}

// POST /keys {token, label, role}  (admin/owner): a new key, shown once.
async function makeKey(db, b) {
    const me = await auth(db, b.token);
    if (!me) return fail('Your access was removed or the token is wrong.', 401);
    if (LEVEL[me.role] < LEVEL.admin) return fail('Only the owner or an admin makes API keys.', 403);
    const name = botName(b.label), role = String(b.role || '');
    if (!name || !['viewer', 'officer'].includes(role)) return fail('Need a label (letters, digits, - or _) and a role: viewer or officer.');
    const have = await db.prepare('SELECT 1 FROM apikeys WHERE ls_id = ? AND name = ?').bind(me.lsId, name).first();
    if (have) return fail('A key with that label exists; revoke it first.', 409);
    const key = KEY_PREFIX + randomToken();
    await db.batch([
        db.prepare('INSERT OR REPLACE INTO roles (ls_id, name, role) VALUES (?, ?, ?)').bind(me.lsId, name, role),
        db.prepare('INSERT INTO apikeys (hash, ls_id, name, label, role, created, last_seen, by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)')
            .bind(await sha(key), me.lsId, name, name.slice(4), role, now(), 0, me.name),
    ]);
    return json({ key, name, role, ls: me.ls, note: 'Shown once. Send it as "Authorization: Bearer <key>".' });
}

// POST /keys/revoke {token, label}
async function revokeKey(db, b) {
    const me = await auth(db, b.token);
    if (!me) return fail('Your access was removed or the token is wrong.', 401);
    if (LEVEL[me.role] < LEVEL.admin) return fail('Only the owner or an admin revokes API keys.', 403);
    const name = botName(b.label);
    if (!name) return fail('Which key?');
    await db.batch([
        db.prepare('DELETE FROM apikeys WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
        db.prepare('DELETE FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
    ]);
    return json({ revoked: name });
}

// Bearer key -> { lsId, name:'bot:x', role, ls } with a per-minute rate limit.
async function authKey(db, req, b) {
    const h = req.headers.get('authorization') || '';
    const key = h.startsWith('Bearer ') ? h.slice(7).trim() : String((b && b.key) || '');
    if (!key.startsWith(KEY_PREFIX)) return null;
    const hash = await sha(key);
    const row = await db.prepare(`SELECT k.ls_id, k.name, l.display, COALESCE(r.role, 'none') AS role
        FROM apikeys k JOIN ls l ON l.id = k.ls_id LEFT JOIN roles r ON r.ls_id = k.ls_id AND r.name = k.name WHERE k.hash = ?`).bind(hash).first();
    if (!row || !Object.hasOwn(LEVEL, row.role) || LEVEL[row.role] === 0) return null;
    const minute = Math.floor(now() / 60);
    const hit = await db.prepare('INSERT INTO keyhits (hash, minute, n) VALUES (?, ?, 1) ON CONFLICT(hash, minute) DO UPDATE SET n = n + 1 RETURNING n').bind(hash, minute).first();
    if (hit && hit.n > KEY_RATE_PER_MIN) return { limited: true };
    await db.prepare('UPDATE apikeys SET last_seen = ? WHERE hash = ?').bind(now(), hash).run();
    return { lsId: row.ls_id, name: row.name, role: row.role, ls: row.display, hash };
}

// ---------------------------------------------------------------- the book, materialised from the log
// The same rules the addon applies (apply_rec / apply_undo / apply_op in heaphkp.lua), so a bot sees what players see.
function emptyBook() { return { seq: 0, members: {}, tods: {}, prices: {}, custom: {}, auto: {}, drops: [], history: [], live: {}, aliases: {}, ids: {} }; }

function applyOp(st, op) {
    const b = op.body || {}, k = op.kind;
    const member = n => (st.members[n] = st.members[n] || { dkp: 0, earned: 0, spent: 0, ticks: 0 });
    if (k === 'rec') {
        if (!b.id || st.ids[b.id]) return;
        st.ids[b.id] = 1;
        for (const d of (b.deltas || [])) {
            const m = member(d.n); m.dkp += d.d; if (d.d > 0) m.earned += d.d; else m.spent -= d.d;
            if (b.kind === 'tick') m.ticks += 1;
        }
        if (b.kind === 'win' && b.drop) {
            const want = st.aliases[b.drop] || b.drop;
            for (const dr of st.drops) if (dr.id === want) { dr.awarded = b.deltas[0].n; dr.price = -b.deltas[0].d; }
        }
        st.history.push({ id: b.id, t: b.t || op.t, kind: b.kind, by: op.author, text: b.text, deltas: b.deltas, names: b.names, mob: b.mob, item: b.item });
        if (st.history.length > 3000) st.history.splice(0, st.history.length - 3000);
    } else if (k === 'undo') {
        const e = st.history.find(x => x.id === b.id);
        if (!e || e.undone) return;
        for (const d of (e.deltas || [])) { const m = member(d.n); m.dkp -= d.d; if (d.d > 0) m.earned -= d.d; else m.spent += d.d; if (e.kind === 'tick') m.ticks = Math.max(0, m.ticks - 1); }
        e.undone = true;
    } else if (k === 'member') { member(b.n); }
    else if (k === 'member_rm') { delete st.members[b.n]; }
    else if (k === 'price') { st.prices[b.k] = { name: b.name, min: b.min }; }
    else if (k === 'price_rm') { delete st.prices[b.k]; }
    else if (k === 'custom') { st.custom[b.name] = { minS: b.minS, maxS: b.maxS }; }
    else if (k === 'custom_rm') { delete st.custom[b.name]; }
    else if (k === 'auto') { if (b.on) st.auto[b.key] = { by: op.author }; else delete st.auto[b.key]; }
    else if (k === 'tod') {
        if (typeof b.key !== 'string' || !b.v || typeof b.v.t !== 'number') return;
        st.tods[b.key] = { t: b.v.t, by: op.author, form: String(b.v.form || b.key), streak: Number(b.v.streak) || 0 };
    } else if (k === 'tod_clear') { delete st.tods[b.key]; }
    else if (k === 'drop') {
        if (st.drops.some(d => d.id === b.id)) return;
        const twin = st.drops.find(d => d.item === b.item && d.mob === b.mob && d.slot === b.slot && d.itemId === b.itemId && Math.abs((d.t || 0) - (b.t || 0)) < 60);
        if (twin) { st.aliases[b.id] = twin.id; return; }
        st.drops.push({ id: b.id, t: b.t, item: b.item, itemId: b.itemId, mob: b.mob, slot: b.slot, event: b.event, seenBy: op.author });
        if (st.drops.length > 500) st.drops.splice(0, st.drops.length - 500);
    } else if (k === 'drop_upd') {
        const d = st.drops.find(x => x.id === (st.aliases[b.id] || b.id)); if (d) d.lotted = b.lotted || d.lotted;
    } else if (k === 'drop_rm') {
        const want = st.aliases[b.id] || b.id; const i = st.drops.findIndex(x => x.id === want); if (i >= 0) st.drops.splice(i, 1);
    } else if (k === 'live') { st.live[op.author] = { t: op.t, s: b }; }
    st.seq = Math.max(st.seq, op.seq);
}

async function materialize(db, lsId) {
    const snap = await db.prepare('SELECT seq, json FROM snapshots WHERE ls_id = ?').bind(lsId).first();
    let st = snap ? JSON.parse(snap.json) : emptyBook();
    const from = st.seq;
    for (;;) {
        const rows = await db.prepare('SELECT seq, author, kind, body, t FROM ops WHERE ls_id = ? AND seq > ? ORDER BY seq LIMIT 2000').bind(lsId, st.seq).all();
        for (const r of rows.results) applyOp(st, { seq: r.seq, author: r.author, kind: r.kind, body: JSON.parse(r.body), t: r.t });
        if (rows.results.length < 2000) break;
    }
    if (st.seq !== from) await db.prepare('INSERT OR REPLACE INTO snapshots (ls_id, seq, json) VALUES (?, ?, ?)').bind(lsId, st.seq, JSON.stringify(st)).run();
    return st;
}

// hnm.json index: lower-case name -> the timer entry it shares (HQ forms point at the NQ timer)
const HNM_BY_NAME = {};
for (const e of HNM) HNM_BY_NAME[e.name.toLowerCase()] = e;
function timerKey(name) {
    const e = HNM_BY_NAME[String(name || '').toLowerCase()];
    return e ? (e.sharesWith || e.name) : null;
}
function timerDef(key, custom) {
    const e = HNM_BY_NAME[String(key).toLowerCase()];
    if (e) return (e.sharesWith ? HNM_BY_NAME[e.sharesWith.toLowerCase()] : e);
    if (custom && custom[key]) return { name: key, minS: custom[key].minS, maxS: custom[key].maxS, zone: '' };
    return null;
}

function bookView(st, ls) {
    const t = now();
    const standings = Object.entries(st.members).map(([name, m]) => ({ name, ...m })).sort((a, b) => b.dkp - a.dkp || a.name.localeCompare(b.name));
    const timers = Object.entries(st.tods).map(([key, v]) => {
        const e = timerDef(key, st.custom);
        const row = { mob: key, form: v.form, zone: e ? e.zone : '', tod: v.t, by: v.by };
        if (e && e.minS && !e.forced) {
            row.opens = v.t + e.minS; row.closes = v.t + (e.maxS || e.minS);
            row.state = t < row.opens ? 'waiting' : (t <= row.closes ? 'open' : 'closed');
        } else row.state = e && e.forced ? 'forced' : 'no-timer';
        return row;
    }).sort((a, b) => (a.opens || 9e12) - (b.opens || 9e12));
    const live = Object.entries(st.live).filter(([, l]) => t - (l.t || 0) < 3 * 3600 && l.s && (l.s.event || l.s.auction)).map(([who, l]) => ({ who, ...l.s }));
    return { ls, time: t, standings, timers, prices: st.prices, drops: st.drops.slice(-50), history: st.history.slice(-100), live, auto: Object.keys(st.auto) };
}

function botOp(st, kind, body, name) {
    const id = 'bot-' + now().toString(16) + '-' + randomToken().slice(0, 8);
    return { cid: id, kind, body: stampAuthor({ ...body }, name), id };
}

// POST /v1/tod {mob, time?('now' | unix seconds | '-15m'), form?}   officer keys
// POST /v1/adjust {name, amount, reason?}                            officer keys
// POST /v1/award {name, price, item}                                 officer keys
async function v1write(db, me, path, b) {
    if (LEVEL[me.role] < LEVEL.officer) return fail('This key is read-only.', 403);
    const st = await materialize(db, me.lsId);
    const ops = [];
    if (path === '/v1/tod') {
        const key = timerKey(b.mob) || (st.custom[String(b.mob || '')] ? String(b.mob) : null);
        if (!key) return fail('Unknown mob. Use a name from GET /v1/book timers or hnm.json.');
        let t = now();
        const tv = b.time;
        if (typeof tv === 'number') t = Math.floor(tv);
        else if (typeof tv === 'string' && /^-\d+m$/.test(tv)) t = now() - parseInt(tv.slice(1)) * 60;
        else if (typeof tv === 'string' && /^-\d+h$/.test(tv)) t = now() - parseInt(tv.slice(1)) * 3600;
        if (Math.abs(t - now()) > 3 * 86400) return fail('That time is more than 3 days from now.');
        const form = b.form ? String(b.form).slice(0, 30) : key;
        const id = 'bot-' + now().toString(16) + '-' + randomToken().slice(0, 8);
        ops.push({ cid: id + 'a', kind: 'tod', body: { key, v: { t, by: me.name, form, streak: 0 } } });
        ops.push({ cid: id + 'b', kind: 'rec', body: { id, t: now(), kind: 'tod', by: me.name, mob: key, text: `${form} ToD ${new Date(t * 1000).toISOString()}` } });
    } else if (path === '/v1/adjust') {
        const name = charName(b.name), amount = Math.trunc(Number(b.amount));
        if (!name || !Number.isFinite(amount) || amount === 0 || Math.abs(amount) > 10000) return fail('Need a character name and a non-zero amount.');
        const why = b.reason ? String(b.reason).slice(0, 80) : '';
        const id = 'bot-' + now().toString(16) + '-' + randomToken().slice(0, 8);
        ops.push({ cid: id, kind: 'rec', body: { id, t: now(), kind: 'adjust', by: me.name, deltas: [{ n: name, d: amount }], text: `${name} ${amount >= 0 ? '+' : ''}${amount}${why ? ' (' + why + ')' : ''}` } });
    } else if (path === '/v1/award') {
        const name = charName(b.name), price = Math.trunc(Number(b.price)), item = String(b.item || '').slice(0, 60);
        if (!name || !Number.isFinite(price) || price < 0 || !item) return fail('Need a character name, a price and an item.');
        const id = 'bot-' + now().toString(16) + '-' + randomToken().slice(0, 8);
        ops.push({ cid: id, kind: 'rec', body: { id, t: now(), kind: 'win', by: me.name, item, deltas: [{ n: name, d: -price }], text: `${name} won ${item} for ${price}` } });
    } else return fail('Unknown endpoint.', 404);
    const ins = ops.map(o => db.prepare('INSERT OR IGNORE INTO ops (ls_id, cid, author, kind, body, t) VALUES (?, ?, ?, ?, ?, ?)').bind(me.lsId, o.cid, me.name, o.kind, JSON.stringify(o.body), now()));
    await db.batch(ins);
    return json({ ok: true, by: me.name, ops: ops.map(o => o.cid) });
}

export default {
    async fetch(req, env) {
        const path = new URL(req.url).pathname.replace(/\/+$/, '');
        if (req.method === 'GET' && path === '/v1/book') {
            const me = await authKey(env.DB, req, null);
            if (!me) return fail('Bad or revoked API key.', 401);
            if (me.limited) return fail('Too many calls; wait a minute.', 429);
            try { return json(bookView(await materialize(env.DB, me.lsId), me.ls)); }
            catch (e) { return fail('Server error: ' + (e && e.message || e), 500); }
        }
        if (req.method !== 'POST') return json({ service: 'heaphkp', ok: true, api: ['GET /v1/book', 'POST /v1/tod', 'POST /v1/adjust', 'POST /v1/award'] });
        const len = Number(req.headers.get('content-length') || 0);
        if (len > 512 * 1024) return fail('Request too large.', 413);
        const text = await req.text();
        if (text.length > 512 * 1024) return fail('Request too large.', 413);
        let b;
        try { b = JSON.parse(text); } catch { return fail('Bad JSON.'); }
        if (!b || typeof b !== 'object') return fail('Bad JSON.');
        try {
            if (path === '/register') return await register(env.DB, b, req);
            if (path === '/invite') return await invite(env.DB, b);
            if (path === '/join') return await join(env.DB, b);
            if (path === '/sync') return await sync(env.DB, b);
            if (path === '/keys') return await makeKey(env.DB, b);
            if (path === '/keys/revoke') return await revokeKey(env.DB, b);
            if (path.startsWith('/v1/')) {
                const me = await authKey(env.DB, req, b);
                if (!me) return fail('Bad or revoked API key.', 401);
                if (me.limited) return fail('Too many calls; wait a minute.', 429);
                if (path === '/v1/book') return json(bookView(await materialize(env.DB, me.lsId), me.ls));
                return await v1write(env.DB, me, path, b);
            }
            return fail('Unknown endpoint.', 404);
        } catch (e) {
            return fail('Server error: ' + (e && e.message || e), 500);
        }
    },
};
