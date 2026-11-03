local w=(...)[60]
for i=2,59 do
  local p=w[i]
  if p then p:remove(); w[i]=nil end
end
