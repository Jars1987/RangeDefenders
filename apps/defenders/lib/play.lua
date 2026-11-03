local s,event,key,rep=...
local w=s.w
local floor,min,max=math.floor,math.min,math.max
local function wave()
  s.mask=0xFFFFFF; s.alive=24; s.fx=83; s.fy=32+min(s.wave-1,6)*4; s.dir=1
  for i=1,8 do s.by[i]=0 end
  for i=1,3 do s.hp[i]=3 end
  s.shot_cd=24; s.boss_cd=240; s.boss_hp=0
end
local function pop(name,points)
  w[46]:text(name.." +"..points); s.popup_cd=16
  s.score=min(2000000000,s.score+points); led.fill(20,241,149); s.flash=2
end
local function over(name)
  s.killer=s.clean(name); s.state="over"; s.finish=true; s.dirty=true
end
local function hit(x,y,a,b,c,d)
  return x<c+a and c<x+3 and y<d+b and d<y+7
end
if event=="start" then
  s.score=0; s.wave=1; s.lives=3; s.px=147; s.new_best=false; s.boss_killed=false
  s.killer=""; s.share_url=nil; s.result_op=nil; s.rank=nil; s.board_best=0; s.top={}
  s.fire_cd=0; s.popup_cd=0; s.boss_x=100; s.boss_dir=1
  s.counts={11,5,3,3}
  s.names={
    "WORMHOLE HACKER|BYBIT HACKER|BRIDGE HACKER|RAYDIUM HACKER|SOLEND HACKER|CREMA HACKER|NIRVANA HACKER|CYPHER HACKER|LOOPSCALE HACKER|DEXX HACKER|DEFITUNA HACKER",
    "PUMP AND DUMP|SCAM COIN|RUG PULL DEV|PRESALE SCAMMER|FAKE AIRDROP",
    "DPRK WALLET 1|DPRK WALLET 2|LAUNDERING HOP",
    "RAINBOW DRAINER|WALLET DRAINER|FAKE MINT SITE"}
  local glyphs={"<W>","{V}","(@)","[v]"}
  for i=1,24 do local r=(i-1)//6+1; w[i+1]:text(glyphs[r]); w[i+1]:color(s.colors[r]) end
  wave(); s.state="play"; led.off(); s.dirty=true; return
elseif event=="key" then
  if key=="left" then s.px=max(2,s.px-8); w[37]:pos(floor(s.px),188)
  elseif key=="right" then s.px=min(296,s.px+8); w[37]:pos(floor(s.px),188)
  elseif key=="back" and not rep then s.state="pause"; s.dirty=true end
  return true
