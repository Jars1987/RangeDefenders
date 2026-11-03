local s,event,key,rep=...
if event=="finish" then
  s[31]=0; s[34]=s[49]>s[4]
  if s[34] then s[4]=s[49]; storage.set("best",s[4]) end
  s[45]=string.format("%08x%08x",math.random(1,2147483646),math.random(1,2147483646))
  local r={score=s[49],wave=s[62],boss=s[9],seconds=math.max(1,math.ceil(s[40]/1000)),op=s[45]}
  if s[38] then
    if not s[35] or r.score>=s[35].score then s[35]=r; storage.set("score_next",r) end
  else s[38]=r; storage.set("score_pending",r) end
  s[61]=0; s[23]=8; led.fill(220,30,80); s[20]=true; return
elseif event=="key" then
  if rep then return true end
  if key=="select" then s[56]=true
  elseif key=="down" then s[47]=s[57]; s[57]="qr"
  elseif key=="right" then s[47]=s[57]; s[57]="about"
  elseif key=="up" and s[53] then s[47]=s[57]; s[57]="share"
  elseif key=="back" then s[57]="title" end
  s[20]=true; return true
end
local function line(i,y,text,color,x)
  local p=s[60][46+i]
  if not p then p=ui.label(10,y,"",{size=i==1 and 20 or 12,w=300}); s[60][46+i]=p end
  p:pos(x or 10,y); p:text(tostring(text or ""):gsub("[^ -~]","?"):sub(1,200)); p:color(color or "text"); p:show(true)
end

line(1,8,"RANGE ALERT","pink"); line(2,34,s[28],"orange")
line(3,51,"SCORE "..s[49].."   WAVE "..s[62])
line(4,68,"BEST "..s[4].."   RANK "..(s[43] or "--"),"aqua")
for i=1,5 do
  local r=s[59][i]
  line(4+i,73+i*16,r and (i..". "..r.n.."  "..r.s) or (i..". --"),"dim")
end
line(10,173,s[53] and "UP share your best" or s[34] and "NEW PERSONAL BEST" or "Screen threats before funds move","green")
if s[37] then line(12,188,"offline - score saved for retry","dim") end
ui.hint("SELECT retry   DOWN QR   RIGHT about")
