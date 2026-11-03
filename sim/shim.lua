-- Browser host implementation of the documented BP26 subset.
local callbacks, sequence, widgets = {}, 0, {}
local function later(cb,kind,payload)
  sequence=sequence+1 callbacks[sequence]=cb
  host_call(sequence,kind,json.encode(payload or {}))
end
function sim_reply(id,ok,body,status)
  local cb=callbacks[id] callbacks[id]=nil
  if cb then
    if status then cb(ok,{status=status,body=body,truncated=false})
    else cb(ok,json.decode(body)) end
  end
end
local function widget(kind,x,y,w,h,text,opts)
  local id=host_create(kind,x,y,w,h,text or '',json.encode(opts or {}))
  local obj={id=id}
  function obj:text(v)host_change(id,'text',tostring(v))end
  function obj:show(v)host_change(id,'show',v and '1' or '0')end
  function obj:pos(a,b)host_change(id,'x',tostring(a))host_change(id,'y',tostring(b))end
  function obj:remove()host_change(id,'remove','')end
  function obj:color(v)host_change(id,'color',tostring(v))end
  function obj:set(v)host_change(id,'value',tostring(v))end
  function obj:size(w,h)host_change(id,'w',tostring(w))host_change(id,'h',tostring(h))end
  return obj
end
ui={W=320,H=218,bg=function(c)end,
 label=function(x,y,t,o)return widget('label',x,y,o and o.w or 300,20,t,o)end,
 rect=function(x,y,w,h,o)return widget('rect',x,y,w,h,'',o)end,
 bar=function(x,y,w,h,v)return widget('bar',x,y,w,h,tostring(v))end,
 qr=function(x,y,w,t)return widget('qr',x,y,w,w,t)end,
 hint=function(s)host_hint(s)end,toast=function(s)host_toast(s)end,
 confirm=function(s,cb)later(cb,'confirm',{text=s})end}
led={count=8,fill=function(r,g,b)host_led(r,g,b)end,off=function()host_led(0,0,0)end}
sys={millis=function()return host_millis()end,exit=function()host_exit()end}
badge={id=function()return host_id()end,owner=function()return '@you'end,online=function()return true end}
profile={me=function(cb)later(cb,'profile')end}
lamps={award=function(n,reason,cb)later(cb,'award',{amount=n})end}
storage={get=function(k)return host_storage('get',k,'')end,set=function(k,v)host_storage('set',k,tostring(v))end,remove=function(k)host_storage('remove',k,'')end}
mesh={nearby=function()return json.decode(host_nearby())end,send=function(to,msg)host_mesh(json.encode(msg))end}
http={post=function(url,body,cb)later(cb,'http',{url=url,body=body})end}
