"""A fake Ashita client running heaphkp.lua in lupa. Several can run side by side (one per character)."""
import json, os, shutil, struct, urllib.request, lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.environ.get('HEAPHKP_ADDON', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'addons', 'heaphkp'))
ASHITA_LIBS = os.environ.get('ASHITA_LIBS', r'C:\Games\PhoenixXI\addons\libs')
SERVER = 'http://127.0.0.1:8799'


def ls_extra_old(name, item_flag=1):
    """Build the 28-byte linkshell extra data: GroupId, GroupKey, Color, Flag, then the name 6 bits a letter, MSB first."""
    bits = ''
    for ch in name:
        if ch.isdigit(): v = ord(ch) - 48 + 53
        elif ch.isupper(): v = ord(ch) - 65 + 27
        else: v = ord(ch) - 97 + 1
        bits += format(v, '06b')
    bits += '1' * ((-len(bits)) % 8 or 8)
    bits = bits.ljust(15 * 8, '0')[:15 * 8]
    name_bytes = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
    return (struct.pack('<IHHB', 1234, 1, 0xF0F0, item_flag) + name_bytes).ljust(28, b'\0').decode('latin-1')


def ls_extra(name, item_flag=1):
    from lsname_port import encode
    return (struct.pack('<IHHB', 1234, 1, 0xF0F0, item_flag) + encode(name)).ljust(28, b'\0').decode('latin-1')


