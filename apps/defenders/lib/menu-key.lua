local s,_,key,rep=...
if rep then return true end
if s[57]=="title" then
  if key=="select" then s[56]=true
  elseif key=="right" then s[57]="about"
  elseif key=="back" then return false end
elseif key=="back" then s[57]="title" end
s[20]=true
return true
