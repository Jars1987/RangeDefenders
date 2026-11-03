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
-- The threat name gets two lines (18..42): long names like RAINBOW DRAINER wrap.
line(1,4,"RANGE ALERT","pink"); line(2,18,s[28],"orange")
line(3,46,"SCORE","green"); line(4,60,tostring(s[49]),"green")
line(5,82,"TODAY "..(s[3] or "--"),"aqua")
line(6,96,"BEST "..s[4],"aqua"); line(7,110,"WAVE "..s[62])
line(8,128,"CODE","dim")
s[60][55]=ui.label(4,142,s[53]:sub(-6),{size=20,mono=true,w=110,color="green"})
line(10,164,"SELECT retry\nBACK title"..(s[54]~="" and "\nRIGHT repost" or ""),"dim")
local url=s[16] and "https://x.com/intent/retweet?tweet_id="..s[54] or s[53]
if ui.qr then s[60][59]=ui.qr(118,0,202,url)
else
  s[60][59]=ui.label(122,66,url:sub(1,60).."...",{size=12,w=194})
  ui.toast("Update Solana OS to scan")
end
ui.hint(s[16] and "Scan to repost Range" or "Photo this screen, scan to post")
