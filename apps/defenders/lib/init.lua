local s=...
local w=s.w
ui.bg("bg")
w[1]=ui.rect(0,0,320,3,{color="green"})
for i=2,25 do w[i]=ui.label(0,0,"",{size=12,mono=true}) end
for i=1,8 do
  w[25+i]=ui.rect(0,0,3,7,{color=i<=5 and "green" or "pink"})
  s.bx[i]=0; s.by[i]=0; s.bn[i]=""
end
for i=1,3 do w[33+i]=ui.rect(i*80-14,174,28,7,{color="aqua",radius=2}) end
w[37]=ui.label(147,188,"/^\\",{size=12,color="green",mono=true})
w[38]=ui.label(100,19,"<LAZARUS>",{size=12,color="aqua",mono=true})
local rows={"EXPLOIT","SCAM","MIXER","DRAINER"}
for i=1,4 do w[38+i]=ui.label(4,34+(i-1)*25,rows[i],{size=12,color=s.colors[i]}) end
w[43]=ui.label(6,5,"",{size=12,w=150})
w[44]=ui.label(156,5,"",{size=12,w=90})
w[45]=ui.label(250,5,"",{size=12,w=66,align="right"})
w[46]=ui.label(2,153,"",{size=12,w=316,align="center",color="green"})
for i=1,12 do w[46+i]=ui.label(10,10,"",{size=i==1 and 20 or 12,w=300}) end
if ui.qr then w[59]=ui.qr(70,14,180,s.server.."/go/screening?a=defenders") end
ui.hint("")