elseif event=="tick" then
  s.fire_cd=s.fire_cd-1; s.shot_cd=s.shot_cd-1; s.boss_cd=s.boss_cd-1
  s.popup_cd=max(0,s.popup_cd-1)
  if s.fire_cd<=0 then
    for i=1,5 do if s.by[i]==0 then s.bx[i]=s.px+9; s.by[i]=182; s.fire_cd=5; break end end
  end
  local left,right,bottom=320,0,0
  s.fx=s.fx+s.dir*(0.5+min(s.wave,15)*0.1+(24-s.alive)*0.025)
  for i=1,24 do
    if s.mask & (1<<(i-1))~=0 then
      local x,y=s.fx+(i-1)%6*33,s.fy+(i-1)//6*25
      left=min(left,x); right=max(right,x+22); bottom=max(bottom,y+14)
    end
  end
  if (s.dir>0 and right>=316) or (s.dir<0 and left<=80) then s.dir=-s.dir; s.fy=s.fy+5; s.fx=s.fx+s.dir*2 end
  if bottom>=186 then
    for i=24,1,-1 do if s.mask & (1<<(i-1))~=0 and s.fy+(i-1)//6*25+14>=186 then over(s.name(i)); return end end
  end
  if bottom>=174 then for i=1,3 do s.hp[i]=0 end end
  if s.boss_hp>0 then
    s.boss_x=s.boss_x+s.boss_dir*1.5
    if s.boss_x>=248 then s.boss_dir=-1 elseif s.boss_x<=82 then s.boss_dir=1 end
  elseif s.boss_cd<=0 then s.boss_hp=3; s.boss_x=120; s.boss_dir=1; s.boss_cd=360 end
  for i=1,5 do
    if s.by[i]>0 then
      s.by[i]=s.by[i]-11
      if s.by[i]<15 then s.by[i]=0
      elseif s.boss_hp>0 and hit(s.bx[i],s.by[i],70,12,s.boss_x,19) then
        s.by[i]=0; s.boss_hp=s.boss_hp-1
        if s.boss_hp==0 then s.boss_killed=true; pop("LAZARUS",300) end
      else
        for j=24,1,-1 do
          local bit=1<<(j-1)
          if s.mask & bit~=0 and hit(s.bx[i],s.by[i],22,14,s.fx+(j-1)%6*33,s.fy+(j-1)//6*25) then
            s.mask=s.mask & ~bit; s.alive=s.alive-1; s.by[i]=0
            pop(s.name(j),(5-((j-1)//6+1))*10); break
          end
        end
      end
    end
  end
  if s.shot_cd<=0 and s.alive>0 then
    local first=math.random(1,24)
    local shooter=first
    for n=0,23 do local j=(first+n-1)%24+1; if s.mask & (1<<(j-1))~=0 then shooter=j; break end end
    for i=6,8 do
      if s.by[i]==0 then s.bx[i]=s.fx+(shooter-1)%6*33+10; s.by[i]=s.fy+(shooter-1)//6*25+14; s.bn[i]=s.name(shooter); break end
    end
    s.shot_cd=max(10,32-s.wave)
  end
  for i=6,8 do
    if s.by[i]>0 then
      s.by[i]=s.by[i]+3+min(s.wave,10)*0.15
      if s.by[i]>201 then s.by[i]=0 end
      for j=1,3 do
        if s.by[i]>0 and s.hp[j]>0 and hit(s.bx[i],s.by[i],28,7,j*80-14,174) then s.hp[j]=s.hp[j]-1; s.by[i]=0 end
      end
      if s.by[i]>0 and hit(s.bx[i],s.by[i],22,12,s.px,188) then
        s.lives=s.lives-1; led.fill(220,30,80); s.flash=5
        for j=6,8 do s.by[j]=0 end
        if s.lives<=0 then over(s.bn[i]); return end
      end
    end
  end
  if s.alive==0 then s.wave=s.wave+1; s.lives=min(5,s.lives+1); wave(); w[46]:text("WAVE CLEARED +1 LIFE"); s.popup_cd=30 end
end
for i=1,24 do
  local active=s.mask & (1<<(i-1))~=0
  w[i+1]:show(active)
  if active then w[i+1]:pos(floor(s.fx+(i-1)%6*33),floor(s.fy+(i-1)//6*25)) end
end
for i=1,8 do w[i+25]:show(s.by[i]>0); if s.by[i]>0 then w[i+25]:pos(floor(s.bx[i]),floor(s.by[i])) end end
for i=1,3 do w[i+33]:show(s.hp[i]>0); w[i+33]:color(s.hp[i]==1 and "orange" or "aqua"); w[i+42]:show(true) end
for i=39,42 do w[i]:show(true) end
w[43]:text("SCORE "..s.score); w[44]:text("WAVE "..s.wave); w[45]:text("LIFE "..s.lives)
w[37]:pos(floor(s.px),188); w[37]:show(true)
w[38]:pos(floor(s.boss_x),19); w[38]:show(s.boss_hp>0); w[46]:show(s.popup_cd>0)
if s.offline then s.line(12,190,"offline","dim",260) end
ui.hint("LEFT/RIGHT move   BACK pause")
