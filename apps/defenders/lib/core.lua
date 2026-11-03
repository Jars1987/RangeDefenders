-- Permanent state. Entity data uses dense arrays and a 24-bit live mask.
local s={state="title",return_to="title",score=0,wave=1,lives=3,px=147,
  best=tonumber(storage.get("best")) or 0,w={},bx={},by={},bn={},hp={3,3,3},
  colors={"pink","orange","yellow","purple"},wait=0,retry=5000,ticket=0,flash=0,
  welcome_amount=0,reward_note="",notice="",top={},board_best=0}
function s.clean(v,n) return tostring(v or ""):gsub("[^ -~]","?"):sub(1,n or 35) end
function s.integer(n) return type(n)=="number" and n==math.floor(n) and n>=0 and n<=2000000000 end
function s.op()
  return string.format("%06x%06x%06x%06x",math.random(0,16777215),math.random(0,16777215),math.random(0,16777215),math.random(0,16777215))
end
function s.line(i,y,text,color,x)
  local p=s.w[46+i]
  p:pos(x or 10,y); p:text(s.clean(text,200)); p:color(color or "text"); p:show(true)
end
function s.hide() for i=2,59 do if s.w[i] then s.w[i]:show(false) end end end
function s.name(i)
  local row=(i-1)//6+1
  local n=((i-1)%6+s.wave-1)%s.counts[row]+1
  for name in s.names[row]:gmatch("[^|]+") do n=n-1; if n==0 then return name end end
end
s.welcome=storage.get("welcome") or {op=s.op()}
s.pending=storage.get("score_pending"); s.next_score=storage.get("score_next")
return s
