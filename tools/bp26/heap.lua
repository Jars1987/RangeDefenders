-- Isolated host heap estimate. Compiled prototypes are excluded to approximate XIP.
local Stub=dofile('tools/bp26/badge_stub.lua')
local n=tonumber(arg[1]) or 20
local peers={}
for j=1,n-1 do peers[#peers+1]={id='B'..j,n='@investigator'..j,band='close',age_s=0}end
local state={ok=true,online=true,big_drop_in_s=59,nearby=peers,awards={},room={id='12345678',phase='active',role='investigator',status='tainted',heat=99,credits=3,in_s=240,ranked=true,pot=100,count=n,drained=0,threshold=12}}
local b={nearby=function()local out={}for _,p in ipairs(peers)do out[#out+1]={id=p.id,kind='badge',rssi=-50}end return out end,send=function()end,http=function(self,id,url,body)
 if url:find('/hello',1,true)then return {status=200,body={ok=true,welcome={amount=0,eligible=false},big_drop_in_s=59}}end
 if url:find('/share',1,true)then return {status=200,body={ok=true,url='https://r.test/r/123456'}}end
 return{status=200,body=state}
end}
local p=Stub.new('B0',b)p.heap_mode=true
for _=1,300 do p:tick(50)end
p:key('left')for _=1,10 do p:tick(50)end p:key('back')p:key('back')p:key('down')for _=1,50 do p:tick(50)end
assert(p.max_heap<48,'estimated flash heap exceeds 48 KB: '..p.max_heap)
print(string.format('%.1f',p.max_heap))
