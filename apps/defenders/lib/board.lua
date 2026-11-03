local s,event,key,rep=...
if event=="finish" then
  s.lives=0; s.new_best=s.score>s.best
  if s.new_best then s.best=s.score; storage.set("best",s.best) end
  s.result_op=s.op()
  local r={score=s.score,wave=s.wave,boss=s.boss_killed,op=s.result_op}
  if s.pending then
    if not s.next_score or r.score>=s.next_score.score then s.next_score=r; storage.set("score_next",r) end
  else s.pending=r; storage.set("score_pending",r) end
  s.need=true; s.flash=8; led.fill(220,30,80); s.dirty=true; return
elseif event=="key" then
  if rep then return true end
  if key=="select" then s.start=true
  elseif key=="down" then s.return_to=s.state; s.state="qr"
  elseif key=="right" then s.return_to=s.state; s.state="about"
  elseif key=="up" and s.share_url then s.return_to=s.state; s.state="share"
  elseif key=="back" then s.state="title" end
  s.dirty=true; return true
end
local line=s.line
line(1,8,"RANGE ALERT","pink"); line(2,34,s.killer,"orange")
line(3,51,"SCORE "..s.score.."   WAVE "..s.wave)
line(4,68,"BEST "..math.max(s.best,s.board_best).."   RANK "..(s.rank or "--"),"aqua")
for i=1,5 do
  local r=s.top[i]
  line(4+i,73+i*16,r and (i..". "..r.n.."  "..r.s) or (i..". --"),"dim")
end
line(10,173,s.share_url and "UP share your best" or s.new_best and "NEW PERSONAL BEST" or "Screen threats before funds move","green")
if s.offline then line(12,188,"offline - score saved for retry","dim") end
ui.hint("SELECT retry   DOWN QR   RIGHT about")
