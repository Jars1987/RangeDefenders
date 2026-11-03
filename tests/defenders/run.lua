-- Run from repository root: lua tests/defenders/run.lua all
local stub=dofile('tests/defenders/stub.lua')
local bot=dofile('tests/defenders/bot.lua')
local json=dofile('tests/defenders/json.lua')
local scenarios,order={},{}
local current={}
local function new(c) local h=stub.new(c); current[#current+1]=h; return h end
local function scenario(name,fn) scenarios[name]=fn; order[#order+1]=name end
local function ready(c) local h=new(c); h:tick(2); return h end
local function play(h) h:key('select'); assert(h:find('/^\\'),'player missing') end
local function clear(h) bot.until_true(h,function(b) return b:has('WAVE 2') end,4000) end
local function read(path)
  local f=assert(io.open(path)); local text=f:read('*a'); f:close(); return text
end
local screening='https://www.range.org/product/transaction-screening?utm_source=bp26-badge'
local function qr(h)
  for _,o in ipairs(h.objects) do if o.kind=='qr' and o.visible and not o.removed then return o end end
end
-- Exercise the normal finish transition with fixed scores, identities and days.
local function finish(h,score,wave)
  h:invoke(function()
    local s=h.state
    s[49]=score; s[62]=wave or 1; s[28]='WALLET DRAINER'
    s[57]='over'; s[21]=true; s[20]=true
    h.env.on_tick(50)
  end)
  assert(h:has('RANGE ALERT') and h:has('WALLET DRAINER'))
end
scenario('defenders_play',function()
  local h=ready(); play(h); clear(h)
  assert(h:has('WAVE CLEARED +1 LIFE') and not h:has('RANGE ALERT'))
end)
scenario('defenders_boss',function()
  local h=ready(); play(h)
  bot.until_true(h,function(b) return b:find('<LAZARUS>') end,800,'boss')
  bot.until_true(h,function(b) return b:has('LAZARUS +300') end,1200,'boss')
  bot.breach(h)
  assert(h:has('RANGE ALERT') and qr(h),'boss run missing result QR')
  assert(h.state[9] and h.store.best>=300)
end)
scenario('defenders_breach',function()
  local h=ready(); play(h); bot.breach(h)
  assert(h:has('RANGE ALERT'))
  assert(h:has('FAKE MINT SITE') or h:has('RAINBOW DRAINER') or h:has('WALLET DRAINER'),'threat name missing')
  assert(qr(h) and h:has('Scan to post your score'))
  h:key('back'); h:key('right'); assert(h:has('Jose Santos and Range'))
  h:key('back'); play(h); assert(h:has('WAVE 1'))
end)
scenario('defenders_about',function()
  local h=ready(); h:key('right')
  assert(h:has('Solana Defenders by') and h:has('Jose Santos and Range'))
  local q=assert(qr(h)); assert(q.text_value==screening and q.w==166 and q.y+q.h==202)
  h:key('back'); assert(h:has('Solana Defenders')); play(h)
  assert(not qr(h),'about QR survived into play')
end)
scenario('defenders_budget',function()
  local h=ready(); play(h)
  local allocated=#h.objects
  bot.until_true(h,function(b) return b:find('<LAZARUS>') end,800,'boss')
  for _=1,60 do bot.step(h,'boss') end
  assert(#h.objects==allocated,'widgets allocated during play')
  h:key('back'); assert(h:has('Paused'))
  local p=h:find('Paused'); h:tick(100); assert(p.visible)
  h:key('select'); clear(h)
  assert(h.max_live<=64 and h.max_instructions<200000 and h.peak_total<24451)
  assert(h.peak_heap<=32768,'heap exceeds 32 KB target: '..h.peak_heap)
  local manifest=assert(json.decode(read('apps/defenders/app.json')))
  assert(manifest.id=='range-defenders' and manifest.name=='Solana Defenders')
  assert(manifest.category=='games' and manifest.icon=='play' and manifest.accent=='14F195')
  assert(table.concat(manifest.permissions,',')=='led,lamps' and manifest.hosts==nil)
end)
scenario('defenders_exit',function()
  local h=new(); h:invoke(h.env.on_exit); h:tick(3)
  assert(h.store.welcome==nil,'late award callback wrote after exit')
  assert(h.led[1]==0 and h.led[2]==0 and h.led[3]==0)
  assert(h:key('select')==true and not h:find('/^\\'))
  local menu=ready(); assert(menu:key('back')==false)
end)
scenario('defenders_module_lifecycle',function()
  local h=ready({award_delay=2000})
  assert(h.env.package==nil,'stub exposed unavailable OS API')
  assert(not pcall(h.env.collectgarbage,'collect'),'stub allowed unavailable manual GC')
  play(h); h:tick(400)
  assert(h:has('WAVE 1') and #h.awards==1 and h.store.welcome==true,'play lost delayed welcome award')
  assert(h.resident['@apps/defenders/lib/play.lua'])
  assert(not h.resident['@apps/defenders/lib/menu.lua'] and not h.resident['@apps/defenders/lib/code.lua'])
  for _=1,12 do
    h:key('back'); assert(h:has('Paused') and h.resident['@apps/defenders/lib/play.lua'])
    h:key('back'); h:key('right'); assert(qr(h))
    h:key('back'); play(h)
  end
  assert(h.peak_total<24451 and h.max_live_play<=45)
end)
scenario('f1_widget_pools_and_compile_lifetime',function()
  local h=ready({award_delay=2000})
  local function menu()
    for _,o in ipairs(h.objects) do if not o.removed then
      assert(o.text_value~='<W>' and o.text_value~='{V}' and o.text_value~='(@)' and o.text_value~='[v]','enemy widget alive on menu')
    end end
  end
  local function playing()
    assert(h.live<=45,'more than 45 play widgets')
    for _,o in ipairs(h.objects) do if not o.removed then
      assert(o.kind~='qr' and o.w~=300,'overlay alive during play')
    end end
  end
  menu(); play(h); playing(); h:tick(400); playing()
  assert(h.loads['lib/play.lua']==1,'play recompiled during play')
  h:key('back'); menu(); h:key('select'); playing()
  assert(h.loads['lib/play.lua']==1,'pause recompiled play')
  bot.breach(h); menu(); h:key('back'); menu(); play(h); playing()
  assert(h.loads['lib/play.lua']==2,'game lifetime broken')
end)
scenario('x_title_copy',function()
  local h=ready()
  assert(h:has('Top score each day wins !LAMPs'))
  assert(h:has('Tweet your score and tag @range_org'))
  assert(not h:has('Link X to earn !LAMPs'))
  assert(h:has('TODAY 0   BEST 0'))
  local lines=0
  for _,o in ipairs(h.objects) do if o.kind=='label' and o.visible and not o.removed and o~=h.hint then
    lines=lines+1
    for _,word in ipairs({'booth','finals','free'}) do assert(not o.text_value:lower():find(word,1,true)) end
  end end
  assert(lines<=5)
end)
scenario('x_no_http',function()
  local files=assert(io.popen('rg --files apps/defenders'))
  local bytes=0
  for path in files:lines() do
    local text=read(path); bytes=bytes+#text
    assert(not text:find('%f[%w_]http%f[^%w_]') and not text:find('%f[%w_]ws%f[^%w_]'),'transport reference: '..path)
    assert(not text:find('%f[%w_]package%f[^%w_]') and not text:find('%f[%w_]collectgarbage%f[^%w_]'),'unavailable API: '..path)
  end
  assert(files:close())
  assert(io.open('apps/defenders/lib/net.lua')==nil)
  -- Baseline package bytes measured from the unchanged branch version.
  assert(bytes<17224,'app grew after removing networking: '..bytes)
  local h=ready(); assert(h.env.http==nil and h.env.ws==nil and h.env.profile==nil)
  play(h); bot.breach(h); assert(#h.calls==0)
end)
scenario('x_welcome_award_once',function()
  local h=new(); assert(#h.awards==1 and h.store.welcome==nil)
  play(h); h:tick(2); assert(h.store.welcome==true)
  assert(h:has('WAVE 1'),'award blocked play')
  h:tick(20); assert(#h.awards==1)
  local again=ready({store=h.store}); assert(#again.awards==0)
  for _,w in ipairs(h.writes) do if w[1]=='welcome' then assert(w[2]==true) end end
  local legacy=ready({store={welcome={done=true}}}); assert(#legacy.awards==0,'legacy completed award replayed')
end)
scenario('x_welcome_needsx_retry',function()
  local h=ready({needsx=true})
  assert(h:has('Link X to earn !LAMPs') and h.last_toast=='Link X to earn !LAMPs')
  assert(h.store.welcome==nil and #h.awards==1)
  h:tick(1000); assert(#h.awards==1)
  local linked=ready({store=h.store}); assert(#linked.awards==1 and linked.store.welcome==true)
  assert(not linked:has('Link X to earn !LAMPs'))
  local again=ready({store=linked.store}); assert(#again.awards==0)
end)
scenario('x_welcome_failure_retry',function()
  for _,config in ipairs({{award_denied=true},{award_timeout=true},{capzero=true},
      {award_result='bad'},{award_result={}},{award_result={awarded=0}}}) do
    local h=ready(config); assert(#h.awards==1 and h.store.welcome==nil)
    play(h); h:tick(50); assert(h:has('WAVE 1') and #h.awards==1)
    local retry=ready({store=h.store}); assert(#retry.awards==1 and retry.store.welcome==true)
  end
  local partial=ready({award_result={awarded=1}}); assert(partial.store.welcome==true)
end)
scenario('x_tweet_url',function()
  local vectors=assert(json.decode(read('tests/defenders/code-vectors.json')))
  assert(#vectors>=20)
  for i,v in ipairs(vectors) do
    local id=v.badgeId
    if id==nil then id=false end
    local h=ready({badge_id=id,time=v.day and v.day*86400 or false})
    finish(h,v.score,v.wave)
    local q=assert(qr(h))
    local text='I scored '..v.score..' on Solana Defenders at #Breakpoint. Beat it? @range_org '..v.code
    local encoded=text:gsub('([^%w ._-])',function(c) return string.format('%%%02X',c:byte()) end):gsub(' ','+')
    assert(q.text_value=='https://x.com/intent/post?text='..encoded,'tweet fixture '..i)
    assert(#q.text_value<=140 and q.w==202 and q.x+q.w==320 and q.y+q.h==202)
    assert(h:has('SCORE') and h:has(tostring(v.score)) and h:has('BEST '..v.score))
    if i==2 then print('EXAMPLE '..q.text_value) end
  end
end)
scenario('x_every_game_over',function()
  local h=ready({store={best=10000}})
  for _,score in ipairs({1230,0,1230}) do
    play(h); finish(h,score,2)
    assert(qr(h) and qr(h).text_value:find('I+scored+'..score..'+',1,true))
    assert(h:has('BEST 10000') and h.store.best==10000)
    h:key('back')
  end
end)
scenario('x_daily_best',function()
  local h=ready(); finish(h,900,2)
  local url=qr(h).text_value
  assert(h.store.day==20000 and h.store.today==900 and h.store.best==900)
  h.time=20001*86400; h:tick()
  assert(h:has('TODAY 0') and h.store.today==0 and h.store.best==900)
  assert(qr(h).text_value==url,'rollover changed the completed game code')
  h:key('back'); assert(h:has('TODAY 0   BEST 900'))
  play(h); finish(h,100,1); assert(h.store.today==100 and h.store.best==900)
  h:key('select'); finish(h,20,1); assert(h.store.today==100)
  local again=ready({time=h.time,store=h.store}); assert(again:has('TODAY 100   BEST 900'))
  local nextday=ready({time=20002*86400,store=h.store}); assert(nextday:has('TODAY 0   BEST 900'))
  -- A game crossing midnight belongs to its finish day.
  play(nextday); nextday.time=20003*86400; finish(nextday,80,1)
  assert(nextday.store.day==20003 and nextday.store.today==80)
end)
scenario('x_clock_unknown',function()
  local store={best=500,day=19999,today=400}
  local h=ready({time=false,badge_id=false,store=store})
  assert(h:has('BEST 500') and not h:has('TODAY'))
  play(h); finish(h,100,1)
  assert(h:has('TODAY --') and h.store.today==400 and h.store.day==19999)
  assert(h.store.best==500)
  local code=assert(loadfile('apps/defenders/lib/code.lua'))(100,0)
  assert(qr(h).text_value:sub(-6)==code)
  h.time=20000*86400; h:tick(); assert(h.store.today==0)
  h:key('select'); finish(h,700,2); assert(h.store.best==700 and h.store.today==700)
  h.time=nil; h:key('select'); finish(h,800,2)
  assert(h.store.best==800 and h.store.today==700 and h:has('TODAY --'))
end)
scenario('x_retweet_hidden_when_empty',function()
  local h=ready(); finish(h,100,1)
  local url=qr(h).text_value
  assert(not h:has('repost') and not h:has('retweet'))
  h:key('right'); assert(qr(h).text_value==url and not h:has('repost'))
end)
scenario('x_retweet_toggle',function()
  local h=ready({tweet_id='1234567890123456789'}); finish(h,100,1)
  local url=qr(h).text_value
  assert(h:has('RIGHT repost'))
  for _=1,3 do
    h:key('right'); assert(qr(h).text_value=='https://x.com/intent/retweet?tweet_id=1234567890123456789')
    assert(h:has('Scan to repost Range'))
    h:key('right'); assert(qr(h).text_value==url and h:has('Scan to post your score'))
  end
  h:key('right'); h:key('select'); finish(h,200,1)
  assert(qr(h).text_value:find('/post?',1,true),'new game retained repost mode')
end)
scenario('x_qr_missing',function()
  local h=ready({noqr=true}); play(h); bot.breach(h)
  assert(h:has('Scan to post your score') and h:has('https://x.com/') and not qr(h))
  assert(h.last_toast=='Update Solana OS to scan')
  h:key('back'); h:key('right'); assert(h:has('https://www.range.org/') and not qr(h))
  h:key('back'); play(h); assert(h:has('WAVE 1'))
end)
local target=arg[1] or 'all'
if target~='all' then assert(scenarios[target],'unknown scenario: '..target); order={target} end
local passed,worst=0,0
local proxies={}
for _,name in ipairs(order) do
  current={}
  local ok,err=pcall(scenarios[name])
  local instructions,live,heap,total,play_live=0,0,0,0,0
  for _,h in ipairs(current) do
    play_live=math.max(play_live,h.max_live_play)
    instructions=math.max(instructions,h.max_instructions); live=math.max(live,h.max_live); heap=math.max(heap,h.peak_heap); total=math.max(total,h.peak_total)
    for path,bytes in pairs(h.proxies) do proxies[path]=math.max(proxies[path] or 0,bytes) end
  end
  worst=math.max(worst,total)
  print(string.format('%s %s | max instructions/callback=%d | max live UI=%d | peak heap estimate=%d bytes | peak code+heap=%d bytes | max live UI in play=%d',
    ok and 'PASS' or 'FAIL',name,instructions,live,heap,total,play_live))
  if ok then passed=passed+1 else print(tostring(err)) end
end
local paths={}; for path in pairs(proxies) do paths[#paths+1]=path end; table.sort(paths)
for _,path in ipairs(paths) do print(string.format('CODE %s proxy=%d bytes',path:sub(2),proxies[path])) end
print(string.format('worst peak code+heap=%d bytes (limit 24576)',worst))
print(string.format('%d/%d PASS',passed,#order))
if passed~=#order then os.exit(1) end
