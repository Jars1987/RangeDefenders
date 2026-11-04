-- Tiny lifecycle/radio fixture; the production scenarios never select this.
local mode,tx,received='title',0,0
function on_start() badge.espnow.enable(true); badge.led.take() end
function on_update() end
function on_button(key,down) if down and key=='a' then mode='radar' end end
function on_draw() badge.gfx.clear(); badge.gfx.text(mode,0,0,badge.gfx.WHITE) end
function on_espnow(mac,data,rssi)
  assert(mac~='' and type(data)=='string' and rssi<0)
  received=received+1
end
function __state()
  return {mode=mode,st='C',hop=0,exposure=0,credits=3,score=0,best=0,
    round='00000000',remain=0,latent=false,pending=nil,roster=received,
    screened={},result=nil,children=0,tx=tx,last_msg=''}
end
