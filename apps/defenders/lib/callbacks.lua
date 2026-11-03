local s=...
local net=assert(fs.load("lib/net.lua"))
local function scene()
  if s[21] or s[57]=="title" then s[39]=nil end
  if s[57]=="play" and s[60][2] then s[20]=nil; return end
  if s[57]=="pause" or (s[57]=="play" and s[39]) then
    for i=2,59 do local p=s[60][i]; if p then p:remove(); s[60][i]=nil end end
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
s[50]=function(path,body,kind)
  s[11]=true; s[18]=7000; s[58]=s[58]+1; s[29]=kind
  local ticket=s[58]
  http.post(s[51]..path,body,function(ok,res)
    if not s[15] and ticket==s[58] and s[11] then s[44]={ok,res} end
  end)
end
function on_tick(ms)
  if s[15] then return end
  ms=math.max(0,math.min(1000,ms))
  s[61]=math.max(0,s[61]-ms)
  if s[23]>0 then s[23]=s[23]-1; if s[23]==0 then led.off() end end
  if s[11] then s[18]=s[18]-ms end
  if s[44] or s[30] or (s[11] and s[18]<=0) or (not s[11] and s[61]==0) then net(s) end
  if s[57]=="play" then s[40]=s[40]+ms; s[39](s,"tick") end
  if s[20] then scene() end
end
function on_key(key,rep)
  if s[15] then return true end
  local handled
  if s[57]=="play" then handled=s[39](s,"key",key,rep)
  elseif s[57]=="pause" then
    if not rep then
      if key=="select" then s[57]="play" elseif key=="back" then s[57]="title" end
      s[20]=true
    end
    handled=true
  else handled=assert(fs.load(s[57]=="over" and "lib/board.lua" or "lib/menu.lua"))(s,"key",key,rep) end
  if s[20] then scene() end
  return handled
end
function on_exit() s[15]=true; led.off(); storage.set("best",s[4]) end
scene()
