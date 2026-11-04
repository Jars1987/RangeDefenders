local json=dofile('tools/bp26/json.lua')
local Stub={} Stub.__index=Stub
local function ascii(s) assert(type(s)=='string' and not s:find('[^ -~]'),'non-ASCII UI') assert(#s<=200,'label too long') return s end
function Stub.new(id,bus)
  local self=setmetatable({id=id,bus=bus,clock=0,objects={},live=0,max_ui=0,max_instructions=0,max_heap=0,queue={},sends={},storage={},text={},online=true,seed=(tonumber(id:match('%d+')) or 0)+1,awards=0},Stub)
  local env={} for _,k in ipairs({'assert','error','ipairs','next','pairs','pcall','select','tonumber','tostring','type','xpcall','print','getmetatable','setmetatable','rawequal','rawget','rawlen','rawset','_VERSION'}) do env[k]=_G[k] end
  for _,k in ipairs({'string','table','math','utf8','coroutine'}) do env[k]={} for n,v in pairs(_G[k]) do env[k][n]=v end end
  env._G=env
  env.math.random=function(lo,hi) self.seed=(self.seed*48271)%2147483647 local n=self.seed/2147483647 if not lo then return n end if not hi then hi=lo lo=1 end return lo+math.floor(n*(hi-lo+1)) end
  env.collectgarbage=function(k)assert(k=='count')return collectgarbage('count')end
  local function create(kind,text)
    self.live=self.live+1 assert(self.live<=64,'UI limit exceeded') self.max_ui=math.max(self.max_ui,self.live)
    if kind=='qr' then assert(not self.qr,'only one QR') self.qr=true end
    local w={kind=kind,value=text,visible=true}
    self.objects[#self.objects+1]=w
    function w:text(s) if kind~='qr' then ascii(s) else assert(type(s)=='string' and #s<=256) end self.value=s end
    function w:show(b) self.visible=b end
    function w:pos()end function w:color()end function w:size()end function w:set(v)self.value=v end
    function w:remove() if self.removed then return end self.removed=true self.visible=false self._owner.live=self._owner.live-1 if kind=='qr' then self._owner.qr=nil end end
    w._owner=self
    return w
  end
  env.ui={W=320,H=218,bg=function()end,label=function(x,y,t,o)ascii(t)return create('label',t)end,
    rect=function()return create('rect')end,bar=function()return create('bar')end,
    qr=function(x,y,size,t)assert(#t<=256)return create('qr',t)end,
    hint=function(s)self.hint=ascii(s)end,toast=function(s)self.toast=ascii(s)end,
    confirm=function(s,cb)ascii(s)self:later(function()cb(true)end)end}
  env.led={count=8,fill=function(r,g,b)self.led={r,g,b}end,off=function()self.led={0,0,0}end}
  env.sys={millis=function()return self.clock end,time=function()return nil end,exit=function()self.closed=true end}
  env.badge={id=function()return id end,owner=function()return '@'..id end,online=function()return self.online end}
  env.storage={get=function(k)return self.storage[k]end,set=function(k,v)self.storage[k]=v end,remove=function(k)self.storage[k]=nil end}
  env.json=json
  env.profile={me=function(cb)self:later(function()cb(true,{name='@'..id,x='@'..id})end)end}
  env.lamps={award=function(amount,reason,cb)self.awards=self.awards+amount self:later(function()cb(true,self.needsX and {awarded=0,needsX=true} or {awarded=amount})end)end}
  env.mesh={nearby=function()return bus:nearby(id)end,send=function(to,msg)
    local wire=json.encode(msg) assert(#wire<=200,'mesh payload exceeded')
    local recent={} for _,at in ipairs(self.sends)do if self.clock-at<1000 then recent[#recent+1]=at end end assert(#recent<4,'mesh rate exceeded')
    recent[#recent+1]=self.clock self.sends=recent bus:send(id,to,msg)
  end}
  env.http={post=function(url,body,cb)
    assert(#json.encode(body)<=2048,'HTTP request too large')
    self:later(function()
      if not self.online then cb(false,'offline') return end
      local r=bus:http(id,url,body)
      cb(true,{status=r.status,body=json.encode(r.body),truncated=r.truncated or false})
    end)
  end}
  self.env=env self.memory_base=collectgarbage('count')
  local chunk=assert(loadfile('apps/lazarus/main.lua','t',env))
  self.chunk=chunk
  collectgarbage('collect')
  self.flash_base=collectgarbage('count')
  self:call(chunk)
  return self
end
function Stub:later(fn)self.queue[#self.queue+1]=fn end
function Stub:call(fn,...)
  if not fn then return end
  local count=0
  if self.heap_mode then collectgarbage('collect') end
  debug.sethook(function()
    count=count+1000 assert(count<200000,'callback instruction limit')
    if self.heap_mode and debug.getinfo(2,'S').source=='@apps/lazarus/main.lua' then
      -- Native OS APIs do not allocate this Lua fixture codec's scratch tables.
      collectgarbage('collect')
      self.max_heap=math.max(self.max_heap,collectgarbage('count')-self.flash_base)
    end
  end,'',1000)
  local ok,err=pcall(fn,...)
  debug.sethook()
  self.max_instructions=math.max(self.max_instructions,count+1000)
  assert(ok,err)
  if self.heap_mode then
    collectgarbage('collect')
    self.max_heap=math.max(self.max_heap,collectgarbage('count')-self.flash_base)
  end
end
function Stub:flush()
  local queue=self.queue self.queue={}
  for _,fn in ipairs(queue)do self:call(fn)end
end
function Stub:tick(ms)self.clock=self.clock+ms self:flush() if not self.closed then self:call(self.env.on_tick,ms)end end
function Stub:key(k)self:call(self.env.on_key,k,false)self:flush()end
function Stub:screen()local out={}for _,w in ipairs(self.objects)do if w.visible and w.kind=='label' then out[#out+1]=w.value end end return table.concat(out,'\n')end
return Stub
