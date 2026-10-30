import os, lupa
L = lupa.LuaRuntime()
chk = L.eval('function(s) local f,e=load(s,"=x"); return f and "compile OK" or e end')
D = os.environ.get('HEAPHKP_ADDON', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'addons', 'heaphkp'))
for f in ('heaphkp.lua', 'net.lua', 'hnm_data.lua'):
    print(f, chk(open(os.path.join(D, f), encoding='utf-8').read()))
