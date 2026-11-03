local s,event,key,rep=...
if event=="key" then
  if rep then return true end
  if s.state=="title" then
    if key=="select" then s.start=true
    elseif key=="right" then s.return_to=s.state; s.state="about"
    elseif key=="down" then s.return_to=s.state; s.state="qr"
    elseif key=="back" then return false end
  elseif s.state=="pause" then
    if key=="select" then s.state="play" elseif key=="back" then s.state="title" end
  elseif s.state=="about" then
    if key=="down" then s.state="qr" elseif key=="back" then s.state=s.return_to end
  elseif key=="back" or key=="up" then s.state=s.return_to end
  s.dirty=true; return true
end
local line=s.line
if s.state=="title" then
  line(1,18,"Solana Defenders","green")
  line(2,52,"Top score each day wins !LAMPs.")
  line(3,68,"Finals at the Range booth.")
  if s.welcome_amount>0 then line(4,94,"Welcome bonus: "..s.welcome_amount.." !LAMPs","green") end
  line(5,112,"Link X to earn !LAMPs","dim"); line(6,141,"BEST "..s.best,"aqua")
  line(7,163,s.reward_note~="" and s.reward_note or s.notice,"dim")
  if s.offline then line(12,184,"offline","dim") end
  ui.hint("SELECT play  RIGHT about  DOWN QR")
elseif s.state=="pause" then
  line(1,40,"Paused","green"); line(2,88,"SCORE "..s.score.."   WAVE "..s.wave)
  ui.hint("SELECT resume   BACK title")
elseif s.state=="about" then
  line(1,18,"About","green"); line(2,58,"Solana Defenders by")
  line(3,75,"Jose Santos and Range"); line(4,109,"Screen Solana threats with Range.")
  line(5,130,"range.org","aqua"); ui.hint("DOWN screening QR   BACK return")
else
  local q=s.w[59]
  if q then q:text(s.state=="share" and s.share_url or s.server.."/go/screening?a=defenders"); q:show(true)
  else line(1,32,"QR unavailable","orange"); line(2,78,"Update Solana OS to scan.") end
  ui.hint("BACK return")
end
