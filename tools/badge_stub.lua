-- Host-only SDK model. Numeric boundary guards do not emulate LUA_32BITS maths.
local M = {DT = 1 / 60}
local floor, min, max = math.floor, math.min, math.max
local function numbers(v, integer, where, seen)
  if type(v) == 'number' then
    assert(v == v and math.abs(v) < math.huge, where .. ': non-finite number')
    if integer or math.type(v) == 'integer' then
      assert(math.tointeger(v) and v >= -2147483648 and v <= 2147483647,
        where .. ': expected int32, got ' .. tostring(v))
    end
  elseif type(v) == 'table' then
    seen = seen or {}
    if seen[v] then return end
    seen[v] = true
    for k, x in pairs(v) do numbers(k, integer, where, seen); numbers(x, integer, where, seen) end
  end
end
M.numbers = numbers

function M.rng(seed)
  local x = seed % 2147483646 + 1
  return function(a, b)
    x = (x * 48271) % 2147483647
    local r = (x - 1) / 2147483646
    if not a then return r end
    if not b then b, a = a, 1 end
    assert(a <= b, 'empty random interval')
    return a + floor(r * (b - a + 1))
  end
end

-- A framebuffer represented by ordered opaque rectangles. Rasterise only on
-- export: this keeps 20 badges drawing every frame affordable on a host CPU.
local function framebuffer()
  local fb = {bg = 0, ops = {}}
  function fb:clear(c) self.bg, self.ops = c or 0, {} end
  function fb:rect(x, y, w, h, c)
    local x1, y1 = max(0, x), max(0, y)
    local x2, y2 = min(319, x + w - 1), min(239, y + h - 1)
    if x1 <= x2 and y1 <= y2 then self.ops[#self.ops+1] = {x1,y1,x2,y2,c or 65535} end
  end
  function fb:dump(path)
    local rows = {}
    local function grey(c)
      local r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
      return string.char(floor((r / 31 + g / 63 + b / 31) * 85 + .5))
    end
    local bg = grey(self.bg)
    for y = 0, 239 do rows[y] = string.rep(bg, 320) end
    for _, o in ipairs(self.ops) do
      local run = string.rep(grey(o[5]), o[3]-o[1]+1)
      for y = o[2], o[4] do
        rows[y] = rows[y]:sub(1, o[1]) .. run .. rows[y]:sub(o[3]+2)
      end
    end
    local f = assert(io.open(path, 'wb')); f:write('P5\n320 240\n255\n')
    for y = 0, 239 do f:write(rows[y]) end
    f:close()
  end
  return fb
end

function M.new(opts)
  opts = opts or {}
  local d = {mac=opts.mac or '02:00:00:00:00:01', frame=0, time=0,
    kv=opts.kv or {}, keys={}, pressed={}, released={}, held={}, texts={}, seen={},
    callbacks={}, sent={}, enabled=false, online=true, fb=framebuffer(), edges={},
    entropy=opts.entropy or {}, entropy_pos=0, max_ms=0, scheduled={}}
  local rand, entropy = M.rng(opts.seed or 1), M.rng((opts.seed or 1) + 7919)
  local badge = {version='0.1.0', api_version=1, device_name='test-' .. d.mac:sub(-5)}
  d.badge = badge
  local function bind(space, name, fn, integral)
    space[name] = function(...)
      for i = 1, select('#', ...) do numbers(select(i, ...), integral, name) end
      return fn(...)
    end
  end
  local g = {}; badge.gfx = g
  local colours = {BLACK=0, WHITE=65535, BG=2113, PANEL=4226, BORDER=12678,
    MUTED=33808, RED=63488, ORANGE=64768, YELLOW=65504, GREEN=2016,
    CYAN=2047, BLUE=31, SOLANA_PURPLE=38943, SOLANA_GREEN=6010,
    SOLANA_TEAL=2000, SOLANA_MAGENTA=63519}
  for k,v in pairs(colours) do g[k]=v end
  bind(g,'width',function() return 320 end)
  bind(g,'height',function() return 240 end)
  bind(g,'clear',function(c) d.fb:clear(c or g.BG) end,true)
  bind(g,'fill_rect',function(x,y,w,h,c) d.fb:rect(x,y,w,h,c) end,true)
  bind(g,'pixel',function(x,y,c) d.fb:rect(x,y,1,1,c) end,true)
  bind(g,'line',function(x,y,x2,y2,c)
    -- Clip extreme offscreen lines before stepping, avoiding host runaway loops.
    assert(math.abs(x2-x)+math.abs(y2-y) <= 10000, 'unbounded line')
    local dx,dy=math.abs(x2-x),math.abs(y2-y)
    local sx,sy=x<x2 and 1 or -1,y<y2 and 1 or -1
    local e=dx-dy
    while true do
      d.fb:rect(x,y,1,1,c)
      if x==x2 and y==y2 then break end
      local e2=2*e
      if e2 > -dy then e=e-dy; x=x+sx end
      if e2 < dx then e=e+dx; y=y+sy end
    end
  end,true)
  bind(g,'rect',function(x,y,w,h,c)
    d.fb:rect(x,y,w,1,c); d.fb:rect(x,y+h-1,w,1,c)
    d.fb:rect(x,y,1,h,c); d.fb:rect(x+w-1,y,1,h,c)
  end,true)
  local function roundrect(fill,x,y,w,h,r,c)
    r=min(r or 4,w//2,h//2)
    for yy=max(0,y),min(239,y+h-1) do
      local dy=max(y+r-yy-1,yy-(y+h-r),0)
      local inset=r-floor(math.sqrt(max(0,r*r-dy*dy)))
      if fill or yy==y or yy==y+h-1 then d.fb:rect(x+inset,yy,w-2*inset,1,c)
      else d.fb:rect(x+inset,yy,1,1,c); d.fb:rect(x+w-inset-1,yy,1,1,c) end
    end
  end
  bind(g,'round_rect',function(...) roundrect(false,...) end,true)
  bind(g,'fill_round_rect',function(...) roundrect(true,...) end,true)
  local function circle(fill,x,y,r,c)
    for yy=max(-r,-y),min(r,239-y) do
      local dx=floor(math.sqrt(r*r-yy*yy))
      if fill then d.fb:rect(x-dx,y+yy,2*dx+1,1,c)
      else d.fb:rect(x-dx,y+yy,1,1,c); d.fb:rect(x+dx,y+yy,1,1,c) end
    end
  end
  bind(g,'circle',function(...) circle(false,...) end,true)
  bind(g,'fill_circle',function(...) circle(true,...) end,true)
  bind(g,'triangle',function(x,y,x2,y2,x3,y3,c)
    g.line(x,y,x2,y2,c); g.line(x2,y2,x3,y3,c); g.line(x3,y3,x,y,c)
  end,true)
  bind(g,'fill_triangle',function(x,y,x2,y2,x3,y3,c)
    for yy=max(0,min(y,y2,y3)),min(239,max(y,y2,y3)) do
      local xs={}
      for _, e in ipairs({{x,y,x2,y2},{x2,y2,x3,y3},{x3,y3,x,y}}) do
        if e[2]~=e[4] and yy>=min(e[2],e[4]) and yy<=max(e[2],e[4]) then
          xs[#xs+1]=e[1]+(yy-e[2])*(e[3]-e[1])/(e[4]-e[2])
        end
      end
      if #xs>=2 then local l,r=floor(min(table.unpack(xs))),floor(max(table.unpack(xs)))
        d.fb:rect(l,yy,r-l+1,1,c) end
    end
  end,true)
  bind(g,'text_width',function(s,size) return #tostring(s)*6*(size or 1) end,true)
  bind(g,'text_height',function(size) return 8*(size or 1) end,true)
  local function text(s,x,y,c,size,anchor)
    s=tostring(s); size=size or 1
    local w=g.text_width(s,size)
    if anchor=='center' then x=x-w//2 elseif anchor=='right' then x=x-w end
    local call={text=s,x=x,y=y,c=c or g.WHITE,size=size}
    d.texts[#d.texts+1]=call; d.seen[s]=true
    -- Text calls are captured exactly. A conservative 5x7 glyph mask reserves
    -- pixels; QR modules and quiet zones are rasterised exactly, font is not.
    for i=1,#s do if s:sub(i,i)~=' ' then d.fb:rect(x+(i-1)*6*size,y,5*size,7*size,c) end end
  end
  for name,anchor in pairs({text='left',text_center='center',text_right='right'}) do
    bind(g,name,function(s,x,y,c,size) text(s,x,y,c,size,anchor) end,true)
  end
  bind(g,'color',function(r,gg,b) return ((r & 248)<<8)|((gg & 252)<<3)|(b>>3) end,true)
  bind(g,'gradient',function(t) t=max(0,min(1,t)); return g.color(floor(153*(1-t)),floor(241*t),floor(255*(1-t)+149*t)) end)
  bind(g,'hsv',function(h,s,v)
    local function f(n) local k=(n+h/60)%6; return floor(255*v*(1-s*max(0,min(k,4-k,1)))+.5) end
    return g.color(f(5),f(3),f(1))
  end)
  bind(g,'brightness',function(v) d.brightness=v or d.brightness or 255; return d.brightness end,true)
  local input={}; badge.input=input
  for name,fn in pairs({down=function(k) return d.keys[k] or false end,
    pressed=function(k) return d.pressed[k] or false end,
    released=function(k) return d.released[k] or false end,
    repeated=function(k) return d.pressed[k] or (d.keys[k] and d.frame%8==0) or false end,
    held_ms=function(k) return d.keys[k] and floor((d.time-(d.held[k] or d.time))*1000+.0001) or 0 end,
    any=function() return next(d.keys)~=nil end, keys=function() return {'up','down','left','right','a','b'} end,
    label=function(k) return ({a='SELECT',b='CANCEL',up='UP',down='DOWN',left='LEFT',right='RIGHT'})[k] end,
    present=function() return true end}) do bind(input,name,fn) end
  badge.led={COUNT=2}
  for _,name in ipairs({'set','all','gradient','show','off','pulse','take'}) do bind(badge.led,name,function() end) end
  bind(badge.led,'brightness',function(v) return v or 255 end)
  badge.storage={kv={}}
  bind(badge.storage.kv,'get',function(k,default) assert(#k<=8); return d.kv[k] or default end)
  bind(badge.storage.kv,'set',function(k,v) assert(#k<=8 and type(v)=='string','kv expects <=8 char key and string value'); d.kv[k]=v end)
  bind(badge.storage.kv,'remove',function(k) d.kv[k]=nil end)
  badge.system={}
  bind(badge.system,'random_bytes',function(n)
    assert(n>=1 and n<=1024)
    if n==4 and d.entropy[d.entropy_pos+1] then
      d.entropy_pos=d.entropy_pos+1; return d.entropy[d.entropy_pos]
    end
    local bytes={}; for i=1,n do bytes[i]=string.char(entropy(0,255)) end; return table.concat(bytes)
  end)
  bind(badge.system,'millis',function() return floor(d.time*1000) end)
  bind(badge.system,'uptime',function() return d.time end)
  bind(badge.system,'exit',function() d.exited=true end)
  bind(badge.system,'name',function() return badge.device_name end)
  bind(badge,'log',function(...) d.log={...} end)
  badge.millis=badge.system.millis
  badge.wifi={}
  bind(badge.wifi,'mac',function() return d.mac end)
  bind(badge.wifi,'connected',function() return false end)
  bind(badge.wifi,'channel',function() return 6 end)
  bind(badge.wifi,'ssid',function() return '' end)
  badge.espnow={MAX_PAYLOAD=240, MAX_PEERS=20}
  bind(badge.espnow,'enable',function(v) d.enabled=v~=false; return true end)
  bind(badge.espnow,'enabled',function() return d.enabled end)
  bind(badge.espnow,'channel',function() return 6 end)
  bind(badge.espnow,'broadcast',function(data)
    assert(type(data)=='string' and #data<=240,'radio payload >240 bytes')
    d.sent[#d.sent+1]={frame=d.frame,time=d.time,data=data,mac=d.mac}
    if d.bus then d.bus:send(d,data) end
    return true
  end)
  bind(badge.espnow,'peers',function()
    local peers={}
    if d.bus then for _,p in ipairs(d.bus.devices) do if p~=d and p.online then
      peers[#peers+1]={mac=p.mac,name=p.badge.device_name,rssi=d.bus:rssi(d,p),age_ms=0,packets=1}
    end end end
    table.sort(peers,function(a,b) return a.rssi>b.rssi or (a.rssi==b.rssi and a.mac<b.mac) end)
    return peers
  end)
  bind(badge.espnow,'signal',function(mac)
    for _,p in ipairs(badge.espnow.peers()) do if p.mac==mac then return p.rssi,0 end end
  end)
  for _,name in ipairs({'beacon','clear'}) do bind(badge.espnow,name,function() return true end) end
  local env={badge=badge,assert=assert,error=error,ipairs=ipairs,pairs=pairs,next=next,
    pcall=pcall,xpcall=xpcall,select=select,tonumber=tonumber,tostring=tostring,type=type,
    rawequal=rawequal,rawget=rawget,rawset=rawset,setmetatable=setmetatable,getmetatable=getmetatable,
    _VERSION=_VERSION,
    os={clock=function() return d.time end,time=function() return floor(d.time) end,
      date=function(format,ts) return os.date(format,ts or floor(d.time)) end,difftime=os.difftime}}
  for name,library in pairs({table=table,string=string,utf8=utf8,coroutine=coroutine}) do
    env[name]={}; for k,v in pairs(library) do env[name][k]=v end
  end
  env.string.dump=nil
  env.math={}; for k,v in pairs(math) do env.math[k]=v end
  env.math.random=function(...) return rand(...) end
  env.math.randomseed=function(s) rand=M.rng(s); return s,0 end
  env.print=badge.log; env._G=env; d.env=env
  function d:call(name,...)
    local fn=self.env[name]; if not fn then return end
    local start=os.clock()
    local ticks=0
    debug.sethook(function() ticks=ticks+1; assert(ticks<=1000,'callback instruction budget exceeded') end,'',10000)
    local out=table.pack(pcall(fn,...))
    debug.sethook()
    local ms=(os.clock()-start)*1000
    self.max_ms=max(self.max_ms,ms); self.callbacks[name]=max(self.callbacks[name] or 0,ms)
    if not out[1] then error(self.mac..' '..name..' frame '..self.frame..': '..tostring(out[2]),0) end
    return table.unpack(out,2,out.n)
  end
  function d:load(source,path)
    assert(load(source,'@'..(path or 'game'),'t',self.env))()
    self:call('on_start'); self:draw()
    assert(type(self.env.__state)=='function','game must implement __state()')
    return self
  end
  function d:state() return self:call('__state') end
  function d:edge(key,down)
    assert(input.label(key),'unknown key '..tostring(key))
    self.edges[#self.edges+1]={key=key,down=down}
  end
  function d:schedule(edges)
    for _,e in ipairs(edges) do
      assert(math.type(e.frame)=='integer' and e.frame>self.frame,'input edge must be in a future frame')
      self.scheduled[#self.scheduled+1]={frame=e.frame,key=e.key,down=e.down}
    end
  end
  function d:draw() self.texts={}; self:call('on_draw') end
  function d:tick(frame)
    self.frame=frame or self.frame+1; self.time=self.frame*M.DT
    self.pressed,self.released={},{}
    local future={}
    for _,e in ipairs(self.scheduled) do
      if e.frame==self.frame then self:edge(e.key,e.down) else future[#future+1]=e end
    end
    self.scheduled=future
    for _,e in ipairs(self.edges) do
      if (self.keys[e.key] or false)~=e.down then
        if e.down then self.keys[e.key]=true; self.pressed[e.key]=true; self.held[e.key]=self.time
        else self.keys[e.key]=nil; self.released[e.key]=true; self.held[e.key]=nil end
        self:call('on_button',e.key,e.down)
      end
    end
    self.edges={}; self:call('on_update',M.DT); self:draw()
  end
  return d
end

function M.bus(opts)
  opts=opts or {}
  local b={devices={},frame=0,queue={},dropped=0,lost=0,duplicates=0,
    delivered=0,rand=M.rng(opts.seed or 991),opts=opts,history={}}
  function b:add(d) self.devices[#self.devices+1]=d; d.bus=self; return d end
  function b:rssi(a,c) return (self.opts.rssi and self.opts.rssi[a.mac] and self.opts.rssi[a.mac][c.mac]) or -55 end
  function b:inject(target,mac,data,rssi,delay)
    self.queue[#self.queue+1]={target=target,mac=mac,data=data,rssi=rssi or -55,due=self.frame+1+(delay or 0)}
  end
  function b:send(d,data)
    self.history[#self.history+1]={mac=d.mac,data=data,frame=self.frame}
    if not d.online then return end
    for _,p in ipairs(self.devices) do if p~=d and p.online then
      if self.rand()<(self.opts.loss or 0) then self.lost=self.lost+1
      else
        local delay=self.opts.reorder and self.rand(0,2) or 0
        self:inject(p,d.mac,data,self:rssi(d,p),delay)
        if self.rand()<(self.opts.dup or 0) then
          self:inject(p,d.mac,data,self:rssi(d,p),delay+1); self.duplicates=self.duplicates+1
        end
      end
    end end
  end
  function b:step(n,controller)
    for _=1,n or 1 do
      self.frame=self.frame+1
      if controller then controller(self,self.frame) end
      local due,future={},{}
      for _,p in ipairs(self.queue) do
        if p.due<=self.frame then due[#due+1]=p else future[#future+1]=p end
      end
      self.queue=future
      if self.opts.reorder then
        for i=#due,2,-1 do local j=self.rand(1,i); due[i],due[j]=due[j],due[i] end
      end
      local counts={}
      for _,p in ipairs(due) do
        local d=p.target
        counts[d]=(counts[d] or 0)+1
        if counts[d]>7 then self.dropped=self.dropped+1
        elseif d.online and d.enabled then
          d:call('on_espnow',p.mac,p.data,p.rssi); self.delivered=self.delivered+1
        end
      end
      for _,d in ipairs(self.devices) do d:tick(self.frame) end
    end
  end
  return b
end
return M
