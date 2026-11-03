-- Solana OS 0.5.5. Use tools/bp26/set-server.sh before publishing.
local SERVER = "https://example.trycloudflare.com"
local SHORT_ORIGIN = "https://rng.example"
local mode, online, closed = "title", false, false
local state, welcome, drop, received = {}, 0, 3600, 0
local initialized = false
local now, next_poll, next_mesh, paint = 0, 0, 0, 0
local flight, serial, pending, retry_at = nil, 0, nil, 0
local selected, notice, qr, practice, elapsed = nil, "Loading", nil, nil, 0
local mint, mint_at, mint_busy = storage.get("mint"), 0, false
local name, x = badge.owner() or "Hunter", nil
local labels, radar = {}, {}
ui.bg(0x0B1318)
for i = 1, 9 do
  labels[i] = ui.label(10, 8 + (i - 1) * 21, "", {size=i == 1 and 20 or 14, w=300, color=i == 1 and "green" or "text"})
end
local function clean(s, n)
  return tostring(s or ""):gsub("[^ -~]", "?"):sub(1, n or 40)
end
local function op()
  return string.format("%08x%08x", math.random(1, 2147483646), math.random(1, 2147483646))
end
local function hide_qr()
  if qr then qr:remove() qr = nil end
end
local function show_qr(url)
  if not ui.qr then ui.toast("Update Solana OS for QR") return end
  hide_qr()
  for _, l in ipairs(labels) do l:show(false) end
  qr = ui.qr(60, 0, 196, url)
  mode = "qr"
  ui.hint("CANCEL back")
end
local function index()
  for i, p in ipairs(radar) do if p.id == selected then return i end end
  selected = radar[1] and radar[1].id or nil
  return 1
end
local function room() return practice and practice.room or state.room end
local function queue(path, body, kind)
  if pending then ui.toast("Wait") return end
  pending = {path=path, body=body, kind=kind}
  retry_at = now
end
local function act(action, target, id)
  queue("/v1/lazarus/action", {action=action, target=target, id=id, op=op()}, action)
end
local function share(kind, direct)
  if online and not practice and not direct then queue("/v1/share", {app="lazarus",kind=kind or "install",data={}}, "share")
  else show_qr(SHORT_ORIGIN .. "/go/install?a=lazarus") end
end
local function apply(r)
  state, drop, received = r, r.big_drop_in_s or drop, now
  radar = r.nearby or {}
  index()
  if r.screen then
    if r.screen.clue then
      local c = r.screen.clue
      notice = "Caught it from " .. clean(c.name, 15) .. " " .. clean(c.sid or c.id:sub(-4), 4)
    else notice = r.screen.result end
  end
  local rr = r.room
  if rr and mode ~= "qr" and mode ~= "practice" then mode = rr.phase == "ended" and "result" or "radar" end
end
local function complete(kind, body, r)
  if kind == "hello" then
    initialized = true
    welcome = r.welcome and r.welcome.amount or 0
    drop, received = r.big_drop_in_s or drop, now
    notice = r.msg and clean(r.msg) or "Link X to earn !LAMPs"
    if not mint and not storage.get("welcome_award") and (welcome > 0 or storage.get("welcome_op")) then
      local id = storage.get("welcome_op") or op()
      storage.set("welcome_op", id)
      queue("/v1/welcome/claim", {app="lazarus", op=id}, "welcome")
    end
  elseif kind == "welcome" or kind == "claim" then
    local marker = kind == "welcome" and "welcome_award" or "award_" .. body.id
    if r.amount and r.amount > 0 and storage.get(marker) ~= "done" then
      mint = {r.amount, kind == "welcome" and "Welcome to Lazarus" or "Quarantine", marker}
      storage.set("mint", mint)
      mint_at = now
    end
  elseif kind == "share" then show_qr(r.url)
  elseif kind == "leave" then state.room = nil mode = "title"
  else
    apply(r)
    if r.awards and r.awards[1] and not pending and not mint then
      act("claim", nil, r.awards[1].id)
    end
  end
end
local function request(path, body, kind)
  serial = serial + 1
  local token, work = serial, pending
  flight = {id=token, at=now}
  http.post(SERVER .. path, body, function(ok, response)
    if closed or not flight or flight.id ~= token then return end
    flight = nil
    local r = ok and response.status == 200 and not response.truncated and json.decode(response.body)
    if not r or not r.ok then
      online = false
      notice = "Offline - DOWN practice"
      if ok and response.status == 400 then
        local err = not response.truncated and json.decode(response.body)
        local messages = {not_nearby="Move closer", no_credits="No credits",
          not_active="Not active", not_preparing="Already started",
          disconnected="Reconnect first", no_round="No round",
          bad_target="Choose a badge", role_denied="Stay moving",
          already_playing="Still playing"}
        notice = messages[err and err.error] or "Try again"
        online = true
        if kind == "share" and err and err.error == "short_origin_required" then
          share(nil, true)
        end
        if pending == work then pending = nil end
      end
      retry_at = now + 5000
      return
    end
    online = true
    if pending == work then pending = nil end
    next_poll = now + 5000
    complete(kind, body, r)
  end)
