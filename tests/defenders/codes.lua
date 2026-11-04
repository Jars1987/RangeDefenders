-- Emit the actual badge implementation's results for the JS verifier test.
local json=dofile('tests/defenders/json.lua')
local f=assert(io.open('tests/defenders/code-vectors.json'))
local vectors=assert(json.decode(f:read('*a'))); f:close()
local code=assert(loadfile('apps/defenders/lib/code.lua'))
for _,v in ipairs(vectors) do
  local actual=code(v.score,v.day)
  assert(actual==v.code,'Lua fixture mismatch')
  print(actual)
end
