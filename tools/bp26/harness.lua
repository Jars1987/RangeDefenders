-- Host-only Lua 5.4 runner for the actual BP26 app and signed server adapter.
local JSON=dofile('tools/bp26/json.lua')
local Stub=dofile('tools/bp26/badge_stub.lua')
local port=18000+math.random(0,20000)
local tmp=os.tmpname()
local function exchange(body)
  local f=assert(io.open(tmp,'w'))f:write(JSON.encode(body))f:close()
  local pipe=assert(io.popen('curl -fsS --max-time 10 -H "content-type: application/json" --data-binary @'..tmp..' http://127.0.0.1:'..port))
  local text=pipe:read('*a')pipe:close()
  return assert(JSON.decode(text),text)
end
local pidfile=tmp..'.pid'
assert(os.execute('HARNESS_PORT='..port..' /opt/homebrew/bin/bun tools/bp26/bridge.ts >'..tmp..'.log 2>&1 & echo $! >'..pidfile))
local ready=false
for _=1,100 do
  local pipe=io.popen('curl -s --max-time 1 -H "content-type: application/json" -d \'{"control":"inspect"}\' http://127.0.0.1:'..port)
  local response=pipe:read('*a')pipe:close()
  if #response>0 then ready=true break end
end
assert(ready,'harness server unavailable')
local current,max_inst,max_ui,losses
local function bus(n,loss)
  local b={badges={},links={},n=n,loss=loss or 0,counter=0}
  function b:nearby(id)
    local list={}
    for _,p in ipairs(self.badges)do if p.id~=id and self.links[id..':'..p.id]~=false then list[#list+1]={id=p.id,name='@'..p.id,kind='badge',rssi=-50,bridged=false}end end
    return list
  end
  function b:send(id,to,msg)
    assert(msg.v==1 and msg.app=='range-lazarus' and not msg.status and not msg.hop and not msg.infector,'role leaked over mesh')
    for _,p in ipairs(self.badges)do if p.id~=id and (to=='*' or to==p.id)then
      self.counter=self.counter+1
      if self.loss>0 and self.counter%self.loss==0 then losses=losses+1
      else p:later(function()p:call(p.env.on_mesh,id,msg)end)end
    end end
  end
  function b:http(id,url,body)return exchange({badge=id,url=url,body=body})end
  for j=0,n-1 do b.badges[#b.badges+1]=Stub.new('B'..j,b)end
  current=b
  return b
end
local function step(ms)
  for t=50,ms,50 do
    if t%1000==0 then exchange({control='advance',ms=1000})end
    for _,p in ipairs(current.badges)do p:tick(50)end
  end
end
local function inspect()return exchange({control='inspect'})end
local function room()
  local state=inspect()
  for _,r in pairs(state.rooms)do return r end
end
local function setup(n,loss)
  exchange({control='reset'})losses=0
  local b=bus(n,loss)step(300)
  for _,p in ipairs(b.badges)do p:key('select')end
  step(11000)
  assert(room(),'room did not form')
  b.badges[1]:key('select')step(400)
  return b
end
local function select_peer(p,id)
  -- Selection is by id in the app; inspect only rendered radar text.
  for _=1,22 do if p:screen():find('> @'..id..' ',1,true)then return end p:key('down')end
  error('target not on radar: '..id..'\n'..p:screen())
end
local function screen(hunter,target)
  local p=current.badges[hunter+1]select_peer(p,'B'..target)p:key('select')step(400)
end
local function isolate(pairs)
  current.links={}
  for _,a in ipairs(current.badges)do for _,b in ipairs(current.badges)do current.links[a.id..':'..b.id]=false end end
  for _,pair in ipairs(pairs)do current.links['B'..pair[1]..':B'..pair[2]]=true current.links['B'..pair[2]..':B'..pair[1]]=true end
end
local scenarios={}
scenarios.lazarus_solo_practice=function()
  bus(1)step(300)current.badges[1]:key('down')
  assert(current.badges[1]:screen():find('Practice',1,true))
  current.badges[1]:key('select')step(20500)current.badges[1]:key('select')step(20500)current.badges[1]:key('select')
  assert(current.badges[1]:screen():find('CAUGHT',1,true))
  assert(current.badges[1].awards==25,'practice awarded points')
end
scenarios.lazarus_6_caught=function()setup(6)step(38000)screen(1,0)assert(room().result=='CAUGHT')end
scenarios.lazarus_6_escaped=function()setup(6)step(55000)assert(room().result=='ESCAPED')end
scenarios.lazarus_quarantine_chain=function()
  setup(6)
  -- Close all links except the source and its first victim before exposure starts.
  isolate({{0,2}})step(50000)
  assert(room().members[3].status=='tainted','first hop not infected')
  isolate({{2,3}})step(26000)
  assert(room().members[4].status=='tainted','second hop not infected')
  isolate({{1,3},{1,2},{1,0}})step(6500)
  screen(1,3)
  local hunter=current.badges[2]
  assert(hunter:screen():find('Caught it from @B2',1,true),'upstream clue missing')
  assert(room().members[4].status=='quarantined')
  isolate({})step(21000)isolate({{1,2}})step(6500)screen(1,2)
  assert(hunter:screen():find('Caught it from @B0',1,true),'source clue missing')
  isolate({})step(21000)isolate({{1,0}})step(6500)screen(1,0)assert(room().result=='CAUGHT')
end
scenarios.lazarus_void_on_disconnect=function()
 setup(6)current.badges[1].online=false step(20000)assert(room().result=='VOID')
end
scenarios.lazarus_4_unranked=function()setup(4)assert(room().ranked==false)step(38000)screen(1,0)assert(room().result=='CAUGHT')assert(next(inspect().payouts)==nil)end
scenarios.lazarus_lossy_mesh=function()setup(6,2)step(38000)screen(1,0)assert(room().result=='CAUGHT')assert(losses>0)end
scenarios.lazarus_20_badges=function()setup(20,3)assert(#room().members==20)step(55000)assert(room().result=='ESCAPED')end
scenarios.lazarus_offline_title=function()
 bus(1)current.badges[1].online=false step(6000)
 assert(current.badges[1]:screen():find('Offline',1,true))current.badges[1]:key('down')step(1000)
 assert(current.badges[1]:screen():find('Practice',1,true))
end
scenarios.lazarus_welcome_needsx=function()
 bus(1)current.badges[1].needsX=true step(1000)
 assert(current.badges[1]:screen():find('Welcome: 25 !LAMPs',1,true))
 assert(current.badges[1].toast=='Link X to earn !LAMPs')
 assert(not current.badges[1].storage.welcome_award,'needsX was consumed')
end
scenarios.lazarus_http_order=function()
 bus(1)
 local p=current.badges[1]
 local profile=p.queue[1]p.queue={}
 step(1000)
 assert(next(inspect().players)==nil,'poll raced profile/hello')
 p:later(profile)step(500)
 assert(p.awards==25,'welcome handshake lost')
 local original=p.env.http.post
 local held=nil
 p.env.http.post=function(url,body,cb)
   original(url,body,function(ok,r)
     if url:find('/poll',1,true)then held=function()cb(ok,r)end else cb(ok,r)end
   end)
 end
 step(6000)assert(held,'routine poll not started')
 p:key('select')p:call(held)step(500)
 assert(inspect().players['prod:B0'].ready==true,'routine response erased queued action')
end
scenarios.lazarus_install_qr=function()
 bus(1)step(500)
 local p=current.badges[1]
 p:key('right')step(500)assert(p.qr,'install QR missing')
 assert(p.live==10,'QR widget count')
 p:key('back')assert(not p.qr,'QR not removed')
 p:key('right')step(500)assert(p.qr,'reopened QR missing')assert(p.live==10,'QR widgets leaked')
end
local heap_cache={}
local names={}for n in pairs(scenarios)do names[#names+1]=n end table.sort(names)
local failed,passed=0,0
local source=assert(io.open('apps/lazarus/main.lua'))local text=source:read('*a')source:close()
assert(#text<=65536,'main.lua >64KB')
local manifest=assert(io.open('apps/lazarus/app.json'))local app=JSON.decode(manifest:read('*a'))manifest:close()assert(#app.name<=20)
for _,n in ipairs(names)do if (arg[1] or 'all')=='all' or arg[1]==n then
 exchange({control='reset'})current=nil
 local ok,err=pcall(scenarios[n])
 max_inst,max_ui=0,0
 if current then for _,p in ipairs(current.badges)do max_inst=math.max(max_inst,p.max_instructions)max_ui=math.max(max_ui,p.max_ui)end end
 if ok then passed=passed+1 else failed=failed+1 end
 local badges=current and #current.badges or 1
 if not heap_cache[badges]then
   local pipe=assert(io.popen('/opt/homebrew/opt/lua@5.4/bin/lua tools/bp26/heap.lua '..badges))
   local estimate=pipe:read('*a')local success=pipe:close()
   assert(success,'heap probe failed')heap_cache[badges]=assert(tonumber(estimate))
 end
 print(string.format('%s %s max_instructions=%d max_live_ui=%d heap_est_kb=%.1f mesh_drops=%d%s',ok and 'PASS' or 'FAIL',n,max_inst,max_ui,heap_cache[badges],losses or 0,ok and '' or ' '..tostring(err)))
end end
local f=assert(io.open(pidfile))local pid=f:read('*a')f:close()os.execute('kill '..pid)os.remove(pidfile)os.remove(tmp)os.remove(tmp..'.log')
print(string.format('%d/%d PASS',passed,passed+failed))
assert(passed+failed>0,'unknown scenario')
if failed>0 then os.exit(1)end
