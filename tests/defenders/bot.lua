-- Reads visible widgets, controls the game through on_key only.
local M={}
local glyphs={['<W>']=true,['{V}']=true,['(@)']=true,['[v]']=true}
function M.step(h,mode)
  local player=h:find('/^\\')
  if not player then h:tick(); return end
  local target,lowest
  if mode=='boss' then target=h:find('<LAZARUS>') end
  if not target and mode~='boss' then
    for _,o in ipairs(h.objects) do
      if o.visible and glyphs[o.text_value] then
        if not lowest or o.y>lowest.y or (o.y==lowest.y and math.abs(o.x-player.x)<math.abs(lowest.x-player.x)) then lowest=o end
      end
    end
    target=lowest
  end
  local goal=2
  if target then
    local prev=h.bot_previous and h.bot_previous[target]
    local velocity=prev and target.x-prev or 0
    local flight=(182-target.y)/11
    goal=target.x+(target.text_value=='<LAZARUS>' and 33 or 10)-9+velocity*flight
  end
  h.bot_previous=h.bot_previous or {}
  for _,o in ipairs(h.objects) do if o.visible and (glyphs[o.text_value] or o.text_value=='<LAZARUS>') then h.bot_previous[o]=o.x end end
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
