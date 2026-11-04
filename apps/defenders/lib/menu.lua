local s=...
local function line(i,y,text,color)
  s[60][46+i]=ui.label(10,y,text,{size=i==1 and 20 or 12,w=300,color=color or "text"})
end
if s[57]=="title" then
  s[60][47]=ui.label(0,0,"SOLANA",{size=32,w=320,align="center",color="green"})
  s[60][48]=ui.label(0,32,"DEFENDERS",{size=32,w=320,align="center",color="purple"})
  s[60][49]=ui.label(0,64,"by Range",{size=12,w=320,align="center",color="aqua"})
  local names={"EXPLOIT","SCAM","MIXER","DRAINER","LAZARUS"}
  local icons={"/oo\\","\\oo/","|<>|","[=o]","<oo>"}
  for i=1,5 do
    local y=84+(i-1)*18
    local color=s[63][i] or "aqua"
    s[60][13+i]=ui.label(6,y,icons[i],{size=12,color=color})
    s[60][18+i]=ui.label(36,y,string.format("%-12s%3s pts",names[i],i==5 and "???" or (5-i)*10),{size=12,w=124,color=color})
  end
  s[60][50]=ui.label(166,86,"Top score each day wins !LAMPs",{size=12,w=150})
  s[60][51]=ui.label(166,116,"Tweet your score and tag @range_org",{size=12,w=150})
  if s[14] then s[60][52]=ui.label(166,148,"Link X to earn !LAMPs",{size=12,w=150,color="dim"}) end
  s[60][53]=ui.label(6,180,(s[3] and "TODAY "..s[3].."   " or "").."BEST "..s[4],{size=12,w=308,align="center",color="aqua"})
  ui.hint("SELECT play   RIGHT about")
else
  line(2,4,"Solana Defenders by")
  line(3,18,"Jose Santos and Range")
  local url="https://www.range.org/product/transaction-screening?utm_source=bp26-badge"
  if ui.qr then s[60][59]=ui.qr(77,36,166,url)
  else line(4,68,url:sub(1,48).."..."); ui.toast("Update Solana OS to scan") end
  ui.hint("BACK return")
end
