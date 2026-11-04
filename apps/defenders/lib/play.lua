local s,event,key,rep=...
local w=s[60]
local function name(i)
  local row=(i-1)//6+1
  local n=((i-1)%6+s[62]-1)%(row==1 and 11 or row==2 and 5 or 3)+1
  for value in s[33][row]:gmatch("[^|]+") do n=n-1; if n==0 then return value end end
end
local floor,min,max=math.floor,math.min,math.max
local function wave()
  s[32]=0xFFFFFF; s[1]=24; s[24]=83; s[25]=32+min(s[62]-1,6)*4; s[19]=1
  for i=1,8 do s[13][i]=0 end
  for i=1,3 do s[27][i]=3 end
  s[55]=24; s[6]=240; s[8]=0
end
local function report(name,points)
  if points then
    w[46]:text(name.." +"..points); s[41]=16
    w[46]:color(s[63][5-points//10] or "aqua")
    s[49]=min(2000000000,s[49]+points); led.fill(20,241,149); s[23]=2
  else
    s[28]=name; s[57]="over"; s[21]=true; s[20]=true
  end
end
local function hit(x,y,a,b,c,d)
  return x<c+a and c<x+3 and y<d+b and d<y+7
end
-- Return before building widgets so compiler garbage can die with this callback.
if event=="start" then wave(); s[20]=true; return
elseif event=="key" then
  if key=="left" or key=="right" then
    s[42]=max(2,min(296,s[42]+(key=="left" and -8 or 8))); if w[37] then w[37]:pos(s[42],188) end
  elseif key=="back" and not rep then s[57]="pause"; s[20]=true end
  return true
elseif event=="tick" then
  s[22]=s[22]-1; s[55]=s[55]-1; s[6]=s[6]-1
  s[41]=max(0,s[41]-1)
  if s[22]<=0 then
    for i=1,5 do if s[13][i]==0 then s[12][i]=s[42]+9; s[13][i]=182; s[22]=5; break end end
  end
  local left,right,bottom=320,0,0
  s[24]=s[24]+s[19]*(0.5+min(s[62],15)*0.1+(24-s[1])*0.025)
  for i=1,24 do
    if s[32] & (1<<(i-1))~=0 then
      local x,y=s[24]+(i-1)%6*33,s[25]+(i-1)//6*25
      left=min(left,x); right=max(right,x+22); bottom=max(bottom,y+14)
    end
  end
  if (s[19]>0 and right>=316) or (s[19]<0 and left<=80) then s[19]=-s[19]; s[25]=s[25]+5; s[24]=s[24]+s[19]*2 end
  if bottom>=186 then
    for i=24,1,-1 do if s[32] & (1<<(i-1))~=0 and s[25]+(i-1)//6*25+14>=186 then report(name(i)); return end end
  end
  if bottom>=174 then for i=1,3 do s[27][i]=0 end end
  if s[8]>0 then
    s[10]=s[10]+s[7]*1.5
    if s[10]>=248 then s[7]=-1 elseif s[10]<=82 then s[7]=1 end
  elseif s[6]<=0 then s[8]=3; s[10]=120; s[7]=1; s[6]=360 end
  for i=1,5 do
    if s[13][i]>0 then
      s[13][i]=s[13][i]-11
      if s[13][i]<15 then s[13][i]=0
      elseif s[8]>0 and hit(s[12][i],s[13][i],70,12,s[10],19) then
        s[13][i]=0; s[8]=s[8]-1
        if s[8]==0 then s[9]=true; report("LAZARUS",300) end
      else
        for j=24,1,-1 do
          local bit=1<<(j-1)
          -- Match the four-column, two-line sprite and integer widget origin.
          if s[32] & bit~=0 and hit(s[12][i],s[13][i],22,24,floor(s[24])+(j-1)%6*33,floor(s[25])+(j-1)//6*25) then
            s[32]=s[32] & ~bit; s[1]=s[1]-1; s[13][i]=0
            report(name(j),(4-(j-1)//6)*10); break
          end
        end
      end
    end
  end
  if s[55]<=0 and s[1]>0 then
    local shooter=math.random(1,24)
    for n=0,23 do local j=(shooter+n-1)%24+1; if s[32] & (1<<(j-1))~=0 then shooter=j; break end end
    for i=6,8 do
      if s[13][i]==0 then s[12][i]=s[24]+(shooter-1)%6*33+10; s[13][i]=s[25]+(shooter-1)//6*25+14; s[5][i-5]=name(shooter); break end
    end
    s[55]=max(10,32-s[62])
  end
  for i=6,8 do
    if s[13][i]>0 then
      s[13][i]=s[13][i]+3+min(s[62],10)*0.15
      if s[13][i]>201 then s[13][i]=0 end
      for j=1,3 do
        if s[13][i]>0 and s[27][j]>0 and hit(s[12][i],s[13][i],28,7,j*80-14,174) then s[27][j]=s[27][j]-1; s[13][i]=0 end
      end
      if s[13][i]>0 and hit(s[12][i],s[13][i],22,12,s[42],188) then
        s[31]=s[31]-1; led.fill(220,30,80); s[23]=5
        for j=6,8 do s[13][j]=0 end
        if s[31]<=0 then report(s[5][i-5]); return end
      end
    end
  end
  if s[1]==0 then s[62]=s[62]+1; s[31]=min(5,s[31]+1); wave(); w[46]:text("WAVE CLEARED +1 LIFE"); w[46]:color("green"); s[41]=30 end
end
if not w[60] then
  s[30]=nil; s[64]=nil; s[65]=nil; ui.hint("")
  -- One label per alien: the badge font is proportional, so blanking sprites
  -- inside a row label would slide the survivors off their hit boxes.
  for i=1,24 do local r=(i-1)//6+1; w[59+i]=ui.label(0,0,s[61][r*2-1].."\n"..s[61][r*2],{size=12,color=s[63][r]}) end
  for i=1,8 do w[26+i]=ui.rect(0,0,3,7,{color=i<=5 and "green" or "pink"}) end
  for i=1,3 do
    local x=i*80-14
    w[15+i*3]=ui.rect(x,174,28,3,{color="green"})
    w[16+i*3]=ui.rect(x,177,7,4,{color="green"})
    w[17+i*3]=ui.rect(x+21,177,7,4,{color="green"})
  end
  w[37]=ui.label(s[42],188,"/^\\",{size=12,color="purple",mono=true})
  w[38]=ui.label(100,19,"<o_o_oo_o_o>",{size=12,color="aqua",mono=true})
  w[43]=ui.label(6,5,"",{size=12,w=114})
  w[44]=ui.label(120,5,"",{size=12,w=80,align="center",color="aqua"})
  w[45]=ui.label(224,5,"",{size=12,w=90,align="right",color="green"})
  w[46]=ui.label(2,22,"",{size=12,w=76,color="green"})
  w[47]=ui.label(0,202,"screened by range.org",{size=12,w=320,align="center",color="dim"})
end
if s[30]~=s[32] then for i=1,24 do w[59+i]:show(s[32] & (1<<(i-1))~=0) end end
s[30]=s[32]
for i=1,24 do
  if s[32] & (1<<(i-1))~=0 then w[59+i]:pos(floor(s[24])+(i-1)%6*33,floor(s[25])+(i-1)//6*25) end
end
for i=1,8 do w[i+26]:show(s[13][i]>0); if s[13][i]>0 then w[i+26]:pos(floor(s[12][i]),floor(s[13][i])) end end
for i=1,3 do
  w[15+i*3]:show(s[27][i]>=2); w[16+i*3]:show(s[27][i]>=1); w[17+i*3]:show(s[27][i]>=3)
end
-- Only rebuild HUD strings when they change; per-tick strings filled the heap.
if s[64]~=s[49] then s[64]=s[49]; w[43]:text(string.format("SCORE %05d",s[49])) end
if s[65]~=s[62]*8+s[31] then s[65]=s[62]*8+s[31]; w[44]:text("WAVE "..s[62]); w[45]:text(string.rep("/^\\",s[31])) end
w[38]:pos(floor(s[10]),19); w[38]:show(s[8]>0); w[46]:show(s[41]>0)