def py_post(url, payload):
    req = urllib.request.Request(url.replace('https://lsdkp.example.workers.dev', SERVER), payload.encode('latin-1'),
                                 {'content-type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=5) as r: return r.status, r.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()
    except Exception as e: return 0, '{"error": "offline: %s"}' % type(e).__name__


class Client:
    def __init__(self, name, party, zone=5, ls_items=()):
        self.name = name
        self.install = os.path.join(HERE, 'install_' + name)
        shutil.rmtree(self.install, ignore_errors=True)
        os.makedirs(os.path.join(self.install, 'screenshots'))
        os.makedirs(os.path.join(self.install, 'config', 'addons', 'heaphkp', 'drops'))
        L = self.L = lupa.LuaRuntime(unpack_returned_tuples=True)
        g = self.g = L.globals()
        g.INSTALL, g.ADDON = self.install, ADDON
        g.SSDIR = os.path.join(self.install, 'screenshots')
        g.py_post = py_post
        g.py_listdir = lambda p: self._list(os.listdir(p) if os.path.isdir(p) else [])
        g.py_exists = lambda p: os.path.exists(p)
        L.execute(r'''
T = function(t) return t end
setmetatable(_G, { __index = function(_, k) if type(k) == 'string' and k:match('^ImGui') then return k end end })
unpack = table.unpack
NOW = 1793400000; CLK = 0
os.time = (function(orig) return function(t) if t then return orig(t) end return NOW end end)(os.time)
os.clock = function() return CLK end
sent, printed = {}, {}
print = function(s) printed[#printed+1] = s end
party = {}
inv = {}
local P = {
  GetMemberName = function(_, i) return party[i+1] and party[i+1].name or '' end,
  GetMemberZone = function(_, i) return party[i+1] and party[i+1].zone or 0 end,
  GetMemberIsActive = function(_, i) return party[i+1] and 1 or 0 end,
}
local I = {
  GetContainerCountMax = function(_, c) return 80 end,
  GetContainerItem = function(_, c, i) return inv[i+1] end,
  -- equipment slot 16 = LS1: the first linkshell item in the bag; slot 17 empty
  GetEquippedItem = function(_, slot)
    if slot == 16 then for i, it in ipairs(inv) do if it.Flags == 19 then return { Slot = 16, Index = i - 1 } end end end
    return { Slot = slot, Index = 0 }
  end,
}
entflags = {}
tgt = 0
local E = { GetName = function(_, i) return entnames[i] end, GetSpawnFlags = function(_, i) return entflags[i] or 0x10 end }
local TG = { GetTargetIndex = function() return tgt end, GetIsSubTargetActive = function() return false end }
entnames = { [100] = 'Fafnir' }
AshitaCore = {
  GetInstallPath = function() return INSTALL .. '\\' end,
  GetMemoryManager = function() return { GetParty = function() return P end, GetEntity = function() return E end, GetInventory = function() return I end, GetTarget = function() return TG end } end,
  GetChatManager = function() return { QueueCommand = function(_, m, c) sent[#sent+1] = c end } end,
  GetResourceManager = function() return { GetItemById = function(_, id) return { Name = { ({[1]='Ridill'})[id] or ('X'..id) } } end, GetString = function() return nil end } end,
}
ashita = { events = { cb = {} }, fs = {}, misc = { play_sound = function(p) printed[#printed+1] = 'SOUND ' .. p end, open_url = function() end } }
ashita.events.register = function(ev, name, fn) ashita.events.cb[ev] = fn end
ashita.fs.create_directory = function() end
ashita.fs.exists = function(p) return py_exists(p) end
ashita.fs.get_dir = function(p) return py_listdir(p) end
addon = { path = ADDON }
struct = { unpack = function(fmt, data, pos) return string.unpack('<' .. (fmt == 'H' and 'I2' or fmt), data, pos) end }
string.args = function(s) local t = {}; for w in s:gmatch('%S+') do t[#t+1] = w end; return t end
imgui = setmetatable({}, { __index = function(_, k) if k == 'GetFontSize' or k == 'GetWindowWidth' then return function() return 18 end end; if k == 'GetWindowPos' or k == 'GetWindowSize' or k == 'GetCursorScreenPos' then return function() return 10, 10 end end; if k == 'GetWindowDrawList' then return function() return setmetatable({}, { __index = function() return function() end end }) end end; return function() return false end end })
bit = { bor = function(...) local r = 0; for _, v in ipairs({...}) do if type(v) ~= 'number' then return 0 end; r = r | v end; return r end, band = function(a, b) return a & b end, rshift = function(a, n) return a >> n end, lshift = function(a, n) return a << n end }
package.preload['common'] = function() return true end
package.preload['imgui'] = function() return imgui end
''')
        L.execute("package.preload['json'] = function() " + open(os.path.join(ASHITA_LIBS, 'json.lua'), encoding='utf-8').read() + " end")
        L.execute("package.preload['hnm_data'] = function() " + open(os.path.join(ADDON, 'hnm_data.lua'), encoding='utf-8').read() + " end")
        L.execute('''package.preload['net'] = function()
            local json = require('json')
            local M = { blocking = false }
            function M.post(url, body, cb)
                local status, raw = py_post(url, json.encode(body))
                local ok, t = pcall(json.decode, raw)
                cb(ok and status >= 200 and status < 300, status, ok and t or raw)
            end
            function M.step() end
            return M
        end''')
        src = open(os.path.join(ADDON, 'heaphkp.lua'), encoding='utf-8').read()
        src = src.replace('%z', '\\0').replace('local db = defaults();', 'db = defaults();').replace('local access = {', 'access = {')
        for fn in ('register_ls', 'join_ls', 'send_invite', 'switch_book', 'equipped_ls', 'reload_from_server', 'set_role', 'place_bid', 'can_manage', 'read_only', 'adjust', 'emit', 'set_tod', 'new_id'):
            src = src.replace('local function %s(' % fn, 'function %s(' % fn)
        src = src.replace('local alerts = {};', 'alerts = {};').replace('local HK = {};', 'HK = {};').replace('local lsMsg = nil;', 'lsMsg = nil;').replace("local bookKey = 'local';", "bookKey = 'local';").replace('local equipped_ls;', '').replace('local pendingInvites = {};', 'pendingInvites = {};')
        L.eval('function(s) return load(s, "=heaphkp") end')(src)()
        self.set_party(party)
        for i, (iid, lsname) in enumerate(ls_items):
            L.execute('inv[%d] = { Id = %d, Flags = 19, Extra = ls_x }' % (i + 1, iid)) if False else None
            g.ls_x = ls_extra(lsname).encode('latin-1')
            L.execute('inv[#inv+1] = { Id = %d, Flags = 19, Extra = ls_x }' % iid)
        L.execute('ashita.events.cb.load()')
        L.execute("access.server = 'http://127.0.0.1:8799'")
        self.run = L.eval('function(name, a) return ashita.events.cb[name](a) end')

    def _list(self, xs):
        t = self.L.table()
        for i, x in enumerate(xs): t[i + 1] = x
        return t

    def set_party(self, names, zone=5):
        self.L.execute('party = {}')
        for n in names:
            self.L.execute("party[#party+1] = { name = '%s', zone = %d }" % (n, zone))

    def lua(self, code): return self.L.execute(code)
    def ev(self, code): return self.L.eval(code)

    def cmd(self, c): self.run('command', self.L.table_from({'command': c, 'blocked': False}))

    def chat(self, kind, name, msg):
        data = struct.pack('<I B B H', 0, kind, 0, 0) + name.encode().ljust(15, b'\0') + msg.encode() + b'\0'
        self.run('packet_in', self.L.table_from({'id': 0x17, 'data': data.decode('latin-1')}))

    def text(self, s): self.run('text_in', self.L.table_from({'message': s, 'injected': False}))

    def target(self, name, player=True):
        """Put a player (or mob) under the cursor."""
        Client._next_idx += 1
        idx = Client._next_idx
        self.L.execute("entnames[%d] = '%s'; entflags[%d] = %d; tgt = %d" % (idx, name, idx, 0x01 if player else 0x10, idx))

    _next_idx = 300
    def kill(self, mob, msg=6):
        """The battle-message packet 0x029 the server sends for '<player> defeats <mob>.' (6) / 'falls to the ground' (20)."""
        Client._next_idx += 1
        idx = Client._next_idx
        self.L.execute("entnames[%d] = '%s'" % (idx, mob.replace("'", "\\'")))
        data = struct.pack('<I', 0) + struct.pack('<IIIIHHHBB', 1, 2, 0, 0, 1, idx, msg, 0, 0)
        self.run('packet_in', self.L.table_from({'id': 0x29, 'data': data.decode('latin-1')}))

    def write_log(self, lines, days_back=0):
        """A chatlogs\\<Name>_YYYY.MM.DD.log file in this client's fake install, for the backfill test."""
        import datetime
        now = int(self.g.NOW) - days_back * 86400
        d = datetime.datetime.fromtimestamp(now).strftime('%Y.%m.%d')
        os.makedirs(os.path.join(self.install, 'chatlogs'), exist_ok=True)
        with open(os.path.join(self.install, 'chatlogs', '%s_%s.log' % (self.name, d)), 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')

    def step(self, sec=0.0, frames=1):
        for _ in range(frames):
            self.g.CLK = self.g.CLK + sec / frames
            self.g.NOW = int(self.g.NOW + sec / frames)
            self.run('d3d_present', None)

    def settle(self, rounds=4):
        for _ in range(rounds): self.step(16, 2)

    def out(self, tag=''):
        s = list(self.g.sent.values()); p = list(self.g.printed.values())
        print('---', self.name, tag)
        for x in s: print('   >', x)
        for x in p: print('   .', x)
        self.L.execute('sent, printed = {}, {}')
