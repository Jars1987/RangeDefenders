-- Solana OS 0.5.5. Change SERVER and app.json hosts together before publishing.
local SERVER = "https://example.trycloudflare.com"
local mode, online, closed = "title", false, false
local state, welcome, drop, received = {}, 0, 3600, 0
local initialized = false
local now, next_poll, next_mesh, paint = 0, 0, 0, 0
local flight, serial, pending, retry_at = nil, 0, nil, 0
local selected, notice, qr, practice, elapsed = nil, "Connecting...", nil, nil, 0
local clean_at = nil
local name, x = badge.owner() or "Investigator", nil
local labels = {}
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
  hide_qr()
  for _, l in ipairs(labels) do l:show(false) end
  qr = ui.qr(60, 0, 196, url)
  mode = "qr"
  ui.hint("CANCEL back")
end
local function peers() return practice and practice.peers or (state.nearby or {}) end
local function index()
  for i, p in ipairs(peers()) do if p.id == selected then return i end end
  selected = peers()[1] and peers()[1].id or nil
  return 1
end
local function room() return practice and practice.room or state.room end
local function queue(path, body, kind)
  if pending then ui.toast("Action pending") return end
  pending = {path=path, body=body, kind=kind}
  retry_at = now
end
local function act(action, target, id)
  queue("/v1/lazarus/action", {action=action, target=target, id=id, op=op()}, action)
end
local function award(amount, reason, marker)
  if not amount or amount <= 0 then return end
  -- Keep an attempted award on disk before crossing the asynchronous OS boundary.
  if storage.get(marker) == "done" then return end
  storage.set(marker, "done")
  lamps.award(amount, reason, function(ok, r)
    if ok and r.needsX then
      storage.remove(marker)
      notice, clean_at = "Link X to earn !LAMPs", nil
      ui.toast(notice)
    elseif ok and (r.awarded or 0) > 0 then
      ui.toast("+" .. tostring(r.awarded) .. " !LAMPs")
    else notice, clean_at = "Reward cap reached", nil end
  end)
end
local function apply(r)
  state, drop, received = r, r.big_drop_in_s or drop, now
  index()
  if r.screen then
    clean_at = r.screen.result == "CLEAN" and now or nil
    if r.screen.clue then
      local c = r.screen.clue
      notice = "Caught it from " .. clean(c.name, 15) .. " " .. clean(c.id, 6)
    else notice = r.screen.result .. (r.screen.result == "CLEAN" and " (now)" or "") end
  end
  local rr = r.room
  if rr and mode ~= "qr" and mode ~= "practice" then mode = rr.phase == "ended" and "result" or "radar" end
end
local function complete(kind, body, r)
  if kind == "hello" then
    initialized = true
    welcome = r.welcome and r.welcome.amount or 0
    drop, received = r.big_drop_in_s or drop, now
    notice = r.msg and clean(r.msg) or "Link X to earn"
    if r.welcome and r.welcome.eligible and not storage.get("welcome_award") then
      local id = storage.get("welcome_op") or op()
      storage.set("welcome_op", id)
      queue("/v1/welcome/claim", {app="lazarus", op=id}, "welcome")
    elseif storage.get("welcome_op") and not storage.get("welcome_award") then
      queue("/v1/welcome/claim", {app="lazarus", op=storage.get("welcome_op")}, "welcome")
    end
  elseif kind == "welcome" then award(r.amount, "Welcome to Lazarus", "welcome_award")
  elseif kind == "claim" then award(r.amount, "Quarantine bonus", "award_" .. body.id)
  elseif kind == "share" then show_qr(r.url)
  elseif kind == "leave" then state.room = nil mode = "title"
  else
    apply(r)
    if r.awards and r.awards[1] and not pending then
      act("claim", nil, r.awards[1].id)
    end
  end
