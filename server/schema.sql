-- LS DKP sync server (Cloudflare D1). One row per registered linkshell; everything else hangs off ls_id.
CREATE TABLE IF NOT EXISTS ls (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    key     TEXT NOT NULL UNIQUE,        -- lower-case LS name
    display TEXT NOT NULL,
    owner   TEXT NOT NULL,
    created INTEGER NOT NULL
);

-- Who has what role in each LS. 'owner' is set at registration only.
CREATE TABLE IF NOT EXISTS roles (
    ls_id INTEGER NOT NULL,
    name  TEXT NOT NULL,
    role  TEXT NOT NULL,                 -- owner | admin | officer | viewer
    PRIMARY KEY (ls_id, name)
);

-- Device tokens (sha-256 hashed). A token belongs to one character in one LS; its power is that name's current role.
CREATE TABLE IF NOT EXISTS tokens (
    hash      TEXT PRIMARY KEY,
    ls_id     INTEGER NOT NULL,
    name      TEXT NOT NULL,
    created   INTEGER NOT NULL,
    last_seen INTEGER NOT NULL
);

-- One-use invite codes (sha-256 hashed), bound to a name, good for one hour.
CREATE TABLE IF NOT EXISTS invites (
    hash    TEXT PRIMARY KEY,
    ls_id   INTEGER NOT NULL,
    name    TEXT NOT NULL,
    created INTEGER NOT NULL,
    expires INTEGER NOT NULL,
    used    INTEGER NOT NULL DEFAULT 0
);

-- The shared log. Every client applies these in seq order, so every client ends up with the same book.
CREATE TABLE IF NOT EXISTS ops (
    seq    INTEGER PRIMARY KEY AUTOINCREMENT,
    ls_id  INTEGER NOT NULL,
    cid    TEXT NOT NULL,                -- client-made id, so a resent op is stored once
    author TEXT NOT NULL,
    kind   TEXT NOT NULL,
    body   TEXT NOT NULL,
    t      INTEGER NOT NULL,
    UNIQUE (ls_id, cid)
);
CREATE INDEX IF NOT EXISTS ops_ls_seq ON ops (ls_id, seq);

-- Registrations per address per day (CF-Connecting-IP), to stop linkshell-name squatting in bulk.
CREATE TABLE IF NOT EXISTS regs (
    ip  TEXT NOT NULL,
    day INTEGER NOT NULL,
    n   INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (ip, day)
);
