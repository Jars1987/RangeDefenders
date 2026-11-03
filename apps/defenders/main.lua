local SERVER = "https://example.trycloudflare.com"
local SHORT_ORIGIN = "https://rng.example"
-- Network stays resident; play is compiled once per game.
-- Dense state slots avoid a hash table; see the slot legend below.
-- Enemies use a 24-bit mask. Slots 2, 16 and 17 are reserved.
local s={[51]=SERVER,[54]=SHORT_ORIGIN,[57]="title",[47]="title",[49]=0,[62]=1,[31]=3,[42]=147,
  [4]=tonumber(storage.get("best")) or 0,[60]={},[12]={},[13]={},[5]={},[27]={3,3,3},
  [61]=0,[46]=5000,[58]=0,[23]=0,
  [48]="",[36]="",[59]={}}
s[63]=storage.get("welcome") or {op=string.format("%08x%08x",math.random(1,2147483646),math.random(1,2147483646))}
s[38]=storage.get("score_pending"); s[35]=storage.get("score_next")
assert(fs.load("lib/init.lua"))(s)
assert(fs.load("lib/callbacks.lua"))(s)
profile.me(function(ok,p)
  if s[15] then return end
  s[37]=not ok
  s[26]={app="defenders",name=ok and type(p)=="table" and tostring(p.name or "Player"):gsub("[^ -~]","?"):sub(1,40) or "Player",v="1.0.0"}
  if ok and type(p)=="table" and type(p.x)=="string" then s[26].x=p.x:gsub("[^ -~]","?"):sub(1,40) end
  s[61]=0; s[20]=true
end)

-- State slots: 1=alive, 2=award_reply, 3=award_tried, 4=best, 5=bn, 6=boss_cd, 7=boss_dir, 8=boss_hp, 9=boss_killed, 10=boss_x, 11=busy, 12=bx, 13=by, 14=claim_done, 15=closed, 16=colors, 17=counts, 18=deadline, 19=dir, 20=dirty, 21=finish, 22=fire_cd, 23=flash, 24=fx, 25=fy, 26=hello, 27=hp, 28=killer, 29=kind, 30=lamp_reply, 31=lives, 32=mask, 33=names, 34=new_best, 35=next_score, 36=notice, 37=offline, 38=pending, 39=play, 40=play_ms, 41=popup_cd, 42=px, 43=rank, 44=response, 45=result_op, 46=retry, 47=return_to, 48=reward_note, 49=score, 50=send, 51=server, 52=share_pending, 53=share_url, 54=short, 55=shot_cd, 56=start, 57=state, 58=ticket, 59=top, 60=w, 61=wait, 62=wave, 63=welcome, 64=welcome_amount
