local s,event,key,rep=...
if event=="key" then
  if rep then return true end
  if s[57]=="title" then
    if key=="select" then s[56]=true
    elseif key=="right" then s[57]="about"
    elseif key=="back" then return false end
  elseif key=="back" then s[57]="title" end
  s[20]=true; return true
end
local function line(i,y,text,color)
  s[60][46+i]=ui.label(10,y,text,{size=i==1 and 20 or 12,w=300,color=color or "text"})
end
if s[57]=="title" then
  line(1,18,"Solana Defenders","green")
  line(2,58,"Top score each day wins !LAMPs")
  line(3,80,"Tweet your score and tag @range_org")
  if s[14] then line(4,110,"Link X to earn !LAMPs","dim") end
  line(5,148,(s[3] and "TODAY "..s[3].."   " or "").."BEST "..s[4],"aqua")
  ui.hint("SELECT play   RIGHT about")
else
  line(2,4,"Solana Defenders by")
  line(3,18,"Jose Santos and Range")
  local url="https://www.range.org/product/transaction-screening?utm_source=bp26-badge"
  if ui.qr then s[60][59]=ui.qr(77,36,166,url)
  else line(4,68,url:sub(1,48).."..."); ui.toast("Update Solana OS to scan") end
  ui.hint("BACK return")
end
