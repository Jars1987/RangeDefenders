local s,event,key,rep=...
if event=="key" then
  if rep then return true end
  if s[57]=="title" then
    if key=="select" then s[56]=true
    elseif key=="right" then s[47]=s[57]; s[57]="about"
    elseif key=="down" then s[47]=s[57]; s[57]="qr"
    elseif key=="back" then return false end
  elseif s[57]=="pause" then
    if key=="select" then s[57]="play" elseif key=="back" then s[57]="title" end
  elseif s[57]=="about" then
    if key=="down" then s[57]="qr" elseif key=="back" then s[57]=s[47] end
  elseif key=="back" or key=="up" then s[57]=s[47] end
  s[20]=true; return true
end
local function line(i,y,text,color,x)
  local p=s[60][46+i]
  if not p then p=ui.label(10,y,"",{size=i==1 and 20 or 12,w=300}); s[60][46+i]=p end
  p:pos(x or 10,y); p:text(tostring(text or ""):gsub("[^ -~]","?"):sub(1,200)); p:color(color or "text"); p:show(true)
end

if s[57]=="title" then
  line(1,18,"Solana Defenders","green")
  line(2,52,"Top score each day wins !LAMPs.")
  line(3,68,"Finals at the Range booth.")
  if (s[64] or 0)>0 then line(4,94,"Welcome bonus: "..s[64].." !LAMPs","green") end
  line(5,112,"Link X to earn !LAMPs","dim"); line(6,141,"BEST "..s[4],"aqua")
  line(7,163,s[48]~="" and s[48] or s[36],"dim")
  if s[37] then line(12,184,"offline","dim") end
  ui.hint("SELECT play  RIGHT about  DOWN QR")
elseif s[57]=="pause" then
  line(1,40,"Paused","green"); line(2,88,"SCORE "..s[49].."   WAVE "..s[62])
  ui.hint("SELECT resume   BACK title")
elseif s[57]=="about" then
  line(1,18,"About","green"); line(2,58,"Solana Defenders by")
  line(3,75,"Jose Santos and Range"); line(4,109,"Screen Solana threats with Range.")
  line(5,130,"range.org","aqua"); ui.hint("DOWN screening QR   BACK return")
else
  local q=s[60][59]
  if not q and ui.qr then q=ui.qr(70,14,180,s[54].."/go/screening?a=defenders"); s[60][59]=q end
  if q then q:text(s[57]=="share" and s[53] or s[54].."/go/screening?a=defenders"); q:show(true)
  else line(1,32,"QR unavailable","orange"); line(2,78,"Update Solana OS to scan.") end
  ui.hint("BACK return")
end