end
local function request(path, body, kind)
  serial = serial + 1
  local token = serial
  local work = pending
  flight = {id=token, at=now}
  http.post(SERVER .. path, body, function(ok, response)
    if closed or not flight or flight.id ~= token then return end
    flight = nil
    local r = ok and response.status == 200 and not response.truncated and json.decode(response.body)
    if not r or not r.ok then
      online = false
      notice = "Offline - Practice available"
      if ok and response.status == 400 then
        local err = not response.truncated and json.decode(response.body)
        local messages = {not_nearby="Move closer", no_credits="No credits",
          not_active="Round not active", not_preparing="Round already started",
          disconnected="Reconnect before screening", no_round="Waiting for players",
          bad_target="Choose a nearby badge", role_denied="Avoid being screened",
          already_playing="Round in progress"}
        notice, clean_at = messages[err and err.error] or "Action failed", nil
        online = true
        if kind == "share" and err and err.error == "short_origin_required" then
          show_qr(SERVER .. "/go/install?a=lazarus")
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
  practice = {room={phase="active", role="investigator", status="clean", credits=1, heat=0, in_s=90, ranked=false}, peers={
    {id="p1",n="Relay",band="close",tainted=true,upstream="p2"},
    {id="p2",n="Broker",band="close",tainted=true,upstream="p3"},
    {id="p3",n="Lazarus",band="close",source=true},
    {id="p4",n="Wallet 4",band="near"}, {id="p5",n="Wallet 5",band="near"}}}
  notice, clean_at = "Practice - no rewards", nil
end
local function practice_screen()
  local rr, p = practice.room, peers()[index()]
  if rr.credits < 1 then notice = "No credits" return end
  rr.credits = rr.credits - 1
  if p.source then rr.phase, rr.result, mode = "ended", "CAUGHT", "result" notice = "Lazarus caught"
  elseif p.tainted then
    p.tainted = false
    notice = "Caught it from " .. p.upstream
    selected = p.upstream
  else notice, clean_at = "CLEAN (now)", now end
end
local function render()
  local rr = room()
  local left = math.max(0, drop - math.floor((now - received) / 1000))
  if rr and rr.status == "tainted" then led.fill(190, 0, 0)
  elseif (rr and rr.phase == "preparing") or (mode == "title" and left <= 60) then
    local level = math.floor(20 + 60 * (1 + math.sin(now / 400)))
    led.fill(0, level, math.floor(level / 2))
  else led.off() end
  if mode == "qr" then return end
  if clean_at then notice = "CLEAN (" .. math.floor((now - clean_at) / 1000) .. "s ago)" end
  for _, l in ipairs(labels) do l:text("") l:show(true) end
  if mode == "title" then
    labels[1]:text("Lazarus In The Room")
    labels[2]:text("Catch Lazarus, win !LAMPs")
    labels[3]:text("Big Drop every hour at :00")
    labels[4]:text(string.format("Next drop %02d:%02d", math.floor(left / 60), left % 60))
    labels[5]:text(welcome > 0 and ("Welcome: " .. welcome .. " !LAMPs") or "Link X to earn")
    labels[6]:text("6+ prize / 4-5 unranked")
    labels[7]:text("Open this app to play")
    labels[8]:text(online and notice or "Offline - Practice available")
    labels[9]:text("RIGHT Install / share")
    ui.hint("SELECT ready  DOWN Practice")
  elseif mode == "result" then
    labels[1]:text(rr and rr.result or "Round ended")
    labels[2]:text(practice and "Practice - no rewards" or (rr and rr.winner and ("Winner: " .. clean(rr.winner, 24)) or "No escape prize"))
    labels[3]:text(rr and rr.reason and clean(rr.reason) or notice)
    labels[5]:text("Follow the money. Catch Lazarus.")
    labels[7]:text("RIGHT result / install QR")
    ui.hint("SELECT rematch  CANCEL title")
  else
    labels[1]:text(practice and "Practice" or (rr and (rr.role == "lazarus" and "You are Lazarus" or "Investigator") or "Finding players"))
    if rr then
      labels[2]:text(rr.phase == "preparing" and ("Ready in " .. rr.in_s .. "s" .. (rr.role == "lazarus" and not rr.ack and " - SELECT accept" or "")) or (rr.status == "quarantined" and "Funds quarantined" or string.upper(rr.status)) .. " / " .. rr.in_s .. "s")
      labels[3]:text(rr.role == "lazarus" and ("Drained " .. rr.drained .. "/" .. rr.threshold) or ("HEAT " .. rr.heat .. "% / Credits " .. rr.credits))
    else labels[2]:text("Waiting for 4+ ready players") end
    local idx = index()
    for offset = 0, 3 do
      local p = peers()[((idx - 1 + offset) % math.max(1, #peers())) + 1]
      if p then labels[4 + offset]:text((offset == 0 and "> " or "  ") .. clean(p.n, 14) .. " " .. clean(p.id, 6) .. " " .. p.band) end
    end
    labels[8]:text(practice and "Practice - no rewards" or (online and notice or "Offline - actions paused"))
    labels[9]:text(rr and rr.ranked and "Prize round" or "Unranked")
    ui.hint("UP/DOWN target SELECT screen")
  end
end
function on_key(key, rep)
  if rep and key ~= "up" and key ~= "down" then return true end
  if mode == "qr" then
    if key == "back" then hide_qr() mode = room() and (room().phase == "ended" and "result" or "radar") or "title" end
  elseif mode == "title" then
    if key == "down" then start_practice()
    elseif key == "select" then
      if online then mode = "radar" act("ready") else start_practice() end
    elseif key == "right" then
      if online then queue("/v1/share", {app="lazarus",kind="install",data={}}, "share")
      else show_qr(SERVER .. "/go/install?a=lazarus") end
    elseif key == "back" then sys.exit() end
  elseif mode == "result" then
    if key == "select" then
      if practice then start_practice() else mode = "radar" act("ready") end
    elseif key == "back" then practice = nil mode = "title"
    elseif key == "right" then
      if not practice and online then
        local rr = room()
        local kind = rr and rr.winner == name and (rr.result == "CAUGHT" and "caught" or "escaped") or "install"
        queue("/v1/share", {app="lazarus",kind=kind,data={}}, "share")
      else show_qr(SERVER .. "/go/install?a=lazarus") end
    end
  else
    if key == "up" or key == "down" then
      local list = peers()
      if #list > 0 then selected = list[((index() - 1 + (key == "down" and 1 or -1)) % #list) + 1].id end
    elseif key == "select" then
      if practice then practice_screen()
      elseif room() and room().phase == "preparing" then act("ack")
      elseif selected then act("screen", selected) end
    elseif key == "left" then
      if online then queue("/v1/share", {app="lazarus",kind="install",data={}}, "share")
      else show_qr(SERVER .. "/go/install?a=lazarus") end
    elseif key == "right" and room() and room().status == "tainted" then
      if practice then practice.room.status = "quarantined" else act("quarantine") end
    elseif key == "back" then
      if practice then practice = nil mode = "title"
      else ui.confirm("Leave this round?", function(yes) if yes then act("leave") mode = "title" end end) end
    end
  end
  render()
  return true
end
function on_tick(ms)
  now = sys.millis()
  if closed then return end
  if flight and now - flight.at > 7000 then flight = nil online = false retry_at = now + 1000 end
  if practice and practice.room.phase == "active" then
    elapsed = elapsed + ms
    practice.room.in_s = math.max(0, 90 - math.floor(elapsed / 1000))
    practice.room.heat = math.min(100, math.floor(elapsed / 600))
    if elapsed >= 60000 and practice.room.status == "clean" then practice.room.status = "tainted" end
    if math.floor(elapsed / 20000) > math.floor((elapsed - ms) / 20000) then practice.room.credits = math.min(3, practice.room.credits + 1) end
    if elapsed >= 90000 then practice.room.phase, practice.room.result, mode = "ended", "ESCAPED", "result" end
  end
  if state.room and not practice then
    if now - received >= 1000 then
      local seconds = math.floor((now - received) / 1000)
      state.room.in_s = math.max(0, state.room.in_s - seconds)
      drop, received = math.max(0, drop - seconds), received + seconds * 1000
    end
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
function on_mesh(from, msg)
  -- Presence is neutral for every role. Mesh never conveys taint or clues.
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
