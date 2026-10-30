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

const LEVEL = { none: 0, viewer: 1, officer: 2, admin: 3, owner: 4 };
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
    const name = charName(body.n), r = String(body.r || '');
    if (!name || !ROLE_SET.has(r)) return 'bad role change';
    const cur = await db.prepare('SELECT role FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name).first();
    if (cur && cur.role === 'owner') return "can't change the owner";
    if ((r === 'admin' || (cur && cur.role === 'admin')) && me.role !== 'owner') return 'only the owner changes admins';
    if (r === 'none') {
        await db.batch([
            db.prepare('DELETE FROM roles WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
            db.prepare('DELETE FROM tokens WHERE ls_id = ? AND name = ?').bind(me.lsId, name),
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
    return json({
        ops: out, more: out.length === PULL, role: after ? after.role : 'none', ls: me.ls, owner: me.owner,
        roles: await roleList(db, me.lsId), rejected, time: now(),
    });
}

export default {
    async fetch(req, env) {
        const path = new URL(req.url).pathname.replace(/\/+$/, '');
        if (req.method !== 'POST') return json({ service: 'lsdkp', ok: true });
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
            return fail('Unknown endpoint.', 404);
        } catch (e) {
            return fail('Server error: ' + (e && e.message || e), 500);
        }
    },
};
