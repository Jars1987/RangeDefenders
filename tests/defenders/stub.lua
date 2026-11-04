-- BP26 subset used by Defenders. Host bookkeeping is excluded from app heap.
-- Heap is a conservative reachable-data estimate with 32-bit Lua value sizes,
-- Code uses measured Lua 5.4 load deltas, including source-compiled prototypes.
local json=dofile('tests/defenders/json.lua')
local M={}
local APP='@apps/defenders/main.lua'
local function app_source(source) return source:sub(1,16)=='@apps/defenders/' end
local function clone(t) local out={}; for k,v in pairs(t) do out[k]=v end; return out end
function M.new(config)
  config=config or {}
  local h={objects={},queue={},calls={},now=0,max_instructions=0,max_live=0,live=0,
    peak_heap=0,peak_total=0,max_live_play=0,loads={},proxies={},io_cost=0,module_cache={},store=config.store or {},awards={},writes={},exited=false,
    callback_id=0,callback_chunks={},compile_events={},
    time=config.time or 20000*86400,badge_id=config.badge_id}
  if config.time==false then h.time=nil end
  if config.badge_id==nil then h.badge_id="7K2Q9M" elseif config.badge_id==false then h.badge_id=nil end
  local env={}
  h.env=env
  local views={}
  local methods={}
  function methods:text(s)
    assert(self.kind=='label' or self.kind=='qr','unsupported text method')
    assert(type(s)=='string' and #s<=(self.kind=='label' and 200 or 256),'text limit')
    assert(not s:find('[^\n -~]'),'non-ASCII UI: '..s)
    self.text_value=s
  end
  function methods:pos(x,y) self.x=x; self.y=y end
  function methods:show(b) self.visible=b end
  function methods:color(c) self.color_value=c end
  function methods:size(w,hh) assert(self.kind=='rect'); self.w=w; self.h=hh end
  function methods:remove()
    assert(not self.removed,'double remove'); self.removed=true; self.visible=false
    h.live=h.live-1
  end
  local function object(kind,x,y,w,hh,text,opts)
    h.live=h.live+1; h.max_live=math.max(h.max_live,h.live)
    assert(h.live<=64,'more than 64 UI objects')
    if kind=='qr' then
      assert(w>=25 and w<=218 and x>=0 and y>=0 and x+w<=320 and y+w<=202,'QR outside available screen')
      for _,o in ipairs(h.objects) do assert(o.kind~='qr' or o.removed,'two QR objects') end
    end
    local o=setmetatable({kind=kind,x=x,y=y,w=w,h=hh,visible=true,
      color_value=opts and opts.color,size_value=opts and opts.size or 12,
      mono=opts and opts.mono,align=opts and opts.align,created_callback=h.callback_id}, {__index=methods})
    views[o]=true; h.objects[#h.objects+1]=o
    if text then o:text(text) end
    return o
  end
  env.ui={W=320,H=218,bg=function(c) h.bg=c end,
    label=function(x,y,s,o) return object('label',x,y,o and o.w,nil,s,o) end,
    rect=function(x,y,w,hh,o) return object('rect',x,y,w,hh,nil,o) end,
    hint=function(s)
      if not h.hint then h.hint=object('label',0,202,320,16,s) else h.hint:text(s) end
    end,
    toast=function(s)
      local o=object('label',0,180,320,16,s); o:remove(); h.last_toast=s
    end}
  if not config.noqr then env.ui.qr=function(x,y,n,s) return object('qr',x,y,n,n,s) end end
  env.led={fill=function(r,g,b) h.led={r,g,b} end,off=function() h.led={0,0,0} end}
  env.storage={get=function(k) return h.store[k] end,
    set=function(k,v) h.store[k]=assert(json.decode(json.encode(v))); h.writes[#h.writes+1]={k,v} end,
    remove=function(k) h.store[k]=nil end}
  env.sys={millis=function() return h.now end,time=function() return h.time end,exit=function() h.exited=true end}
  env.badge={id=function() return h.badge_id end}
  env.json=json
  local function enqueue(fn,delay) h.queue[#h.queue+1]={at=h.now+(delay or 50),fn=fn} end
  env.timer={after=function(ms,fn) enqueue(fn,ms); return #h.queue end,
    cancel=function(i) if h.queue[i] then h.queue[i].cancelled=true end end}
  env.lamps={award=function(amount,reason,cb)
    assert(amount==25 and reason=='Welcome to Solana Defenders')
    h.awards[#h.awards+1]=amount
    enqueue(function()
      if config.award_denied then cb(false,'denied')
      elseif config.award_timeout then cb(false,'timeout')
      elseif config.award_result then cb(true,config.award_result)
      else cb(true,{awarded=config.needsx and 0 or config.capzero and 0 or amount,needsX=config.needsx or false}) end
    end,config.award_delay)
  end}
  for _,k in ipairs({'assert','error','ipairs','next','pairs','pcall','select','tonumber','tostring','type','xpcall'}) do env[k]=_G[k] end
  env.math=clone(math); env.string=clone(string); env.table=clone(table)
  env._G=env
  env.collectgarbage=function(what)
    assert(what=='count','Solana OS does not expose manual GC')
    local heap,code=h:heap(); return (heap+code)/1024
  end
  local excluded={[_G]=true,[h]=true,[config]=true,[json]=true}
  for _,t in pairs(env) do if type(t)=='table' then excluded[t]=true end end
  -- Account app globals via their callback roots, not the host environment.
  function h:heap()
    local seen,upvalues,sources,bytes={},{},{},0
    local scan
    scan=function(v)
      local t=type(v)
      if (t~='table' and t~='function' and t~='string') or seen[v] then return end
      seen[v]=true
      if views[v] then bytes=bytes+16; return end
      if excluded[v] then return end
      if t=='string' then bytes=bytes+20+4*math.ceil(#v/4)
      elseif t=='table' then
        if v[57] and v[60] and v[12] then self.state=v end
        bytes=bytes+48
        local array,hash=0,0
        for k,x in pairs(v) do
          if type(k)=='number' and k>=1 and k%1==0 and k<=#v then array=array+1 else hash=hash+1 end
          scan(k); scan(x)
        end
        local array_capacity,hash_capacity=0,0
        if array>0 then array_capacity=1; while array_capacity<array do array_capacity=array_capacity*2 end end
        if hash>0 then hash_capacity=1; while hash_capacity<hash do hash_capacity=hash_capacity*2 end end
        bytes=bytes+array_capacity*8+hash_capacity*24
      else
        local info=debug.getinfo(v,'S')
        if not app_source(info.source) then return end
        sources[info.source]=true
        bytes=bytes+32
        local i=1
        while true do
          local name,x=debug.getupvalue(v,i); if not name then break end
          bytes=bytes+4
          local id=debug.upvalueid(v,i)
          if not upvalues[id] then upvalues[id]=true; bytes=bytes+20 end
          scan(x); i=i+1
        end
      end
    end
    for _,k in ipairs({'on_tick','on_key','on_mesh','on_exit'}) do scan(env[k]) end
    scan(self.loading)
    for _,value in pairs(self.module_cache) do scan(value) end
    for _,q in ipairs(h.queue) do
      -- Host wrappers enclose badge callbacks, which must count as live closures.
      local i=1
      while true do local name,x=debug.getupvalue(q.fn,i); if not name then break end; scan(x); i=i+1 end
    end
    -- Count temporary app locals too when called from the instruction hook.
    local level=2
    while true do
      local info=debug.getinfo(level,'Sf')
      if not info then break end
      if app_source(info.source) then
        scan(info.func)
        local i=1
        while true do
          local name,x=debug.getlocal(level,i); if not name then break end
          -- Unnamed VM registers can contain stale host instrumentation. They
          -- are not Lua locals. Named values and callback closures are roots.
          if name:sub(1,1)~='(' then scan(x) end
          i=i+1
        end
      end
      level=level+1
    end
    local code=0
    for source in pairs(sources) do code=code+assert(self.proxies[source],source..' has no measured proxy') end
    self.resident=sources
    return bytes,code
  end
  function h:sample()
    local heap,code=self:heap()
    if self.state and self.state[57]=="play" then self.max_live_play=math.max(self.max_live_play,self.live) end
    self.peak_heap=math.max(self.peak_heap,heap)
    self.peak_total=math.max(self.peak_total,heap+code)
    assert(heap<=48*1024,'estimated heap exceeds 48 KB: '..heap)
    assert(heap+code<=24*1024,'peak code+heap exceeds 24 KB: '..(heap+code)..' (code '..code..', data '..heap..')')
  end
  function h:load_chunk(path)
    -- Compilation is a C operation on badge. Do not charge host instrumentation
    -- as app instructions. Do charge the documented file-open/compile cost.
    self.loads[path]=(self.loads[path] or 0)+1
    local hook,mask,count=debug.gethook(); debug.sethook()
    local f=assert(io.open('apps/defenders/'..path)); local source=f:read('*a'); f:close()
    assert(#source<=(path=='main.lua' and 65536 or 262144),'file size limit')
    assert(not source:find('[\128-\255]'),'source must be ASCII')
    if path=='main.lua' and config.tweet_id then
      source=source:gsub('local LAUNCH_TWEET_ID = "[^"]*"',function()
        return 'local LAUNCH_TWEET_ID = "'..config.tweet_id..'"'
      end,1)
    end
    collectgarbage('collect')
    local baseline=collectgarbage('count')
    local name='@apps/defenders/'..path
    local chunk=assert(load(source,name,'t',env))
    collectgarbage('collect')
    self.proxies[name]=math.max(self.proxies[name] or 0,math.ceil((collectgarbage('count')-baseline)*1024))
    -- Remember code compiled earlier in this callback, even if it is no longer
    -- reachable. Together with phase widget references this exposes overlap
    -- hidden by the retained-heap proxy. It is not a native allocator model.
    local event={path=path,callback=self.callback_id,previous=clone(self.callback_chunks),phase_widgets=0,live=self.live}
    if self.state then for i=14,83 do
      if self.state[60][i] then event.phase_widgets=event.phase_widgets+1 end
    end end
    self.compile_events[#self.compile_events+1]=event
    self.callback_chunks[path]=self.proxies[name]
    self.loading=chunk; self:sample(); self.loading=nil
    self.io_cost=self.io_cost+500+math.ceil(#source/4)
    debug.sethook(hook,mask,count)
    return chunk
  end
  env.fs={load=function(path)
    assert(path:match('^lib/[a-z0-9_-]+%.lua$'),'invalid bundled path')
    return h:load_chunk(path)
  end}
  excluded[env.fs]=true
  env.require=function(name)
    if not h.module_cache[name] then h.module_cache[name]=h:load_chunk(name:gsub('%.','/')..'.lua')() end
    return h.module_cache[name]
  end
  function h:invoke(fn,...)
    local count=0
    self.io_cost=0
    self.callback_id=self.callback_id+1; self.callback_chunks={}
    debug.sethook(function()
      count=count+1000
      assert(count+self.io_cost<200000,'callback exceeds 200,000 VM instructions')
      self:sample()
    end,'',1000)
    local result=table.pack(pcall(fn,...))
    debug.sethook()
    self.max_instructions=math.max(self.max_instructions,count+999+self.io_cost)
    self:sample()
    assert(result[1],result[2])
    return table.unpack(result,2,result.n)
  end
  function h:tick(n)
    for _=1,n or 1 do
      self.now=self.now+50
      self:invoke(env.on_tick,50)
      local due={}
      for i=#self.queue,1,-1 do
        local v=self.queue[i]
        if v.at<=self.now then table.remove(self.queue,i); if not v.cancelled then due[#due+1]=v.fn end end
      end
      for i=#due,1,-1 do self:invoke(due[i]) end
    end
  end
  function h:key(k,rep) return self:invoke(env.on_key,k,rep or false) end
  function h:has(text)
    for _,o in ipairs(self.objects) do
      if o.visible and not o.removed and o.text_value and o.text_value:find(text,1,true) then return true end
    end
    return false
  end
  function h:find(text)
    for _,o in ipairs(self.objects) do if o.text_value==text and o.visible and not o.removed then return o end end
  end
  function h:requests(path)
    local out={}; for _,c in ipairs(self.calls) do if c.path==path then out[#out+1]=c end end; return out
  end
  math.randomseed(config.seed or 26)
  h:invoke(h:load_chunk('main.lua'))
  return h
end
return M
