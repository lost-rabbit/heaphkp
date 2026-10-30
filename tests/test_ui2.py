import sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from client import Client

LS = 'Uitest%d' % (int(time.time()) % 100000)
h = Client('Heaph', ['Heaph', 'Donut'], ls_items=[(513, LS)])
h.lua('''
CLICK = false
setmetatable(imgui, { __index = function(_, k)
    if k:find('^Begin') then return function() return true end end
    if k == 'GetWindowPos' or k == 'GetItemRectMin' or k == 'GetCursorScreenPos' or k == 'GetWindowSize' or k == 'CalcTextSize' then return function() return 10, 10 end end
    if k == 'GetFontSize' or k == 'GetWindowWidth' then return function() return 18 end end
    if k == 'InvisibleButton' then return function() return CLICK end end
    if k == 'GetColorU32' then return function() return 0 end end
    if k == 'GetWindowDrawList' or k == 'GetForegroundDrawList' then return function() return setmetatable({}, { __index = function() return function() end end }) end end
    if k == 'GetWindowDrawList' then return function() return { AddCircleFilled = function() end, AddCircle = function() end } end end
    if k == 'Button' or k == 'SmallButton' or k == 'Selectable' or k == 'Checkbox' or k == 'ImageButton' or k == 'IsItemHovered' then return function() return CLICK end end
    return function() return false end
end })''')
h.cmd('/hkp add Donut 5'); h.cmd('/hkp tod Simurgh -1231m'); h.step(6, 2)
h.cmd('/hkp')
for click in (False, True, False, True, False):
    h.g.CLICK = click
    for _ in range(3): h.step(0.5)
print('local book passes ok; book now:', h.ev('bookKey'))
h.lua("register_ls('%s', false)" % LS); h.settle()
h.lua("switch_book(string.lower('%s'))" % LS)
for click in (False, True, False, True, False):
    h.g.CLICK = click
    for _ in range(3): h.step(0.5)
# THEME_LOOP: draw every window style
for th in ('midnight', 'parchment', 'crystal', 'ffxi'):
    h.lua("db.cfg.theme = '%s'" % th)
    for click in (False, True):
        h.g.CLICK = click
        for _ in range(2): h.step(0.5)
print('shared book passes ok; book now:', h.ev('bookKey'), '| err:', h.ev('access.books[bookKey] and access.books[bookKey].err'))
