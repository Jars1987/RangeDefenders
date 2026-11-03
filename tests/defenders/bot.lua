-- Reads visible widgets, controls the game through on_key only.
local M={}
local function alien(h,o)
  if o.kind~='label' or not o.visible or o.removed then return false end
  local g=h.state and h.state[61]
  if not g then return false end
  for r=1,4 do if o.text_value==g[r*2-1]..'\n'..g[r*2] then return true end end
  return false
end
function M.step(h,mode)
  local player=h:find('/^\\')
  if not player then h:tick(); return end
  local target,lowest
  if mode=='boss' then target=h:find('<o_o_oo_o_o>') end
  if not target and mode~='boss' then
    for _,o in ipairs(h.objects) do
      if alien(h,o) and (not lowest or o.y>lowest.y or (o.y==lowest.y and math.abs(o.x-player.x)<math.abs(lowest.x-player.x))) then
        lowest={x=o.x,y=o.y,widget=o}
      end
    end
    target=lowest
  end
  local goal=2
  if target then
    local widget=target.widget or target
    local prev=h.bot_previous and h.bot_previous[widget]
    local velocity=prev and widget.x-prev or 0
    local flight=(182-target.y)/11
    goal=target.x+(target.widget and 10 or 33)-9+velocity*flight
  end
  h.bot_previous=h.bot_previous or {}
  for _,o in ipairs(h.objects) do if alien(h,o) or o.text_value=='<o_o_oo_o_o>' then h.bot_previous[o]=o.x end end
  if player.x<goal-3 then h:key('right',true)
  elseif player.x>goal+3 then h:key('left',true) end
  h:tick()
end
function M.until_true(h,predicate,limit,mode)
  for _=1,limit do
    if predicate(h) then return end
    M.step(h,mode)
  end
  assert(predicate(h),'bot did not reach goal after '..limit..' ticks')
end
function M.breach(h)
  for _=1,40 do h:key('left',true) end
  for _=1,6000 do
    if h:has('RANGE ALERT') then return end
    h:tick()
  end
  error('formation did not breach')
end
return M
