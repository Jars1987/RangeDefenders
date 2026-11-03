local s=...
local function scene()
  if s[21] or s[57]=="title" then s[39]=nil end
  if s[57]=="play" and s[60][60] then s[20]=nil; return end
  if s[57]=="pause" or (s[57]=="play" and s[39]) then
    for i=14,83 do local p=s[60][i]; if p then p:remove(); s[60][i]=nil end end
    if s[57]=="pause" then assert(fs.load("lib/pause.lua"))(s) else s[39](s,"draw") end
    s[20]=nil
  else
    assert(fs.load("lib/scene.lua"))(s)
    if s[57]=="play" then
      s[39]=assert(fs.load("lib/play.lua"))
      s[39](s,"start"); s[20]=nil
    end
  end
end
local function day()
  local t=sys.time()
  local d=t and t//86400
  if d~=s[2] then
    s[2]=d; s[3]=nil
    if d then
      s[3]=storage.get("day")==d and (tonumber(storage.get("today")) or 0) or 0
      storage.set("day",d); storage.set("today",s[3])
    end
    s[20]=true
  end
end
day()
function on_tick(ms)
  if s[15] then return end
  ms=math.max(0,math.min(1000,ms))
  day()
  if s[23]>0 then s[23]=s[23]-1; if s[23]==0 then led.off() end end
  if s[57]=="play" then s[39](s,"tick") end
  if s[20] then scene() end
end
function on_key(key,rep)
  if s[15] then return true end
  day()
  local handled
  if s[57]=="play" then handled=s[39](s,"key",key,rep)
  elseif s[57]=="pause" then
    if not rep then
      if key=="select" then s[57]="play" elseif key=="back" then s[57]="title" end
      s[20]=true
    end
    handled=true
  else handled=assert(fs.load(s[57]=="over" and "lib/board.lua" or "lib/menu-key.lua"))(s,"key",key,rep) end
  if s[20] then scene() end
  return handled
end
function on_exit() s[15]=true; led.off(); storage.set("best",s[4]) end
scene()
