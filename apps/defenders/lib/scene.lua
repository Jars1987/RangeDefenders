local s=...
if s[56] then
  s[56]=nil; s[57]="play"; s[39]=nil
  assert(fs.load("lib/pool.lua"))(s)
  assert(fs.load("lib/setup.lua"))(s,"start")
elseif s[21] then
  s[39]=nil; s[21]=nil
  assert(fs.load("lib/pool.lua"))(s)
  assert(fs.load("lib/board.lua"))(s,"finish")
else
  assert(fs.load("lib/pool.lua"))(s)
  assert(fs.load(s[57]=="over" and "lib/board.lua" or "lib/menu.lua"))(s,"draw")
end
s[20]=nil
