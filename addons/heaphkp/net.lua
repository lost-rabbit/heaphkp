--[[
* heaphkp/net.lua - JSON POSTs to the sync server without freezing the game.
*
* Each request runs in a coroutine on a non-blocking socket and moves a little every frame (net.step() from
* d3d_present), so a slow server never stalls a frame. "Simple mode" (net.blocking = true) uses LuaSec's own
* https.request instead: fewer moving parts, but the game pauses for the length of each request.
*
* Module names: Ashita ships LuaSocket/LuaSec under addons\libs\socket\, so they are 'socket.ssl', 'socket.ltn12'
* and 'socket.ssl.https' (not the upstream 'ssl' / 'ltn12' / 'ssl.https').
*
* TLS: the server certificate is checked against assets\cacert.pem (the trusted roots exported from Windows) unless
* net.verify is false (Settings > Sync server > "Skip certificate check", for a broken bundle).
]]--

local socket = require('socket');
local okSsl, ssl = pcall(require, 'socket.ssl');
local json = require('json');

local M = { jobs = {}, blocking = false, verify = true, cafile = nil, dns = {} };

local function parse_url(url)
    local scheme, host, port, path = tostring(url or ''):match('^(https?)://([^/:]+):?(%d*)(.*)$');
    if (scheme == nil) then return nil; end
    port = tonumber(port) or ((scheme == 'https') and 443 or 80);
    if (path == '') then path = '/'; end
    return scheme, host, port, path;
end

-- Does the certificate name the host we connected to? LuaSec checks the chain but not the name (11-01 security review).
local function host_matches(cert, host)
    host = tostring(host or ''):lower();
    local function one(pat)
        pat = tostring(pat or ''):lower();
        if (pat == host) then return true; end
        local tail = pat:match('^%*%.(.+)$');
        if tail then
            local h = host:match('^[^%.]+%.(.+)$');
            return (h ~= nil) and (h == tail);
        end
        return false;
    end
    local okx, exts = pcall(function () return cert:extensions(); end);
    if okx and (type(exts) == 'table') then
        for _, ext in pairs(exts) do
            if (type(ext) == 'table') and ((ext.name == 'subjectAltName') or (ext.oid == '2.5.29.17')) then
                for _, names in pairs(ext) do
                    if (type(names) == 'table') then
                        for _, v in pairs(names) do
                            if (type(v) == 'string') and one(v) then return true; end
                            if (type(v) == 'table') and (type(v[1]) == 'string') and one(v[1]) then return true; end
                        end
                    end
                end
            end
        end
    end
    local oks, subj = pcall(function () return cert:subject(); end);
    if oks and (type(subj) == 'table') then
        for _, f in ipairs(subj) do
            if (type(f) == 'table') and ((f.name == 'commonName') or (f.oid == '2.5.4.3')) and one(f.value) then return true; end
        end
    end
    return false;
end
M.host_matches = host_matches;

local function tls_params(host)
    local p = { mode = 'client', protocol = 'any', options = 'all', verify = 'none' };
    if M.verify and (M.cafile ~= nil) then p.verify = 'peer'; p.cafile = M.cafile; end
    return p;
end

