-- Small fixture codec. The app uses the OS json module, never this host codec.
local J = {}
function J.encode(v)
  local t=type(v)
  if t=='nil' then return 'null' end
  if t=='boolean' or t=='number' then return tostring(v) end
  if t=='string' then return '"'..v:gsub('[%z\1-\31\\"]',function(c)
    local m={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
    return m[c] or string.format('\\u%04x',c:byte()) end)..'"' end
  assert(t=='table','not JSON')
  local out={}
  if #v>0 then for i=1,#v do out[i]=J.encode(v[i]) end return '['..table.concat(out,',')..']' end
  for k,x in pairs(v) do out[#out+1]=J.encode(tostring(k))..':'..J.encode(x) end
  table.sort(out)
  return '{'..table.concat(out,',')..'}'
end
function J.decode(s)
  if type(s)~='string' then return nil end
  local i=1
  local function ws() local _,p=s:find('^[ \n\r\t]*',i) i=(p or i-1)+1 end
  local parse
  local function str()
    i=i+1 local out={}
    while i<=#s do
      local c=s:sub(i,i) i=i+1
      if c=='"' then return table.concat(out) end
      if c=='\\' then
        c=s:sub(i,i) i=i+1
        local m={n='\n',r='\r',t='\t',b='\b',f='\f',['"']='"',['\\']='\\',['/']='/'}
        if c=='u' then local n=tonumber(s:sub(i,i+3),16) assert(n) c=utf8.char(n) i=i+4 else c=assert(m[c]) end
      end
      out[#out+1]=c
    end
    error('unterminated JSON')
  end
  parse=function()
    ws() local c=s:sub(i,i)
    if c=='"' then return str() end
    if c=='{' or c=='[' then
      local obj,close={},c=='{' and '}' or ']' i=i+1 ws()
      if s:sub(i,i)==close then i=i+1 return obj end
      while true do
        if c=='{' then assert(s:sub(i,i)=='"') local k=str() ws() assert(s:sub(i,i)==':') i=i+1 obj[k]=parse()
        else obj[#obj+1]=parse() end
        ws() local x=s:sub(i,i) i=i+1
        if x==close then return obj end
        assert(x==',','JSON comma') ws()
      end
    end
    for text,value in pairs({['true']=true,['false']=false}) do if s:sub(i,i+#text-1)==text then i=i+#text return value end end
    if s:sub(i,i+3)=='null' then i=i+4 return nil end
    local n=s:match('^-?%d+%.?%d*[eE]?[+-]?%d*',i) assert(n and #n>0,'JSON number') i=i+#n return assert(tonumber(n))
  end
  local ok,result=pcall(parse) if not ok then return nil,result end
  ws() if i<=#s then return nil,'trailing JSON' end
  return result
end
return J
