local s=...
local function integer(n) return type(n)=="number" and n%1==0 and n>=0 and n<=2000000000 end
local function clean(v,n) return (type(v)=="string" and v or ""):gsub("[^ -~]","?"):sub(1,n or 35) end
local good=false
if s[30] then
  local ok,r=s[30][1],s[30][2]; s[30]=nil
  local a=s[63]
  if ok and type(r)=="table" and integer(r.awarded) then
    if r.awarded>0 then a={done=true}; s[63]=a; s[48]="+"..r.awarded.." !LAMPs welcome bonus"
    elseif r.needsX then s[48]="Link X to earn !LAMPs"
    else s[48]="Welcome award unavailable" end
    a.started=false
  elseif not ok then
    if r=="denied" or r=="offline" or r=="not linked" then a.started=false end
    s[48]=r=="denied" and "Welcome award denied" or "Welcome award pending"
  end
  storage.set("welcome",a); s[20]=true
elseif s[44] then
  local ok,res=s[44][1],s[44][2]; s[44]=nil; s[11]=false
  local r
  if ok and type(res)=="table" and res.status==200 and not res.truncated and type(res.body)=="string" and #res.body<=3072 then r=json.decode(res.body) end
  res=nil
  if type(r)=="table" and r.ok==true then
    if s[29]=="hello" then
      if type(r.welcome)=="table" and integer(r.welcome.amount) and type(r.welcome.eligible)=="boolean" then
        s[26]=nil; s[64]=r.welcome.amount; s[14]=not r.welcome.eligible; s[36]=clean(r.msg); good=true
      end
    elseif s[29]=="claim" then
      if integer(r.amount) then s[63].amount=r.amount; s[14]=true; storage.set("welcome",s[63]); good=true end
    elseif s[29]=="score" then
      good=integer(r.best) and (r.rank==nil or integer(r.rank)) and type(r.top)=="table" and #r.top<=5
      if good then
        for i=1,#r.top do
          local row=r.top[i]
          if type(row)~="table" or type(row.n)~="string" or not integer(row.s) then good=false; break end
        end
      end
      if good then
        if s[38].op==s[45] then
          s[4]=math.max(s[4],r.best); s[43]=r.rank; s[59]={}
          for i=1,#r.top do s[59][i]={n=clean(r.top[i].n,22),s=r.top[i].s} end
          if s[34] then s[52]=s[38] end
        end
        s[38]=s[35]; s[35]=nil
        if s[38] then storage.set("score_pending",s[38]) else storage.remove("score_pending") end
        storage.remove("score_next")
      end
    elseif s[29]=="share" then
      good=type(r.url)=="string" and #r.url<=40 and r.url:sub(1,8)=="https://" and not r.url:find("[^ -~]")
      if good then if s[52].op==s[45] then s[53]=r.url end; s[52]=nil end
    end
  end
  s[37]=not good
  if good then s[46]=5000; s[61]=1200 else s[61]=s[46]; s[46]=math.min(30000,s[46]*2) end
  s[20]=true
elseif s[11] then
  s[11]=false; s[58]=s[58]+1; s[37]=true; s[61]=s[46]; s[46]=math.min(30000,s[46]*2); s[20]=true
elseif s[38] then
  s[50]("/v1/defenders/score",s[38],"score")
elseif s[26] then s[50]("/v1/hello",s[26],"hello")
elseif s[64]~=nil and s[64]>0 and not s[14] and not s[63].done and not s[63].started then
  storage.set("welcome",s[63])
  s[50]("/v1/welcome/claim",{app="defenders",op=s[63].op},"claim")
elseif s[52] then
  local a=s[52];
  s[50]("/v1/share",{app="defenders",kind="score",data={score=a.score,wave=a.wave,boss=a.boss}},"share")
else s[61]=5000
end
local a=s[63]
if s[64]~=nil and not s[3] and not a.done and not a.started and integer(a.amount) and a.amount>0 then
  -- No award operation ID exists. Do not replay an ambiguous transport result.
  s[3]=true; a.started=true; storage.set("welcome",a)
  lamps.award(a.amount,"Welcome to Solana Defenders",function(ok,r) if not s[15] then s[30]={ok,r} end end)
end
