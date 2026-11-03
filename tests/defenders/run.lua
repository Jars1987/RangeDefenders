-- Run from repository root: lua tests/defenders/run.lua all
local stub=dofile('tests/defenders/stub.lua')
local bot=dofile('tests/defenders/bot.lua')
local json=dofile('tests/defenders/json.lua')
local scenarios,order={},{}
local current={}
local function new(c) local h=stub.new(c); current[#current+1]=h; return h end
local function scenario(name,fn) scenarios[name]=fn; order[#order+1]=name end
local function ready(c) local h=new(c); h:tick(2); return h end
local function play(h) h:key('select'); h:tick(); assert(h:find('/^\\'),'player missing') end
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
  bot.until_true(h,function(b) return b:find('<o_o_oo_o_o>') end,800,'boss')
  bot.until_true(h,function(b) return b:has('LAZARUS +300') end,1200,'boss')
  bot.breach(h)
  assert(h:has('RANGE ALERT') and qr(h),'boss run missing result QR')
  assert(h.state[9] and h.store.best>=300)
end)
scenario('defenders_breach',function()
  local h=ready(); play(h); bot.breach(h)
  assert(h:has('RANGE ALERT'))
  assert(h:has('FAKE MINT SITE') or h:has('RAINBOW DRAINER') or h:has('WALLET DRAINER'),'threat name missing')
  assert(qr(h) and h:has('Photo this screen, scan to post'))
  h:key('back'); h:key('right'); assert(h:has('Jose Santos and Range'))
  h:key('back'); play(h); assert(h:has('WAVE 1'))
end)
scenario('defenders_about',function()
  local h=ready(); h:key('right')
  assert(h:has('Solana Defenders by') and h:has('Jose Santos and Range'))
  local q=assert(qr(h)); assert(q.text_value==screening and q.w==166 and q.y+q.h==202)
  h:key('back'); assert(h:has('SOLANA') and h:has('DEFENDERS')); play(h)
  assert(not qr(h),'about QR survived into play')
end)
scenario('defenders_budget',function()
  local h=ready(); play(h)
  local allocated=#h.objects
  bot.until_true(h,function(b) return b:find('<o_o_oo_o_o>') end,800,'boss')
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
  assert(h.peak_total<24451 and h.max_live_play<=60)
end)
scenario('f1_widget_pools_and_compile_lifetime',function()
  local h=ready({award_delay=2000})
  local function menu()
    for i=60,83 do assert(h.state[60][i]==nil,'alien alive on menu') end
  end
  local function playing()
    assert(h.live<=60,'more than 60 play widgets')
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
  assert(lines<=17)
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
    h:key('right'); assert(qr(h).text_value==url and h:has('Photo this screen, scan to post'))
  end
  h:key('right'); h:key('select'); finish(h,200,1)
  assert(qr(h).text_value:find('/post?',1,true),'new game retained repost mode')
end)
scenario('x_qr_missing',function()
  local h=ready({noqr=true}); play(h); bot.breach(h)
  assert(h:has('Photo this screen, scan to post') and h:has('https://x.com/') and not qr(h))
  assert(h.last_toast=='Update Solana OS to scan')
  h:key('back'); h:key('right'); assert(h:has('https://www.range.org/') and not qr(h))
  h:key('back'); play(h); assert(h:has('WAVE 1'))
end)
scenario('look_title_table',function()
  local colors={0xFF4040,'orange','yellow','pink','aqua'}
  local names={'EXPLOIT','SCAM','MIXER','DRAINER','LAZARUS'}
  -- Model the measured size-12 mono advance (about 6.5 px on the emulator) and normal word wrapping.
  local function box(o)
    local width=o.w or #o.text_value*6.5
    local columns=math.floor(width/6.5)
    local lines=0
    for text in (o.text_value..'\n'):gmatch('(.-)\n') do
      local used=0
      lines=lines+1
      for spaces,word in text:gmatch('(%s*)(%S+)') do
        local gap=#spaces
        assert(#word<=columns,'word wider than label: '..word)
        if used+gap+#word>columns then lines=lines+1; used=0; gap=0 end
        used=used+gap+#word
      end
    end
    return {x=o.x,y=o.y,w=width,h=math.max(o.h or 0,lines*o.size_value),text=o.text_value}
  end
  for _,config in ipairs({{}, {needsx=true,store={best=2000000000,day=20000,today=2000000000}}, {time=false}}) do
    local h=ready(config)
    assert(h:find('SOLANA').size_value==32 and h:find('SOLANA').color_value=='green')
    assert(h:find('DEFENDERS').size_value==32 and h:find('DEFENDERS').color_value=='purple')
    assert(h:has('by Range') and h:has('Top score each day wins !LAMPs'))
    assert(h:has('Tweet your score and tag @range_org') and h:has('BEST'))
    assert(h:has('Link X to earn !LAMPs')==(config.needsx==true))
    for i,name in ipairs(names) do
      local sprite,label=h.state[60][13+i],h.state[60][18+i]
      assert(sprite.text_value==({'/oo\\','\\oo/','|<>|','[=o]','<oo>'})[i] and sprite.color_value==colors[i])
      assert(label.text_value:find(name,1,true) and label.color_value==colors[i])
      assert(label.text_value:match(i==5 and '%?%?%? pts$' or (5-i)*10 ..' pts$'))
      assert(sprite.y==84+(i-1)*18 and label.y==sprite.y)
      assert(36+#label.text_value*5.5<166,'table overlaps prize copy')
    end
    local stars,boxes=0,{}
    for _,o in ipairs(h.objects) do if o.visible and not o.removed then
      if o.kind=='label' then
        local b=box(o)
        assert(b.x>=0 and b.y>=0 and b.y+b.h<=218,'title text outside screen: '..b.text)
        assert(o==h.hint or b.y+b.h<=202,'title overlaps hint: '..b.text)
        assert(b.x+b.w<=320,'title outside width')
        for _,a in ipairs(boxes) do
          assert(b.x>=a.x+a.w or a.x>=b.x+b.w or b.y>=a.y+a.h or a.y>=b.y+b.h,
            'title labels overlap: '..a.text..' / '..b.text)
        end
        boxes[#boxes+1]=b
      elseif o.kind=='rect' and o.color_value=='dim' then
        assert(o.w==2 and o.h==2); stars=stars+1
      end
    end end
    assert(stars==8)
  end
end)
scenario('look_row_labels_hits',function()
  local h=ready(); play(h)
  local s=h.state
  local allocated=#h.objects
  assert(h:has('SCORE 00000'))
  -- Each alien is its own label at the hit-grid origin (the badge font is
  -- proportional, so sprites cannot share a label). Test both visible lines,
  -- both horizontal edges, and misses just outside the 22 x 24 bounds.
  local cases={{-3,0,false},{22,0,false},{0,-7,false},{0,24,false},{0,0,true},{21,18,true},{-2,0,true}}
  for r=1,4 do for c=0,5 do for _,case in ipairs(cases) do
    local mask=63<<((r-1)*6)
    local bit=1<<((r-1)*6+c)
    local idx=(r-1)*6+c+1
    h:invoke(function()
      s[24]=100.25; s[25]=32; s[19]=1; s[32]=mask; s[1]=6; s[49]=0
      s[22]=1000; s[55]=1000; s[6]=1000; s[8]=0
      for i=1,8 do s[13][i]=0 end
      s[39](s,'draw')
    end)
    local o=s[60][59+idx]
    assert(o.size_value==12 and o.visible and o.text_value==s[61][r*2-1]..'\n'..s[61][r*2])
    assert(o.color_value==({0xFF4040,'orange','yellow','pink'})[r])
    h:invoke(function()
      -- This fixture moves one rendered pixel during the tick.
      s[12][1]=101+c*33+case[1]
      s[13][1]=o.y+case[2]+11
    end)
    h:tick()
    assert(case[3] or o.x==101+c*33,'unexpected fixture position')
    assert(s[32]==(case[3] and mask & ~bit or mask),'glyph hit bounds at '..r..','..c..' offset '..case[1]..','..case[2])
    assert(s[49]==(case[3] and (5-r)*10 or 0),'hit points changed')
    for i=1,24 do
      local alive=s[32] & (1<<(i-1))~=0
      assert(s[60][59+i].visible==alive,'wrong sprite hidden at '..r..','..c)
    end
    if case[3] then assert(s[60][46].color_value==s[63][r] and s[60][46].y==22) end
    assert(#h.objects==allocated,'alien updates allocated widgets')
  end end end
  assert(h:find('/^\\').color_value=='purple' and h:has('screened by range.org'))
  assert(h:has('SCORE 00010') and h:has('WAVE 1') and h:has('/^\\/^\\/^\\'))
  local vis={}; for i=1,24 do vis[i]=s[60][59+i].visible end
  h:key('back'); h:key('select')
  for i=1,24 do assert(s[60][59+i].visible==vis[i],'resume restored a dead sprite') end
end)
scenario('look_shield_erodes',function()
  local h=ready(); play(h)
  local s=h.state
  local allocated=#h.objects
  for j=1,3 do
    local function visible()
      local n=0
      for k=15+j*3,17+j*3 do
        local o=s[60][k]
        assert(o.kind=='rect' and o.color_value=='green')
        if o.visible then n=n+1 end
      end
      return n
    end
    assert(visible()==3)
    for hp=2,0,-1 do
      h:invoke(function()
        s[55]=1000
        s[12][6]=j*80; s[13][6]=170; s[5][1]='WALLET DRAINER'
      end)
      h:tick()
      assert(s[27][j]==hp and s[13][6]==0 and s[31]==3,'shield hit behavior changed')
      assert(visible()==hp,'shield did not erode at HP '..hp)
      assert(#h.objects==allocated,'erosion allocated widgets')
    end
  end
  h:key('back'); h:key('select')
  for k=18,26 do assert(not s[60][k].visible,'resume restored a shield') end
end)
scenario('look_gameover_code',function()
  local vectors=assert(json.decode(read('tests/defenders/code-vectors.json')))
  local h=ready({tweet_id='1234567890123456789'})
  for _,v in ipairs(vectors) do
    h.time=v.day and v.day*86400 or nil
    finish(h,v.score,v.wave)
    local q=assert(qr(h))
    local code=assert(h:find(v.code),'score code missing')
    assert(h:find('CODE') and code.text_value==q.text_value:sub(-6))
    assert(code.size_value==20 and code.mono and code.x+code.w<=q.x and code.y+20<202)
    assert(q.x==118 and q.y==0 and q.w==202 and q.h==202)
    assert(h.hint.text_value=='Photo this screen, scan to post')
    h:key('right'); assert(h:find(v.code),'repost changed the score code')
    h:key('right'); assert(qr(h).text_value==q.text_value and h:find(v.code))
    h.time=h.time and h.time+86400 or 20000*86400; h:tick()
    assert(h:find(v.code),'day rollover changed the displayed code')
  end
  local noqr=ready({noqr=true}); finish(noqr,1230)
  assert(noqr:find(noqr.state[53]:sub(-6)) and noqr:has('CODE'))
end)
scenario('look_transition_compile_lifetime',function()
  local function compilation(h)
    for i=#h.compile_events,1,-1 do
      local e=h.compile_events[i]
      if e.path=='lib/play.lua' then return e end
    end
    error('play was not compiled')
  end
  -- Reproduce the unsafe overlap without relying on a named Lua reference to
  -- the previous chunk. Both its code and the title's widgets must be recorded.
  local unsafe=ready()
  unsafe:invoke(function()
    assert(unsafe.env.fs.load('lib/menu.lua'))
    assert(unsafe.env.fs.load('lib/play.lua'))
  end)
  local overlap=compilation(unsafe)
  assert(overlap.previous['lib/menu.lua']>0 and overlap.phase_widgets>0,'compile overlap was invisible')
  local h=ready({needsx=true})
  local function start()
    local title={}
    for i=14,83 do if h.state[60][i] then title[#title+1]=h.state[60][i] end end
    local menu_loads=h.loads['lib/menu.lua']
    h:key('select')
    local e=compilation(h)
    assert(h.loads['lib/menu.lua']==menu_loads,'input recompiled title art')
    assert(e.phase_widgets==0 and e.live==10,'phase widgets survived into play compilation')
    assert(not e.previous['lib/menu.lua'],'title code compiled in the play callback')
    assert(h.resident['@apps/defenders/lib/play.lua'] and not h.resident['@apps/defenders/lib/menu.lua'])
    for _,o in ipairs(title) do assert(o.removed,'previous phase widget survived') end
    for i=14,83 do assert(h.state[60][i]==nil,'play widgets built in compiler callback') end
    -- Keys arriving before the first tick still work without a ship widget.
    h:key('right'); assert(h.state[42]==155)
    h:key('left'); assert(h.state[42]==147)
    h:tick()
    assert(h:find('/^\\') and h.state[60][60].x==83 and h.state[49]==0 and h.state[1]==24)
    for i=14,83 do local o=h.state[60][i]
      if o then assert(o.created_callback>e.callback,'widget creation overlapped compilation') end
    end
    assert(h.state[24]>83 and h.state[24]<84 and h.state[13][1]==171 and h.state[22]==5,
      'deferred widgets changed the first gameplay tick')
    for i=2,8 do assert(h.state[13][i]==0,'unexpected shot on first tick') end
  end
  start()
  h:key('back'); h:key('back'); h:key('right'); h:key('back'); start()
  finish(h,1230); start()
  local early=ready(); early:key('select'); early:key('back')
  assert(early:has('Paused')); early:key('select')
  assert(early:find('/^\\') and early.loads['lib/play.lua']==1,'early pause lost play')
end)
local target=arg[1] or 'all'
if target~='all' then assert(scenarios[target],'unknown scenario: '..target); order={target} end
local passed,worst,max_live=0,0,0
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
  max_live=math.max(max_live,live)
  print(string.format('%s %s | max instructions/callback=%d | max live UI=%d | peak heap estimate=%d bytes | peak code+heap=%d bytes | max live UI in play=%d',
    ok and 'PASS' or 'FAIL',name,instructions,live,heap,total,play_live))
  if ok then passed=passed+1 else print(tostring(err)) end
end
local paths={}; for path in pairs(proxies) do paths[#paths+1]=path end; table.sort(paths)
for _,path in ipairs(paths) do print(string.format('CODE %s proxy=%d bytes',path:sub(2),proxies[path])) end
print(string.format('worst peak code+heap=%d bytes (limit 21500)',worst))
print(string.format('%d/%d PASS',passed,#order))
-- 24 per-alien labels cost about 1 KB of proxy; the emulator stays under its cap.
assert(worst<=21500,'visual refresh exceeds code+heap budget')
assert(max_live<=60,'visual refresh exceeds live widget budget')
if passed~=#order then os.exit(1) end
