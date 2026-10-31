-- Run with Lua 5.4 from the repo root. Game source is never rewritten.
-- Gameplay uses normal controls; isolated effect checks call the popup helper.
local Stub = dofile('tools/badge_stub.lua')
local H = {devices={}, details={}, dump=nil, final=false,
  invaders='scripts/range-defenders/main.lua', taint='scripts/range-taint/main.lua'}
local scenario='all'
local i=1
while i<=#arg do
  local a=arg[i]
  if a=='--final' then H.final=true
  elseif a=='--dump-qr' then i=i+1; H.dump=assert(arg[i],'--dump-qr needs a path')
  elseif a=='--invaders' or a=='--taint' then i=i+1; H[a:sub(3)]=assert(arg[i],a..' needs a path')
  elseif a=='--self-test' then scenario='self_test'
  elseif a:sub(1,2)=='--' then error('unknown option '..a)
  else scenario=a end
  i=i+1
end
local function read(path)
  local f=assert(io.open(path,'rb')); local s=f:read('a'); f:close(); return s
end
local function check(ok,msg) if not ok then error(msg or 'assertion failed',2) end end
local function eq(a,b,msg) check(a==b,(msg or 'mismatch')..': expected '..tostring(b)..', got '..tostring(a)) end
local function note(s) H.details[#H.details+1]=s end
local function contains(d,needle,current)
  if current then for _,v in ipairs(d.texts) do if v.text:find(needle,1,true) then return true end end
  else for s in pairs(d.seen) do if s:find(needle,1,true) then return true end end end
  return false
end
local function device(path,seed,opts)
  opts=opts or {}; opts.seed=seed or 7
  local d=Stub.new(opts); H.devices[#H.devices+1]=d
  return d:load(read(path),path)
end
local function step(d,n,controller)
  for frame=1,n do if controller then controller(d,frame) end; d:tick() end
end
local function tap(d,key)
  d:edge(key,true); d:tick(); d:edge(key,false); d:tick()
end
local function until_(d,limit,predicate,controller)
  for frame=1,limit do
    if predicate(d:state()) then return true end
    if controller then controller(d,frame) end
    d:tick()
  end
  return predicate(d:state())
end
local function hold(d,key,down)
  if (d.keys[key] or false)~=down then d:edge(key,down) end
end
local function dump(d) if H.dump then d.fb:dump(H.dump); H.dumped=true end end
local function qr(d,back)
  tap(d,'down'); eq(d:state().mode,'qr','DOWN opens QR'); dump(d)
  tap(d,'b'); eq(d:state().mode,back,'CANCEL returns to QR opener')
end

-- Read-only geometry adapter for the original Invaders closure names. __state
-- remains the assertion surface. No debug library is exposed to either game.
-- This permits real controls for aiming without widening the public hook.
local function locals(d)
  local result,seen={},{}
  local function visit(fn)
    if type(fn)~='function' or seen[fn] then return end
    seen[fn]=true
    local j=1
    while true do
      local name,v=debug.getupvalue(fn,j); if not name then break end
      if name~='_ENV' then
        if result[name]==nil then result[name]=v end
        if type(v)=='function' then visit(v) end
      end
      j=j+1
    end
  end
  visit(d.env.on_update); visit(d.env.on_draw); visit(d.env.on_button)
  return result
end
local function move(d,x)
  local l=locals(d)
  check(type(l.px)=='number','geometry adapter: original px upvalue missing')
  local center=l.px+11
  hold(d,'left',x<center-2); hold(d,'right',x>center+2)
end
local function avoid(d)
  local l=locals(d); local target=l.px+11
  for _,b in ipairs(l.ebullets or {}) do
    if b.y>130 and math.abs(b.x-target)<21 then target=b.x<160 and b.x+35 or b.x-35 end
  end
  move(d,math.max(13,math.min(307,target)))
end
local function aim(d,slot)
  local l=locals(d); local a=(l.aliens or {})[slot]
  if not a then return avoid(d) end
  local fx,fy=l.fx,l.fy
  check(type(fx)=='number' and type(fy)=='number','geometry adapter: fx/fy missing')
  local state=d:state()
  local ratio=state.alive/32
  local speed=16+state.wave*5+(1-ratio)^2*110
  local travel=math.max(0,(208-(fy+a.row*20+7))/280)
  local x=fx+a.col*28+10+(l.fdir or 1)*speed*travel
  -- Predict formation bounce at the surviving formation's edges.
  local minc,maxc=8,-1
  for _,alien in ipairs(l.aliens) do if alien.alive then minc=math.min(minc,alien.col); maxc=math.max(maxc,alien.col) end end
  local left,right=4-minc*28,316-maxc*28-20
  local predicted=x-a.col*28-10
  if predicted>right then x=x-2*(predicted-right) elseif predicted<left then x=x+2*(left-predicted) end
  move(d,math.max(13,math.min(307,x)))
end
local function bot(d,f)
  local s=d:state()
  hold(d,'a',s.mode=='play')
  if s.mode=='play' then
    local slot
    -- Prefer bottommost visible target; aim beyond bunkers by sweeping.
    for j=#s.aliens,1,-1 do if s.aliens[j].alive then slot=j; break end end
    if slot then aim(d,slot) end
    if f%240>200 then avoid(d) end
  end
end

local scenarios={}
function scenarios.invaders_play()
  local d=device(H.invaders,17)
  eq(d:state().mode,'title'); tap(d,'right'); eq(d:state().mode,'about'); tap(d,'b')
  tap(d,'a')
  local initial,hit,dead,waves={},{},{},{}
  local kills,tough=0,0
  local prev=d:state()
  for f=1,3600 do
    if not waves[prev.wave] and #prev.aliens>0 then
      waves[prev.wave]=true; initial,hit,dead={},{},{}
      local count=0
      for j,a in ipairs(prev.aliens) do
        initial[j]=a.hits_left
        if a.hits_left==2 then count=count+1 end
      end
      check(count<=math.floor(#prev.aliens/3),'two-hit quota exceeded')
    end
    bot(d,f); d:tick()
    local now=d:state()
    if now.wave==prev.wave then
      for j,a in ipairs(prev.aliens) do
        local b=now.aliens[j]
        if a.alive and b then
          if a.hits_left==2 and b.alive and b.hits_left==1 then hit[j]=true; tough=tough+1 end
          if not b.alive then
            kills=kills+1; dead[j]=true
            local expected=a.name..' +'..({40,30,20,10})[(j-1)//8+1]
            local found=false
            for _,p in ipairs(now.popups) do if p==expected then found=true end end
            check(found,'kill popup does not equal dead slot attribution: '..expected)
            if initial[j]==2 then check(hit[j],'tough invader skipped 2 -> 1 -> dead') end
          end
        end
      end
    end
    if H.final then for _,text in ipairs(d.texts) do check(not text.text:lower():find('placeholder',1,true),'placeholder text on screen') end end
    prev=now
  end
  check(kills>0,'bot produced no kills')
  check(tough>0,'bot never hit a tough invader')
  hold(d,'a',false); hold(d,'up',false)
  check(until_(d,18000,function(s) return s.mode=='over' end),'no game over')
  local s=d:state()
  check(s.score>0 and s.best>=s.score,'new best not reflected in state')
  eq(tonumber(d.kv.best),s.best,'best not saved in kv')
  check(contains(d,'RANGE ALERT',true),'RANGE ALERT missing')
  step(d,60); qr(d,'over')
  check(contains(d,'Screen Solana addresses with Range'),'QR caption missing')
  note('kills='..kills..' tough_hits='..tough)
end

function scenarios.invaders_killer()
  -- Search fixed seeds using only inputs. Observe a bullet at launch, kill its
  -- known shooter, then steer underneath that same still-airborne bullet.
  for seed=1,32 do
    local d=device(H.invaders,seed); tap(d,'a')
    local seen,target={},nil
    for f=1,4800 do
      local s=d:state(); if s.mode=='over' then break end
      local l=locals(d)
      for _,b in ipairs(l.ebullets or {}) do
        if not seen[b] then
          seen[b]=true
          local best,dist=nil,math.huge
          for slot,a in ipairs(l.aliens or {}) do if a.alive then
            local x=l.fx+a.col*28+9
            local y=l.fy+a.row*20+14
            local distance=math.abs(x-b.x)+math.abs(y-b.y)
            if distance<dist then best,dist=slot,distance end
          end end
          if not target and best and dist<8 then
            local a=s.aliens[best]
            if a and a.name then target={bullet=b,slot=best,name=a.name,dead=false,lives=s.lives} end
          end
        end
      end
      if s.mode=='play' and target then
        local a=s.aliens[target.slot]
        target.dead=target.dead or (a and not a.alive)
        local present=false
        for _,b in ipairs(l.ebullets or {}) do if b==target.bullet then present=true end end
        if not present then target=nil; hold(d,'a',false); avoid(d)
        elseif target.dead then hold(d,'a',false); move(d,target.bullet.x+1)
        else hold(d,'a',true); aim(d,target.slot) end
      elseif s.mode=='play' then hold(d,'a',false); avoid(d) end
      local before=s; d:tick(); local after=d:state()
      if target and target.dead and after.lives<before.lives then
        eq(after.killer and after.killer.name,target.name,'bullet lost dead shooter attribution')
        if after.mode=='over' then
          check(contains(d,'Flagged:',true),'Flagged: missing')
          check(contains(d,'Flagged:  '..target.name,true),'original shooter not displayed')
          note('seed='..seed..' dead shooter='..target.name)
          return
        end
        target=nil
      end
    end
  end
  error('no dead-shooter bullet hit found in seeds 1..32; geometry/timing needs review')
end

function scenarios.invaders_breach()
  for seed=1,12 do
    local d=device(H.invaders,seed); tap(d,'a')
    for _=1,20000 do
      local before=d:state(); if before.mode=='over' then break end
      avoid(d); d:tick(); local s=d:state()
      if (s.breached or 0)>0 then
        eq(s.breached,before.alive,'breach alive count')
        -- The contract keeps the original row-major alien slots (8 columns).
        local slot
        for j,a in ipairs(before.aliens) do if a.alive then
          if not slot or (j-1)//8>(slot-1)//8 then slot=j end
        end end
        check(slot,'no live alien before breach')
        eq(s.killer and s.killer.name,before.aliens[slot].name,'lowest row, leftmost breach name')
        check(contains(d,'Flagged:  '..before.aliens[slot].name,true),'breaching name missing')
        check(contains(d,'threats got through',true),'breach text missing')
        note('seed='..seed..' breached='..s.breached); return
      end
    end
  end
  error('no breach survived in fixed seeds 1..12')
end

function scenarios.invaders_pause()
  local function bullets(d)
    local list=locals(d).ebullets
    check(type(list)=='table','geometry adapter: ebullets missing')
    local known={}
    for _,b in ipairs(list) do known[b]=true end
    return known
  end
  local function quiet(d,known,phase,resume)
    -- Include the SELECT callback's first update in the 15-frame window.
    for f=1,15 do
      if resume and f==1 then d:edge('a',true)
      elseif resume and f==2 then d:edge('a',false) end
      d:tick(); eq(d:state().mode,'play',phase..' did not resume play')
      for b in pairs(bullets(d)) do check(known[b],phase..' spawned an enemy bullet within 0.25 s') end
    end
  end
  for seed=1,16 do
    local d=device(H.invaders,seed); tap(d,'a')
    check(until_(d,300,function(s) return s.mode=='play' end),'play did not start')
    -- Pause just after a shot, so the next shot has at least 0.25 s left.
    check(until_(d,180,function() return next(bullets(d))~=nil end),'no initial enemy bullet')
    local l=locals(d)
    check(l.enemy_cd-l.t>0.25,'pause precondition: next shot too close')
    tap(d,'b'); eq(d:state().mode,'pause'); step(d,180)
    eq(d:state().mode,'pause','three-second pause ended without input')
    quiet(d,bullets(d),'pause',true)
    -- Seek a real lost life with enough cooldown left at the instant of death.
    -- Reading the deadline selects a reproducible case; assertions count shots.
    for _=1,2400 do
      local before=d:state(); if before.mode=='over' then break end
      if before.mode=='play' then
        local target
        for _,b in ipairs(locals(d).ebullets) do if not target or b.y>target.y then target=b end end
        if target then move(d,target.x+1) end
      end
      d:tick(); local after=d:state()
      if after.mode=='dying' and after.lives<before.lives then
        l=locals(d)
        if l.enemy_cd-l.t>0.30 then
          hold(d,'left',false); hold(d,'right',false)
          check(until_(d,100,function(s) return s.mode=='play' end),'dying phase did not resume play')
          quiet(d,bullets(d),'dying',false)
          note('seed='..seed..' pause=3s; pause/dying first 15 frames: no enemy spawns')
          return
        end
      end
    end
  end
  error('no lost-life cooldown case found in fixed seeds 1..16')
end

function scenarios.invaders_names()
  local pools={
    {'WORMHOLE HACKER','BYBIT HACKER','BRIDGE HACKER','RAYDIUM HACKER',
      'SOLEND HACKER','CREMA HACKER','NIRVANA HACKER','CYPHER HACKER',
      'LOOPSCALE HACKER','DEXX HACKER','DEFITUNA HACKER'},
    {'PUMP AND DUMP','SCAM COIN','RUG PULL DEV','PRESALE SCAMMER','FAKE AIRDROP'},
    {'LAZARUS','DPRK WALLET 1','DPRK WALLET 2','LAUNDERING HOP'},
    {'RAINBOW DRAINER','WALLET DRAINER','FAKE MINT SITE'},
  }
  local types={'EXPLOIT','SCAM','MIXER','DRAINER'}
  local d=device(H.invaders,17)
  check(contains(d,'LAZARUS BOSS',true),'title boss name missing')
  check(contains(d,'Screen threats before funds move',true),'title caption missing')
  tap(d,'right'); eq(d:state().mode,'about'); qr(d,'about'); tap(d,'b'); tap(d,'a')
  local twin=device(H.invaders,17); tap(twin,'a')
  local kinds=locals(d).KINDS
  for row,pool in ipairs(pools) do
    eq(#kinds[row].names,#pool,'row pool size')
    for j,name in ipairs(pool) do eq(kinds[row].names[j],name,'fixed roster') end
  end
  for j,a in ipairs(d:state().aliens) do eq(a.name,twin:state().aliens[j].name,'seed replay name') end
  local function roster(s)
    local seen={{},{},{},{}}
    for j,a in ipairs(s.aliens) do
      local row=(j-1)//8+1
      eq(a.type,types[row],'alien row type')
      local expected=pools[row][((j-1)%8+s.wave-1)%#pools[row]+1]
      eq(a.name,expected,'row pool assignment')
      seen[row][a.name]=true
    end
    for row,pool in ipairs(pools) do
      local n=0; for _ in pairs(seen[row]) do n=n+1 end
      eq(n,math.min(8,#pool),'row variety')
    end
  end
  local boss=false
  local function inspect(s)
    roster(s)
    if s.boss then eq(s.boss.name,'LAZARUS','mothership name'); boss=true end
  end
  for f=1,3600 do bot(d,f); d:tick(); inspect(d:state()) end
  hold(d,'a',false); hold(d,'up',false)
  check(until_(d,18000,function(s) inspect(s); return s.mode=='over' end),'named game did not finish')
  check(boss,'no mothership observed')
  check(contains(d,'Flagged:  '..d:state().killer.name,true),'alert name missing')
  check(contains(d,'Funds moved to a flagged wallet',true),'alert caption missing')
  check(not contains(d,'Risk:'),'risk score rendered')
  step(d,60); qr(d,'over')
  for text in pairs(d.seen) do
    for token in text:gmatch('[1-9A-HJ-NP-Za-km-z]+') do
      check(#token<32,'wallet-like token rendered: '..token)
    end
  end
  -- Exercise the real popup helper at both edges in an isolated device.
  -- Only transient effects are added; gameplay scenarios use normal controls.
  local effects=device(H.invaders,17); tap(effects,'a')
  local popup=assert(locals(effects).popup,'popup helper missing')
  local count=0
  for _,name in ipairs({'LOOPSCALE HACKER','DEFITUNA HACKER'}) do
    local text=name..' +40'
    local width=effects.badge.gfx.text_width(text)
    check(width<=320,'longest popup wider than screen')
    for _,x in ipairs({0,320}) do
      popup(x,80,text,effects.badge.gfx.WHITE); effects:draw()
      local rendered=effects.texts[#effects.texts]
      for _,call in ipairs(effects.texts) do if call.text==text then rendered=call end end
      eq(rendered.text,text,'long popup not drawn')
      check(rendered.x>=0 and rendered.x+width<=320,'long popup clips screen')
      eq(rendered.x,x==0 and 0 or 320-width,'popup edge clamp')
      count=count+1
    end
  end
  note('fixed row pools, seeded variety, LAZARUS boss, full-game text; edge popups='..count)
end

local function network(n,opts)
  local bus=Stub.bus(opts)
  for j=1,n do
    local d=device(H.taint,j*23,{mac=string.format('02:00:00:00:%02x:%02x',j//256,j%256)})
    bus:add(d)
    d:edge('a',true); bus:step(); d:edge('a',false); bus:step()
    eq(d:state().mode,'radar','SELECT enters radar')
  end
  return bus,table.unpack(bus.devices)
end
local function ntap(bus,d,key)
  d:edge(key,true); bus:step(); d:edge(key,false); bus:step()
end
local function outbreak(bus,d)
  d:edge('a',true); bus:step(125); d:edge('a',false); bus:step()
  check(d:state().round~='00000000','hold SELECT did not start outbreak')
end
local function waitnet(bus,frames,predicate,controller)
  for _=1,frames do if predicate() then return true end; bus:step(1,controller) end
  return predicate()
end
local function ended(bus)
  for _,d in ipairs(bus.devices) do if d:state().mode~='end' then return false end end
  return true
end
local function autotap(bus,frame)
  -- Normal controls, cycling selected peers; never synthesise protocol answers.
  for _,d in ipairs(bus.devices) do
    if d:state().mode=='radar' then
      local p=frame%48
      if p==0 then d:edge('a',true) elseif p==1 then d:edge('a',false)
      elseif p==4 then d:edge('down',true) elseif p==5 then d:edge('down',false) end
    end
  end
end
function scenarios.taint_2()
  local bus,a,b=network(2); outbreak(bus,a)
  check(waitnet(bus,600,function() return b:state().st=='T' end),'peer not tainted within 10 seconds')
  check(contains(b,'HEAT'),'HEAT meter missing'); check(contains(a,'LAUNDERING'),'LAUNDERING status missing')
  check(waitnet(bus,1200,function() return not a:state().latent end),'LATENT did not end')
  ntap(bus,b,'a'); bus:step(60); ntap(bus,a,'a'); bus:step(60)
  check(waitnet(bus,1800,function() return ended(bus) end),'two-badge containment timeout')
  for _,d in ipairs({a,b}) do
    eq(d:state().result,'CONTAINED'); check(d:state().score>0,'screening score missing')
  end
  check(contains(a,'Quarantined: hop') or contains(b,'Quarantined: hop'),'quarantine status missing')
end

local function hello(round,st,hop,remain) return table.concat({'RT1','H',round,st or 'T',hop or 0,0,remain or 180},'|') end
local FAKE='0a:00:00:00:00:01'
local OTHER='0a:00:00:00:00:02'
local function inject(bus,d,mac,data,rssi) bus:inject(d,mac,data,rssi); bus:step() end
function scenarios.taint_end_screen()
  for _,result in ipairs({'FUNDS ESCAPED','CONTAINED'}) do
    local bus,finished,starter=network(2)
    starter.online=false
    -- A clean late join either times out in one second or contains after LATENT.
    inject(bus,finished,FAKE,hello('00000001','C',0,result=='CONTAINED' and 155 or 1))
    check(waitnet(bus,1200,function() return finished:state().mode=='end' end),'round did not finish')
    eq(finished:state().result,result,'end-screen precondition')
    check(contains(finished,result,true),'finished result not displayed')
    finished.online=false; starter.online=true
    outbreak(bus,starter)
    local new=starter:state().round
    check(new~='00000001','new outbreak reused the finished round')
    finished.online=true
    for _=1,180 do
      bus:step()
      local s=finished:state()
      eq(s.mode,'end','new outbreak dismissed the end screen')
      eq(s.result,result,'new outbreak replaced the finished result')
      eq(s.round,'00000000','finished badge adopted before SELECT')
      check(contains(finished,result,true),'finished result disappeared from screen')
    end
    ntap(bus,finished,'a'); eq(finished:state().mode,'title','SELECT must return to title')
    ntap(bus,finished,'a'); eq(finished:state().mode,'radar','SELECT must enter radar')
    check(waitnet(bus,180,function() return finished:state().round==new end),'badge did not adopt after SELECT')
    eq(finished:state().result,nil,'new round retained previous result')
  end
  note('both end results stay visible until SELECT; next round adopted afterwards')
end

function scenarios.taint_p_flood()
  local bus,victim=network(1); outbreak(bus,victim)
  local initial=victim:state()
  local function mac(j) return string.format('0a:01:00:00:%02x:%02x',j//256,j%256) end
  local report='RT1|P|'..initial.round..'|'..victim.mac..'|'..(initial.hop+1)
  -- Deliver every report, avoiding the seven-packet cap masking the game bug.
  for j=1,200 do inject(bus,victim,mac(j),report) end
  local unknown=victim:state()
  for j=201,230 do
    -- Rotate through 30 roster members; each is present when its P arrives.
    inject(bus,victim,mac(j),hello(initial.round,'T',initial.hop+1))
    inject(bus,victim,mac(j),report)
  end
  local final=victim:state()
  eq(bus.dropped,0,'flood was masked by inbound queue drops')
  eq(unknown.score,initial.score,'non-roster P frames awarded points')
  eq(unknown.children,initial.children,'non-roster P frames created children')
  check(final.children<=20,'P flood exceeded the 20-child bound')
  eq(final.children,20,'roster reports did not exercise the child limit')
  eq(final.score-initial.score,20*25,'accepted children did not award exactly 25 points each')
  note('200 non-roster reports: no awards; 30 roster reports: children='..final.children)
end

function scenarios.taint_arbitration()
  local bus,a,b=network(2)
  a.online=false; b.online=false
  outbreak(bus,a); outbreak(bus,b)
  local ra,rb=a:state().round,b:state().round
  check(ra~=rb,'distinct badges produced identical round ids')
  local lower=ra<rb and ra or rb
  local loser=ra<rb and b or a
  loser.online=true
  local loser_round=loser:state().round
  inject(bus,loser,FAKE,hello(loser_round,'C',0))
  inject(bus,loser,FAKE,'RT1|P|'..loser_round..'|'..loser.mac..'|1')
  ntap(bus,loser,'a')
  check(loser:state().pending and loser:state().credits==2 and loser:state().score==25,
    'arbitration precondition did not dirty pending, credits and score')
  a.online=true; b.online=true
  check(waitnet(bus,180,function() return a:state().round==lower and b:state().round==lower end),'round ids did not converge')
  local s=loser:state()
  check(s.st=='C' or s.st=='E','round switch did not reset state')
  check(s.exposure<=Stub.DT+1e-6,'round switch did not reset exposure before same-frame spread')
  eq(s.hop,0); eq(s.credits,3); eq(s.score,0); eq(s.pending,nil)
  eq(s.children,0); eq(next(s.screened),nil,'round switch screened map')
end

function scenarios.taint_protocol()
  local bus,d=network(1); local round='1234abcd'
  for _,bad in ipairs({'untagged',hello(round,'E',0),hello(round,'T',10),
      hello(round,'T',0,181),'RT1|S|'..round..'|1.5|'..d.mac,
      'RT1|H|'..round..'|T|0|100000|180'}) do
    inject(bus,d,FAKE,bad)
    eq(d:state().round,'00000000','invalid frame adopted a round')
    eq(d:state().roster,0,'invalid frame changed roster')
  end
  inject(bus,d,d.mac,hello(round,'T',0))
  eq(d:state().round,'00000000','own frame accepted')
  inject(bus,d,FAKE,hello(round,'T',0))
  for f=1,420 do
    if f%45==0 then bus:inject(d,FAKE,hello(round,'T',0)) end
    bus:step()
  end
  eq(d:state().st,'T','test participant did not become tainted')
  local request='RT1|S|'..round..'|37|'..d.mac
  local before=d:state(); inject(bus,d,FAKE,request); bus:step(60)
  eq(d:state().st,'Q','screen request did not quarantine')
  inject(bus,d,FAKE,request); bus:step(90)
  local answers={}
  for _,m in ipairs(d.sent) do if m.data:find('RT1|A|'..round..'|37|',1,true)==1 then answers[#answers+1]=m.data end end
  check(#answers>=2,'duplicate request did not receive cached answer')
  eq(answers[1],answers[2],'duplicate request answer changed'); eq(d:state().score,before.score,'duplicate caused score transition')
  local old=d:state()
  inject(bus,d,FAKE,hello('00000000','T',0))
  eq(d:state().round,old.round,'idle HELLO changed round'); eq(d:state().exposure,old.exposure,'idle HELLO exposure')

  local b,x=network(1); outbreak(b,x)
  inject(b,x,FAKE,hello(x:state().round,'C',0))
  local r=x:state().round
  inject(b,x,FAKE,'RT1|P|'..r..'|'..x.mac..'|9')
  eq(x:state().children,0,'wrong hop infection report accepted')
  inject(b,x,FAKE,'RT1|P|'..r..'|'..x.mac..'|1')
  inject(b,x,FAKE,'RT1|P|'..r..'|'..x.mac..'|1')
  eq(x:state().children,1,'infection report not deduplicated'); eq(x:state().score,25)
  ntap(b,x,'a'); check(x:state().pending,'screen did not create pending request')
  local pending=x:state().pending; local credits=x:state().credits
  local answer='RT1|A|'..r..'|'..pending.req..'|'..x.mac..'|Q|1'
  inject(b,x,OTHER,answer)
  check(x:state().pending,'answer from wrong sender accepted'); eq(x:state().credits,credits)
  check(waitnet(b,600,function() return x:state().pending==nil end),'request never timed out')
  eq(x:state().credits,credits+1,'timeout credit not refunded exactly once')
  check(contains(x,'No answer'),'timeout status missing')
  local score=x:state().score
  inject(b,x,FAKE,answer); b:step(60)
  eq(x:state().score,score,'late answer accepted'); eq(x:state().credits,credits+1,'late answer refunded twice')
  eq(next(x:state().screened),nil,'late answer entered screened map')
  -- A fresh request may succeed with N, then another with D. Both status
  -- strings are user-visible outcomes, not merely wire parser acceptance.
  inject(b,x,FAKE,hello(r,'C',0)); ntap(b,x,'a')
  local p=x:state().pending
  check(p,'new screening request missing after timeout')
  inject(b,x,FAKE,'RT1|A|'..r..'|'..p.req..'|'..x.mac..'|N|0')
  eq(x:state().screened[FAKE],'N'); check(contains(x,'No taint found'),'N status missing')
  ntap(b,x,'a'); p=x:state().pending; check(p,'N result incorrectly blocked re-screen')
  inject(b,x,FAKE,'RT1|A|'..r..'|'..p.req..'|'..x.mac..'|D|0')
  eq(x:state().screened[FAKE],'D'); check(contains(x,'Already quarantined'),'D status missing')

  local e,z=network(1)
  inject(e,z,FAKE,hello('00000011','C',0,1)); e:step(90)
  eq(z:state().mode,'end','short adopted round did not end')
  inject(e,z,FAKE,hello('00000011','T',0,180))
  eq(z:state().round,'00000000','ended round was re-adopted')
  eq(z:state().exposure,0,'ended round added exposure')
end

function scenarios.taint_4_lossy()
  local bus,a=network(4,{loss=.10,dup=.05,reorder=true,seed=708})
  outbreak(bus,a)
  local start=bus.frame; local leave=bus.devices[4]
  local function controller(b,f)
    leave.online=not (f>=start+600 and f<start+1200)
    if f>start+1500 then autotap(b,f) end
  end
  check(waitnet(bus,12000,function() return ended(bus) end,controller),'lossy round did not end')
  check(bus.lost>0 and bus.duplicates>0,'loss/dup model not exercised')
  for _,d in ipairs(bus.devices) do check(d:state().result,'rejoined badge has no result') end
  note('lost='..bus.lost..' dup='..bus.duplicates..' overflow='..bus.dropped)
end

function scenarios.taint_20()
  local bus,a=network(20,{seed=20,reorder=true}); outbreak(bus,a)
  local spread,quarantined={},false
  local start=bus.frame
  for _=1,12000 do
    bus:step(1,function(b,f) if f>start+1800 then autotap(b,f) end end)
    for _,d in ipairs(bus.devices) do
      local s=d:state()
      if s.st=='T' then spread[d.mac]=true end
      if s.st=='Q' or contains(d,'Quarantined: hop') then quarantined=true end
      check(s.tx<=2*d.time+4+1e-6,'TX token bucket exceeded on '..d.mac)
      eq(s.tx,#d.sent,'tx hook does not count every send')
    end
    if ended(bus) then break end
  end
  local count=0; for _ in pairs(spread) do count=count+1 end
  check(count>=5,'spread reached only '..count..' badges'); check(quarantined,'no quarantine in 20-badge run')
  check(ended(bus),'20-badge round did not end')
  check(bus.dropped>0,'queue cap stress produced no overflow')
  note('spread='..count..' overflow='..bus.dropped)
end

function scenarios.taint_practice_timeout()
  local d=device(H.taint,223)
  local best=d:state().best; local tx=d:state().tx; local stored=d.kv.best
  tap(d,'down'); eq(d:state().mode,'practice')
  local roster=d:state().roster
  check(contains(d,'PRACTICE: simulated wallets'),'practice banner missing')
  for f=1,5600 do
    if f%30==0 then d:call('on_espnow',FAKE,hello('00000001','T',0),-45) end
    d:tick(); local s=d:state()
    eq(s.tx,tx,'practice transmitted'); eq(s.round,'00000000','practice adopted radio round')
    eq(s.roster,roster,'practice accepted radio peer'); eq(s.best,best,'practice updated best')
    eq(d.kv.best,stored,'practice wrote best to kv')
    if s.mode=='end' then
      note(string.format('practice end at %.2fs: %s',d.time,tostring(s.result)))
      eq(s.result,'FUNDS ESCAPED','no-input practice was contained by SIM screening; tune SIM interval')
      check(contains(d,'PRACTICE',true),'practice end label missing')
      return
    end
  end
  error('practice failed to end after 90 seconds')
end

function scenarios.taint_practice_win()
  local d=device(H.taint,223); local tx=d:state().tx; local best=d:state().best
  tap(d,'down'); eq(d:state().mode,'practice')
  for f=1,5600 do
    if f>1250 then
      local p=f%48
      if p==0 then d:edge('a',true) elseif p==1 then d:edge('a',false)
      elseif p==6 then d:edge('down',true) elseif p==7 then d:edge('down',false) end
    end
    d:tick(); local s=d:state()
    eq(s.tx,tx,'practice transmitted'); eq(s.best,best,'practice saved best')
    if s.mode=='end' then
      eq(s.result,'CONTAINED','scripted practice did not win')
      check(s.score>0,'practice bot never screened a tainted SIM')
      check(contains(d,'PRACTICE',true),'practice end label missing'); qr(d,'end'); return
    end
  end
  error('scripted practice never ended')
end

function scenarios.taint_restart()
  local bus,x=network(1)
  local old='00000001'
  inject(bus,x,FAKE,hello(old,'C',0,1)); bus:step(90)
  eq(x:state().mode,'end'); ntap(bus,x,'a'); eq(x:state().mode,'title')
  ntap(bus,x,'a'); outbreak(bus,x)
  local new=x:state().round; check(new>old,'test needs S > R')
  local exposure=x:state().exposure
  for f=1,600 do
    if f%15==0 then bus:inject(x,FAKE,hello(old,'T',0,170)) end
    bus:step(); eq(x:state().round,new,'finished R displaced new S')
    eq(x:state().exposure,exposure,'finished R changed exposure')
  end
end

-- Self-test is deliberately independent of the production scenarios: it proves
-- SDK boundaries, input ordering, isolated RNG/kv/env, bus faults and QR pixels.
-- Tiny fixture apps are not substitutes for running `all` after game merge.
function scenarios.self_test()
  local d=device('tools/fixtures/invaders.lua',1)
  eq(d:state().mode,'title'); tap(d,'a'); eq(d:state().mode,'play')
  hold(d,'a',true); step(d,12); hold(d,'a',false); step(d,1)
  check(d:state().score>0,'fixture controls did not score')
  local copy=d:state(); copy.aliens[1].name='changed'
  check(d:state().aliens[1].name~='changed','state hook leaked a mutable reference')
  step(d,40); eq(d:state().mode,'over'); eq(tonumber(d.kv.best),d:state().best)
  qr(d,'over')
  local bad={{function() d.badge.gfx.fill_rect(.5,0,1,1,0) end,'fractional gfx'},
    {function() d.badge.gfx.clear(2147483648) end,'wide integer'},
    {function() d.badge.led.gradient(0,0/0) end,'NaN'},
    {function() d.badge.led.pulse(math.huge,0,0) end,'infinity'}}
  for _,case in ipairs(bad) do check(not pcall(case[1]),case[2]..' guard missing') end
  d.badge.led.gradient(0,.25,.5)
  local bus=Stub.bus({seed=13,loss=.10,dup=.05,reorder=true})
  local a=device('tools/fixtures/taint.lua',2,{mac='02:00:00:00:00:02'})
  local b=device('tools/fixtures/taint.lua',3,{mac='02:00:00:00:00:03'})
  bus:add(a); bus:add(b)
  for n=1,100 do bus:inject(b,FAKE,'RT1|test|'..n,-55) end
  bus:step(); eq(b:state().roster,7,'radio inbound cap'); eq(bus.dropped,93)
  for _=1,200 do a.badge.espnow.broadcast('RT1|test'); bus:step() end
  check(bus.lost>0 and bus.duplicates>0,'seeded bus faults not exercised')
  local rand1,rand2=Stub.rng(99),Stub.rng(99)
  for _=1,100 do eq(rand1(),rand2(),'seed replay') end
  local x=Stub.new({seed=4}); local y=Stub.new({seed=4})
  eq(x.env.math.random(),y.env.math.random(),'env RNG independence')
  x.env.table.test='local'; eq(y.env.table.test,nil,'standard library isolation')
  eq(y.env.string.dump,nil,'bytecode export exposed')
  x.kv.best='5'; eq(y.kv.best,nil,'kv isolation')
  local f=read('tools/fixtures/taint.lua'); local z=Stub.new()
  z:load(f,'fixture')
  z:schedule({{frame=1,key='a',down=true},{frame=2,key='a',down=false}})
  z:tick(); eq(z:state().mode,'radar'); check(z.keys.a,'scheduled press missing')
  z:tick(); check(not z.keys.a,'scheduled release missing')
  eq(z.env.io,nil,'io leaked into app'); eq(z.env.debug,nil,'debug leaked into app')
  note('guards, framebuffer, input, kv, isolated environments, deterministic bus faults')
end

local order={'invaders_play','invaders_killer','invaders_breach','invaders_pause','invaders_names','taint_2','taint_arbitration',
  'taint_protocol','taint_4_lossy','taint_20','taint_practice_timeout','taint_practice_win','taint_restart',
  'taint_end_screen','taint_p_flood'}
local selected=scenario=='all' and order or {scenario}
local failures=0
for _,name in ipairs(selected) do
  H.devices,H.details={},{}
  local ok,err=xpcall(function()
    check(scenarios[name],'unknown scenario '..name)
    if H.final and name~='self_test' then
      local paths=name:sub(1,9)=='invaders_' and {H.invaders} or {H.taint}
      for _,path in ipairs(paths) do check(not read(path):lower():find('placeholder',1,true),'remaining placeholder in '..path) end
    end
    scenarios[name]()
  end,debug.traceback)
  local ms=0; for _,d in ipairs(H.devices) do ms=math.max(ms,d.max_ms) end
  if ok then print('PASS '..name..string.format(' max_callback_ms=%.3f',ms)..(#H.details>0 and ' '..table.concat(H.details,'; ') or ''))
  else failures=failures+1; print('FAIL '..name..string.format(' max_callback_ms=%.3f',ms)..' '..tostring(err):gsub('\n',' | ')) end
end
if H.dump and not H.dumped then print('FAIL dump_qr: scenario never reached QR'); failures=failures+1 end
os.exit(failures>0 and 1 or 0)
