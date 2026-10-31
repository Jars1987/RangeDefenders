-- Tiny SDK/lifecycle fixture, not a substitute for the production game.
local g, input, kv = badge.gfx, badge.input, badge.storage.kv
local THREATS = {
  {name="WORMHOLE HACKER", type="EXPLOIT", hits=2},
  {name="RUG PULL DEV", type="SCAM", hits=1},
  {name="LAZARUS", type="MIXER", hits=2},
  {name="WALLET DRAINER", type="DRAINER", hits=1},
}
-- BEGIN GENERATED QR
local QR = { url = "https://www.range.org", size = 21, rows = {
"101010101010101010101", "010101010101010101010", "101010101010101010101",
"010101010101010101010", "101010101010101010101", "010101010101010101010",
"101010101010101010101", "010101010101010101010", "101010101010101010101",
"010101010101010101010", "101010101010101010101", "010101010101010101010",
"101010101010101010101", "010101010101010101010", "101010101010101010101",
"010101010101010101010", "101010101010101010101", "010101010101010101010",
"101010101010101010101", "010101010101010101010", "101010101010101010101"
} }
-- END GENERATED QR
local mode,score,best,lives,ticks='title',0,0,3,0
local aliens,popups={},{}
function on_start()
  math.randomseed(string.unpack('<i4',badge.system.random_bytes(4)))
  best=tonumber(kv.get('best','0')) or 0
  for j,e in ipairs(THREATS) do
    aliens[j]={type=e.type,name=e.name,hits_left=e.hits,alive=true}
  end
end
function on_update(dt)
  assert(dt==1/60)
  if mode=='play' then
    ticks=ticks+1
    if input.down('a') and ticks%3==0 then
      for _,a in ipairs(aliens) do if a.alive then
        a.hits_left=a.hits_left-1
        if a.hits_left==0 then
          a.alive=false; score=score+40
          popups[#popups+1]=a.name..' +40'
        end
        break
      end end
    end
    if ticks>=48 then
      mode='over'; lives=0
      if score>best then best=score; kv.set('best',tostring(best)) end
    end
  end
end
function on_button(key,down)
  if not down then return end
  if mode=='title' and key=='a' then mode='play'
  elseif mode=='over' and key=='down' then mode='qr'
  elseif mode=='qr' and (key=='b' or key=='up') then mode='over' end
end
function on_draw()
  g.clear(mode=='qr' and g.WHITE or g.BLACK)
  if mode=='qr' then
    local px=math.floor(216/(QR.size+8))
    local left=(320-px*(QR.size+8))//2
    local top=(216-px*(QR.size+8))//2
    for y,row in ipairs(QR.rows) do
      local x=1
      while x<=QR.size do
        if row:sub(x,x)=='1' then
          local a=x
          while x<=QR.size and row:sub(x,x)=='1' do x=x+1 end
          g.fill_rect(left+(a+3)*px,top+(y+3)*px,(x-a)*px,px,g.BLACK)
        else x=x+1 end
      end
    end
    g.text_center('Screen Solana addresses with Range',160,222,g.BLACK,1)
  else g.text(mode=='over' and 'RANGE ALERT' or mode,0,0,g.WHITE) end
end
function __state()
  local a,p={},{}
  local alive=0
  for j,v in ipairs(aliens) do
    a[j]={type=v.type,name=v.name,hits_left=v.hits_left,alive=v.alive}
    if v.alive then alive=alive+1 end
  end
  for j,v in ipairs(popups) do p[j]=v end
  return {mode=mode,score=score,best=best,lives=lives,wave=1,alive=alive,
    aliens=a,popups=p,killer=nil,breached=0,boss=nil}
end