end
local function observations()
  local out = {}
  for _, p in ipairs(mesh.nearby()) do
    if #out >= 20 then break end
    if p.kind == "badge" and not p.bridged and p.rssi and p.rssi < 0 then
      out[#out + 1] = {id=p.id, rssi=p.rssi}
    end
  end
  return out
end
local function start_practice()
  hide_qr()
  mode, selected, elapsed = "practice", "p1", 0
  practice = {room={phase="active", role="investigator", status="clean", credits=2, heat=0, in_s=90, ranked=false}, peers={
    {id="p1",n="Relay",band="close",tainted=true,upstream="p2"},
    {id="p2",n="Broker",band="close",tainted=true,upstream="p3"},
    {id="p3",n="Wallet 3",band="close",source=true},
    {id="p4",n="Wallet 4",band="near"}, {id="p5",n="Wallet 5",band="near"}}}
  radar = practice.peers
  notice = "Practice - no rewards"
end
local function practice_screen()
  local rr, p = practice.room, radar[index()]
  if rr.credits < 1 then notice = "No credits" return end
  rr.credits = rr.credits - 1
  if p.source then rr.phase, rr.result, mode = "ended", "CAUGHT", "result" notice = "Lazarus caught"
  elseif p.tainted then
    p.tainted = false
    notice = "Caught it from " .. p.upstream
    selected = p.upstream
  else p.age_s=0 notice="CLEAN" end
end
local function render()
  local rr = room()
  local left = math.max(0, drop - ((now - received) // 1000))
  if rr and rr.status == "tainted" then led.fill(190, 0, 0)
  elseif (rr and rr.phase == "preparing") or (mode == "title" and left <= 60) then
    local level = math.floor(20 + 60 * (1 + math.sin(now / 400)))
    led.fill(0, level, math.floor(level / 2))
  else led.off() end
  if mode == "qr" then return end
  for _, l in ipairs(labels) do l:text("") l:show(true) end
  if mode == "title" then
    labels[1]:text("Catch Lazarus, win !LAMPs")
    labels[2]:text("SELECT join (need 4 nearby)")
    labels[3]:text("Screen a badge, follow clues")
    labels[4]:text(string.format("Big Drop in %02d:%02d", left // 60, left % 60))
    labels[5]:text("DOWN practice  RIGHT QR")
    labels[7]:text(welcome > 0 and ("Welcome: " .. welcome .. " !LAMPs") or "")
    labels[8]:text(online and notice or "Offline - DOWN practice")
    ui.hint("SELECT join  DOWN practice")
  elseif mode == "result" then
    labels[1]:text(rr and rr.result or "Round ended")
    labels[2]:text(practice and "Practice - no rewards" or (rr and rr.winner and ("Winner: " .. clean(rr.winner, 24)) or "No prize"))
    labels[3]:text(rr and rr.result == "VOID" and (rr.reason == "Lazarus left" and "Round cancelled - Lazarus left" or "Round cancelled - signal lost") or notice)
    labels[7]:text("RIGHT QR")
    ui.hint("SELECT rematch  CANCEL title")
  else
    labels[1]:text(rr and rr.role == "lazarus" and "You are Lazarus" or "Screen nearby. Follow clues.")
    if rr then
      if rr.phase == "preparing" then
        labels[2]:text(rr.role == "lazarus" and ("SELECT to accept  " .. rr.in_s .. "s") or ("Hunt starts in " .. rr.in_s .. "s"))
        labels[3]:text(rr.role == "lazarus" and "Stay moving. Do not get screened." or "Wait. Lazarus must accept.")
      else
        labels[2]:text(string.format("%s  HEAT %d%%  %d credits", string.upper(rr.status), rr.heat, rr.credits))
        labels[3]:text(rr.role == "lazarus" and ("Drained " .. rr.drained .. "/" .. rr.threshold) or rr.in_s .. "s")
      end
    else labels[2]:text("4 badges: open app + SELECT") end
    local idx = index()
    for offset = 0, 3 do
      local p = radar[((idx - 1 + offset) % math.max(1, #radar)) + 1]
      if p then labels[4 + offset]:text((offset == 0 and "> " or "  ") .. clean(p.n, 12) .. " " .. (p.sid or p.id:sub(-4)) .. " " .. p.band .. (offset == 0 and p.age_s and (" " .. p.age_s .. "s ago") or "")) end
    end
    labels[8]:text(practice and "Practice - no rewards" or (online and notice or "Offline"))
    labels[9]:text(rr and rr.heat > 50 and "Spread out or Lazarus escapes" or rr and rr.ranked and "Prize round" or "Unranked")
    ui.hint("SELECT screen  RIGHT quarantine")
  end
end
function on_key(key, rep)
  if rep and key ~= "up" and key ~= "down" then return true end
  if mode == "qr" then
    if key == "back" then hide_qr() mode = room() and (room().phase == "ended" and "result" or "radar") or "title" end
  elseif mode == "title" then
    if key == "down" or (key == "select" and not online) then start_practice()
    elseif key == "select" then mode = "radar" act("ready")
    elseif key == "right" then
      share()
    elseif key == "back" then sys.exit() end
  elseif mode == "result" then
    if key == "select" then
      if practice then start_practice() else mode = "radar" act("ready") end
    elseif key == "back" then practice = nil radar = state.nearby or {} mode = "title"
    elseif key == "right" then
      local rr = room()
      share(not practice and rr and rr.winner == name and (rr.result == "CAUGHT" and "caught" or "escaped") or "install")
    end
  else
    if key == "up" or key == "down" then
      local list = radar
      if #list > 0 then selected = list[(index() + (key == "down" and 0 or -2)) % #list + 1].id end
    elseif key == "select" then
      if practice then practice_screen()
      elseif room() and room().phase == "preparing" then act("ack")
      elseif selected then act("screen", selected) end
    elseif key == "left" then
      share()
    elseif key == "right" and room() and room().status == "tainted" then
      if practice then practice.room.status = "quarantined" else act("quarantine") end
    elseif key == "back" then
      if practice then practice = nil radar = state.nearby or {} mode = "title"
      else ui.confirm("Leave this round?", function(yes) if yes then act("leave") mode = "title" end end) end
    end
  end
  render()
  return true
end
function on_tick(ms)
  now = sys.millis()
  if closed then return end
  if mint and not mint_busy and now >= mint_at then
    mint_busy = true
    local a = mint
    lamps.award(a[1], a[2], function(ok, r)
      mint_busy = false
      if closed then return end
      if ok and (r.awarded or 0) > 0 then
        storage.set(a[3], "done") storage.remove("mint") mint = nil
        ui.toast("+" .. r.awarded .. " !LAMPs")
      else
        notice = ok and (r.needsX and "Link X to earn !LAMPs" or "Reward cap reached") or r == "denied" and "Award denied" or "Award pending"
        ui.toast(notice)
        mint_at = now + ((not ok and (r == "offline" or r == "denied")) and 5000 or 30000)
        if not ok and r ~= "offline" and r ~= "denied" then mint_at = math.huge end
      end
    end)
  end
  if flight and now - flight.at > 7000 then flight = nil online = false retry_at = now + 1000 end
  if practice and practice.room.phase == "active" then
    elapsed = elapsed + ms
    practice.room.in_s = math.max(0, 90 - (elapsed // 1000))
    practice.room.heat = math.min(100, (elapsed // 600))
    if elapsed >= 60000 and practice.room.status == "clean" then practice.room.status = "tainted" end
    if (elapsed // 20000) > ((elapsed - ms) // 20000) then practice.room.credits = math.min(3, practice.room.credits + 1) end
    if elapsed >= 90000 then practice.room.phase, practice.room.result, mode = "ended", "ESCAPED", "result" end
  end
  if state.room and not practice and now - received >= 1000 then
      local seconds = ((now - received) // 1000)
      state.room.in_s = math.max(0, state.room.in_s - seconds)
      drop, received = math.max(0, drop - seconds), received + seconds * 1000
  end
  if now >= next_mesh and not practice then
    mesh.send("*", {v=1, app="range-lazarus"})
    next_mesh = now + 2000 + math.random(0, 350)
  end
  if not flight and now >= retry_at and not practice then
    if pending then request(pending.path, pending.body, pending.kind)
    elseif initialized and now >= next_poll then request("/v1/lazarus/poll", {nearby=observations()}, "poll") end
  end
  if now >= paint then render() paint = now + 250 end
end
function on_exit()
  closed = true
  led.off()
end
profile.me(function(ok, p)
  if ok then name, x = clean(p.name or name, 20), p.x end
  queue("/v1/hello", {app="lazarus",name=name,x=x,v="1.0.0"}, "hello")
end)
render()