local function dechunk(body)
    local out, i = {}, 1;
    while true do
        local size, nl = body:match('^(%x+)[^\r\n]*\r\n()', i);
        if (size == nil) then break; end
        size = tonumber(size, 16);
        if (size == 0) then break; end
        out[#out + 1] = body:sub(nl, nl + size - 1);
        i = nl + size + 2;
    end
    return table.concat(out);
end

local function split_reply(resp)
    local head, body = resp:match('^(.-)\r\n\r\n(.*)$');
    if (head == nil) then error('the server sent a broken reply', 0); end
    local status = tonumber(head:match('^HTTP/%d%.%d (%d+)')) or 0;
    if head:lower():find('transfer%-encoding:%s*chunked') then body = dechunk(body); end
    return status, body;
end

-- A DNS answer is kept for 10 minutes: socket.dns.toip blocks, so it runs rarely.
local function resolve(host)
    local c = M.dns[host];
    if (c ~= nil) and (os.clock() - c.t < 600) then return c.ip; end
    local ip = socket.dns.toip(host);
    if (ip == nil) then error('cannot find ' .. host, 0); end
    M.dns[host] = { ip = ip, t = os.clock() };
    return ip;
end

local function request_async(scheme, host, port, path, payload, timeout)
    local deadline = os.clock() + (timeout or 15);
    local function wait()
        if (os.clock() > deadline) then error('the server took too long', 0); end
        coroutine.yield();
    end
    local ip = resolve(host);
    local tcp = socket.tcp();
    tcp:settimeout(0);
    local ok, err = tcp:connect(ip, port);
    if (not ok) and (err ~= 'timeout') and (err ~= 'Operation already in progress') then
        M.dns[host] = nil;
        error('cannot connect: ' .. tostring(err), 0);
    end
    while true do
        local _, w = socket.select(nil, { tcp }, 0);
        if (w ~= nil) and (w[1] ~= nil) then break; end
        wait();
    end
    local conn = tcp;
    if (scheme == 'https') then
        local wrapped, werr = ssl.wrap(tcp, tls_params(host));
        if (wrapped == nil) then error('tls: ' .. tostring(werr), 0); end
        conn = wrapped;
        if conn.sni then conn:sni(host); end
        conn:settimeout(0);
        while true do
            local done, herr = conn:dohandshake();
            if done then break; end
            if (herr == 'wantread') or (herr == 'wantwrite') or (herr == 'timeout') then wait();
            else error('tls: ' .. tostring(herr) .. (M.verify and ' (certificate check; see Settings > Sync server)' or ''), 0); end
        end
        if M.verify and (M.cafile ~= nil) then
            local cert = conn.getpeercertificate and conn:getpeercertificate() or nil;
            if (cert == nil) or (not host_matches(cert, host)) then
                error('tls: the certificate is not for ' .. tostring(host) .. ' (certificate check; see Settings > Sync server)', 0);
            end
        end
    end
    local req = table.concat({
        ('POST %s HTTP/1.0'):format(path), 'Host: ' .. host, 'User-Agent: heaphkp/1.3', 'Content-Type: application/json',
        'Content-Length: ' .. #payload, 'Connection: close', '', payload,
    }, '\r\n');
    local i = 1;
    while (i <= #req) do
        local n, serr, last = conn:send(req, i);
        if (n ~= nil) then
            i = n + 1;
        elseif (serr == 'wantwrite') or (serr == 'wantread') or (serr == 'timeout') then
            if (last ~= nil) and (last >= i) then i = last + 1; end
            wait();
        else
            error('send failed: ' .. tostring(serr), 0);
        end
    end
    local parts = {};
    while true do
        local data, rerr, partial = conn:receive(8192);
        if (data ~= nil) then
            parts[#parts + 1] = data;
        else
            if (partial ~= nil) and (#partial > 0) then parts[#parts + 1] = partial; end
            if (rerr == 'closed') then break; end
            if (rerr == 'wantread') or (rerr == 'wantwrite') or (rerr == 'timeout') then wait();
            else error('receive failed: ' .. tostring(rerr), 0); end
        end
    end
    pcall(function () conn:close(); end);
    return split_reply(table.concat(parts));
end

local function request_blocking(scheme, url, payload, host)
    local ltn12 = require('socket.ltn12');
    local lib = (scheme == 'https') and require('socket.ssl.https') or require('socket.http');
    lib.TIMEOUT = 8;
    local out = {};
    local req = {
        url = url, method = 'POST', sink = ltn12.sink.table(out), source = ltn12.source.string(payload),
        headers = { ['content-type'] = 'application/json', ['content-length'] = tostring(#payload), ['user-agent'] = 'heaphkp/1.3' },
    };
    if (scheme == 'https') then
        local p = tls_params(host);
        req.verify, req.cafile, req.protocol, req.options = p.verify, p.cafile, p.protocol, p.options;
    end
    local _, code = lib.request(req);
    if (type(code) ~= 'number') then error('network: ' .. tostring(code), 0); end
    return code, table.concat(out);
end

-- cb(ok, status, reply): reply is the decoded JSON table, or an error message when ok is false.
function M.post(url, body, cb)
    local scheme, host, port, path = parse_url(url);
    if (scheme ~= 'https') then cb(false, 0, 'the server address must start with https:// (tokens never go over plain http)'); return; end
    if (scheme == 'https') and (not okSsl) then cb(false, 0, 'the ssl library did not load (socket.ssl)'); return; end
    local payload = json.encode(body);
    local function finish(okRun, status, raw)
        if (not okRun) then cb(false, 0, tostring(status)); return; end
        local okJson, t = pcall(json.decode, raw or '');
        if (not okJson) or (type(t) ~= 'table') then cb(false, status, ('the server said %d'):format(status)); return; end
        cb(status >= 200 and status < 300, status, t);
    end
    if M.blocking then
        finish(pcall(request_blocking, scheme, url, payload, host));
        return;
    end
    M.jobs[#M.jobs + 1] = { co = coroutine.create(request_async), args = { scheme, host, port, path, payload }, finish = finish };
end

function M.step()
    for i = #M.jobs, 1, -1 do
        local j = M.jobs[i];
        local ok, a, b;
        if (j.args ~= nil) then
            ok, a, b = coroutine.resume(j.co, unpack(j.args));
            j.args = nil;
        else
            ok, a, b = coroutine.resume(j.co);
        end
        if (not ok) then
            table.remove(M.jobs, i);
            j.finish(false, a);
        elseif (coroutine.status(j.co) == 'dead') then
            table.remove(M.jobs, i);
            j.finish(true, a, b);
        end
    end
end

function M.busy() return #M.jobs > 0; end

return M;
