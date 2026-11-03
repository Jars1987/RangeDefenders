local s=...
local integer=s.integer
local good=false
if s.lamp_reply then
  local ok,r=s.lamp_reply[1],s.lamp_reply[2]; s.lamp_reply=nil
  local a=s.welcome
  if ok and type(r)=="table" and integer(r.awarded) then
    if r.awarded>0 then a.done=true; s.reward_note="+"..r.awarded.." !LAMPs welcome bonus"
    elseif r.needsX then s.reward_note="Link X to earn !LAMPs"
    else s.reward_note="Welcome award unavailable" end
    a.started=false
  elseif not ok then
    if r=="denied" or r=="offline" or r=="not linked" then a.started=false end
    s.reward_note=r=="denied" and "Welcome award denied" or "Welcome award pending"
  end
  storage.set("welcome",a); s.dirty=true
elseif s.response then
  local ok,res=s.response[1],s.response[2]; s.response=nil; s.busy=false
  local r
  if ok and type(res)=="table" and res.status==200 and not res.truncated and type(res.body)=="string" and #res.body<=3072 then r=json.decode(res.body) end
  if type(r)=="table" and r.ok==true then
    if s.kind=="hello" then
      if type(r.welcome)=="table" and integer(r.welcome.amount) and type(r.welcome.eligible)=="boolean" then
        s.hello=nil; s.hello_done=true; s.welcome_amount=r.welcome.amount; s.eligible=r.welcome.eligible; s.notice=s.clean(r.msg); good=true
      end
    elseif s.kind=="claim" then
      if integer(r.amount) then s.welcome.amount=r.amount; s.claim_done=true; storage.set("welcome",s.welcome); good=true end
    elseif s.kind=="score" then
      good=integer(r.best) and (r.rank==nil or integer(r.rank)) and type(r.top)=="table" and #r.top<=5
      if good then
        for i=1,#r.top do
          local row=r.top[i]
          if type(row)~="table" or type(row.n)~="string" or not integer(row.s) then good=false; break end
        end
      end
      if good then
        if s.sent.op==s.result_op then
          s.board_best=r.best; s.rank=r.rank; s.top={}
          for i=1,#r.top do s.top[i]={n=s.clean(r.top[i].n,22),s=r.top[i].s} end
          if s.new_best then s.share_pending=s.sent end
        end
        s.pending=s.next_score; s.next_score=nil; s.sent=nil
        if s.pending then storage.set("score_pending",s.pending) else storage.remove("score_pending") end
        storage.remove("score_next")
      end
    elseif s.kind=="share" then
      good=type(r.url)=="string" and #r.url<=40 and r.url:sub(1,#s.server+3)==s.server.."/r/" and not r.url:find("[^ -~]")
      if good then if s.shared_op==s.result_op then s.share_url=r.url end; s.share_pending=nil end
    end
  end
  s.offline=not good
  if good then s.retry=5000; s.wait=1200 else s.wait=s.retry; s.retry=math.min(30000,s.retry*2) end
  s.dirty=true
elseif s.busy then
  s.busy=false; s.ticket=s.ticket+1; s.offline=true; s.wait=s.retry; s.retry=math.min(30000,s.retry*2); s.dirty=true
elseif s.pending then
  s.sent=s.pending; s.send("/v1/defenders/score",s.pending,"score")
elseif s.hello then s.send("/v1/hello",s.hello,"hello")
elseif s.hello_done and s.eligible and s.welcome_amount>0 and not s.claim_done and not s.welcome.done and not s.welcome.started then
  storage.set("welcome",s.welcome)
  s.send("/v1/welcome/claim",{app="defenders",op=s.welcome.op},"claim")
elseif s.share_pending then
  local a=s.share_pending; s.shared_op=a.op
  s.send("/v1/share",{app="defenders",kind="score",data={score=a.score,wave=a.wave,boss=a.boss}},"share")
end
local a=s.welcome
if s.hello_done and not s.award_tried and not a.done and not a.started and integer(a.amount) and a.amount>0 then
  -- No award operation ID exists. Do not replay an ambiguous transport result.
  s.award_tried=true; a.started=true; storage.set("welcome",a)
  lamps.award(a.amount,"Welcome to Solana Defenders",s.award_reply)
end
s.need=s.pending or s.hello or s.share_pending or (s.hello_done and s.eligible and s.welcome_amount>0 and not s.claim_done and not a.done and not a.started)
