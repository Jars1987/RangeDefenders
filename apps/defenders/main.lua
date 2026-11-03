local SERVER = "https://rng.example"
-- One phase chunk is retained. Solana OS has no package.loaded or manual GC.
local s = require("lib.core")
s.server=SERVER
local phase,code
local function run(name,event,a,b)
  if phase~=name then
    code=nil; phase=name
    code=assert(fs.load("lib/"..name..".lua"))
  end
  return code(s,event,a,b)
end
local function settle()
  if s.start then s.start=nil; run("play","start") end
  if s.finish then s.finish=nil; run("board","finish") end
  if s.dirty then
    s.dirty=nil; s.hide()
    run(s.state=="play" and "play" or s.state=="over" and "board" or "menu","draw")
  end
end
-- These callbacks retain the bootstrap and state, never a previous phase.
function s.send(path,body,kind)
  s.busy=true; s.deadline=7000; s.ticket=s.ticket+1; s.kind=kind
  local ticket=s.ticket
  http.post(SERVER..path,body,function(ok,res)
    if not s.closed and ticket==s.ticket and s.busy then s.response={ok,res} end
  end)
end
function s.award_reply(ok,r)
  if not s.closed then s.lamp_reply={ok,r} end
end
function on_tick(ms)
  if s.closed then return end
  ms=math.max(0,math.min(1000,ms))
  s.wait=math.max(0,s.wait-ms)
  if s.flash>0 then s.flash=s.flash-1; if s.flash==0 then led.off() end end
  if s.busy then s.deadline=s.deadline-ms end
  if s.response or s.lamp_reply or (s.busy and s.deadline<=0) or (not s.busy and s.need and s.wait==0) then run("net","tick") end
  if s.state=="play" then run("play","tick") end
  settle()
end
function on_key(key,rep)
  if s.closed then return true end
  local handled=run(s.state=="play" and "play" or s.state=="over" and "board" or "menu","key",key,rep)
  settle()
  return handled
end
function on_mesh(from,msg) end
function on_exit()
  s.closed=true; s.ticket=s.ticket+1; led.off(); storage.set("best",s.best)
end
run("init","create")
s.dirty=true; settle()
profile.me(function(ok,p)
  if s.closed then return end
  s.offline=not ok
  s.hello={app="defenders",name=ok and type(p)=="table" and s.clean(p.name,40) or "Player",v="1.0.0"}
  if ok and type(p)=="table" and type(p.x)=="string" then s.hello.x=s.clean(p.x,40) end
  s.need=true; s.dirty=true
end)
