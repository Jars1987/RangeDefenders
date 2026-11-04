-- Small test-only JSON codec. No host eval or Lua serialization shortcuts.
local M={}
local escapes={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
local function quote(s)
  return '"'..s:gsub('[%z\1-\31\\"]',function(c) return escapes[c] or string.format('\\u%04x',c:byte()) end)..'"'
end
function M.encode(v)
  local t=type(v)
  if v==nil then return 'null' end
  if t=='string' then return quote(v) end
  if t=='boolean' or t=='number' then return tostring(v) end
  assert(t=='table','JSON type '..t)
  local out={}
  if #v>0 then
    for i=1,#v do out[i]=M.encode(v[i]) end
    return '['..table.concat(out,',')..']'
  end
  for k,x in pairs(v) do out[#out+1]=quote(k)..':'..M.encode(x) end
  return '{'..table.concat(out,',')..'}'
end
function M.decode(text)
  local pos=1
  local parse
  local function ws() local _,last=text:find('^%s*',pos); pos=(last or pos-1)+1 end
  local function str()
    assert(text:sub(pos,pos)=='"','expected string'); pos=pos+1
    local out={}
    while pos<=#text do
      local c=text:sub(pos,pos); pos=pos+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        c=text:sub(pos,pos); pos=pos+1
        local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if c=='u' then
          local n=tonumber(text:sub(pos,pos+3),16); assert(n,'unicode'); pos=pos+4
          c=utf8.char(n)
        else c=assert(map[c],'escape') end
      end
      out[#out+1]=c
    end
    error('unterminated string')
  end
  parse=function()
    ws(); local c=text:sub(pos,pos)
    if c=='"' then return str() end
    if c=='{' or c=='[' then
      pos=pos+1; ws(); local out={}; local object=c=='{'; local close=object and '}' or ']'
      if text:sub(pos,pos)==close then pos=pos+1; return out end
      repeat
        local key
        if object then key=str(); ws(); assert(text:sub(pos,pos)==':','colon'); pos=pos+1 end
        local value=parse()
        if object then out[key]=value else out[#out+1]=value end
        ws(); c=text:sub(pos,pos); pos=pos+1
        if c==close then return out end
        assert(c==',','comma'); ws()
      until false
    end
    for _,v in ipairs({{'true',true},{'false',false},{'null',nil}}) do
      if text:sub(pos,pos+#v[1]-1)==v[1] then pos=pos+#v[1]; return v[2] end
    end
    local n=text:match('^-?%d+%.?%d*[eE]?[+-]?%d*',pos)
    assert(n and tonumber(n),'number'); pos=pos+#n; return tonumber(n)
  end
  local ok,value=pcall(function() local v=parse(); ws(); assert(pos>#text,'trailing JSON'); return v end)
  if ok then return value end
  return nil,tostring(value)
end
return M
