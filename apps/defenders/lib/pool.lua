local w=(...)[60]
for i=14,83 do
  local p=w[i]
  if p then p:remove(); w[i]=nil end
end
