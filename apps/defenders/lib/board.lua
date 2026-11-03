local s,event,key,rep=...
if event=="finish" then
  s[31]=0; s[34]=s[49]>s[4]
  if s[34] then s[4]=s[49]; storage.set("best",s[4]) end
  if s[2] then s[3]=math.max(s[3],s[49]); storage.set("today",s[3]) end
  local code=assert(fs.load("lib/code.lua"))(s[49],s[2])
  s[53]="https://x.com/intent/post?text=I+scored+"..s[49]..
    "+on+Solana+Defenders+at+%23Breakpoint.+Beat+it%3F+%40range_org+"..code
  s[23]=8; led.fill(220,30,80); s[20]=true
elseif event=="key" then
  if rep then return true end
  if key=="select" then s[56]=true
  elseif key=="right" and s[54]~="" then s[16]=not s[16]
  elseif key=="back" then s[57]="title" end
  s[20]=true; return true
end
local function line(i,y,text,color)
  s[60][46+i]=ui.label(4,y,text,{size=12,w=110,color=color or "text"})
end
line(1,6,"RANGE ALERT","pink"); line(2,28,s[28],"orange")
line(3,66,"SCORE","green"); line(4,82,tostring(s[49]),"green")
line(5,108,"TODAY "..(s[3] or "--"),"aqua")
line(6,126,"BEST "..s[4],"aqua"); line(7,148,"WAVE "..s[62])
line(8,174,s[16] and "Scan to repost Range" or "Scan to post your score","dim")
local url=s[16] and "https://x.com/intent/retweet?tweet_id="..s[54] or s[53]
if ui.qr then s[60][59]=ui.qr(118,0,202,url)
else
  s[60][59]=ui.label(122,66,url:sub(1,60).."...",{size=12,w=194})
  ui.toast("Update Solana OS to scan")
end
ui.hint("SELECT retry  BACK title"..(s[54]~="" and "  RIGHT repost" or ""))
