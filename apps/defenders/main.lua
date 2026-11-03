local WELCOME = 25
local LAUNCH_TWEET_ID = ""
-- Dense state slots keep gameplay tables small. Phase code uses fs.load.
local s={[54]=LAUNCH_TWEET_ID,[57]="title",[49]=0,[62]=1,[31]=3,[42]=147,
  [4]=tonumber(storage.get("best")) or 0,[60]={},[12]={},[13]={},[5]={},[27]={3,3,3},[23]=0}
assert(fs.load("lib/init.lua"))(s)
assert(fs.load("lib/callbacks.lua"))(s)
local welcome=storage.get("welcome")
if welcome~=true and not (type(welcome)=="table" and welcome.done) then
  lamps.award(WELCOME,"Welcome to Solana Defenders",function(ok,r)
    if s[15] then return end
    if ok and type(r)=="table" then
      if type(r.awarded)=="number" and r.awarded>0 then storage.set("welcome",true)
      elseif r.needsX then s[14]=true; ui.toast("Link X to earn !LAMPs"); s[20]=true end
    end
  end)
end

-- Slots: 1=alive, 2=day, 3=today, 4=best, 5=shot_names, 6=boss_cd,
-- 7=boss_dir, 8=boss_hp, 9=boss_killed, 10=boss_x, 12=bx, 13=by,
-- 14=needsX, 15=closed, 16=repost, 19=dir, 20=dirty, 21=finish, 22=fire_cd,
-- 23=flash, 24=fx, 25=fy, 27=hp, 28=killer, 31=lives, 32=mask, 33=names,
-- 34=new_best, 39=play, 41=popup_cd, 42=px, 49=score, 53=tweet_url,
-- 54=launch_tweet_id, 55=shot_cd, 56=start, 57=state, 60=widgets, 62=wave.
