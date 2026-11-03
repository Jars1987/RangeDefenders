local score,id,day,wave=...
local text=score.."|"..(id or "anon").."|"..(day or 0).."|"..wave.."|sd1"
local h=0x811c9dc5
for i=1,#text do h=((h ~ text:byte(i))*0x01000193) & 0xffffffff end
local alphabet="0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local code=""
for i=1,6 do
  local n=(h & 31)+1
  code=alphabet:sub(n,n)..code; h=h >> 5
end
return code
