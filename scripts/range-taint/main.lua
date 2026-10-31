-- Taint by Range: trace stolen funds badge to badge.
local g, input, led = badge.gfx, badge.input, badge.led
local net, kv = badge.espnow, badge.storage.kv

-- BEGIN GENERATED QR
local QR = { url = "https://www.range.org/product/transaction-screening?utm_source=event-breakpoint&utm_medium=qr&utm_campaign=always-on&utm_content=badge-taint", size = 45, rows = {
  "111111100011011000001001001001111100101111111",
  "100000100100011011010011101110010001001000001",
  "101110100011010011011001110011011101001011101",
  "101110101111011001100100011111101101101011101",
  "101110101010001101011111110111101011101011101",
  "100000100011100001101000111100011000001000001",
  "111111101010101010101010101010101010101111111",
  "000000000001010100111000111011011111100000000",
  "110001110110100001111111101001010010000011000",
  "001010001010111010001100001111110111101101110",
  "101100101001000001101111101111000010001001110",
  "111000001001001001100101110010101111010111100",
  "100110111110001000101100111110101010001010001",
  "001100010011111101010100010011111101110100111",
  "101111101001011110111101101010010001101110110",
  "111111010000100101111010010001100011110101100",
  "000110101010011101111011010000110110001001010",
  "111111001011000110011100010001110100110111111",
  "000001101110011101110000100010001100100011101",
  "100110010101101110010000111011001111111011100",
  "110011111111110111111111110000110011111110010",
  "011110001111000110011000111101111111100010100",
  "000110101110100000011010110011001111101011000",
  "101010001101110101101000100110111100100010100",
  "100111111011111010101111100011001001111110001",
  "011101010011010000001111110111100001010101011",
  "000000100100010000101010001100010110100101110",
  "110001010101011011000111110001100011010111101",
  "101001110010010111110001111001010010000011101",
  "101011000111101100011011110101110101001100011",
  "011001101010000100011000010001011101101001001",
  "001110000001001100001111100010101111101100101",
  "001001101111111101100000011001110010111110011",
  "010001011010101101010101011111110111111111000",
  "000010101011100111100100011100011010110001010",
  "011110010110110111101011100010101001011101100",
  "100110111111001001111111100110101011111111000",
  "000000001011101101001000110111100100100011001",
  "111111101010100001111010101101000111101011010",
  "100000101110111110111000101001000011100010111",
  "101110100110100100101111101000010101111110001",
  "101110100111010000110101110111101101000111000",
  "101110100101010110011100110110011000101010110",
  "100000101011011001111100011110011111110111100",
  "111111101111010111110001111001110000101010010"
} }
-- END GENERATED QR

local ROUND_S, LATENT_S, CONTAIN_S = 180, 20, 15
local EXPOSE_MAX, DECAY, RSSI_FULL, RSSI_NONE = 6, 0.25, -55, -85
local SCREEN_RSSI, FRESH_S, PEER_TTL_S = -82, 2.0, 6
local CREDITS_START, CREDITS_MAX, CREDIT_EVERY_S = 3, 5, 20
local HELLO_T_S, HELLO_S, JITTER_S = 1.0, 1.5, 0.25
local REQ_TIMEOUT_S, REQ_TRIES = 1.2, 3
local CACHE_TTL_S, CACHE_MAX = 10, 32
local TX_BUCKET, TX_REFILL, ENDED_KEEP, PRACTICE_S = 4, 2, 4, 90
local IDLE = "00000000"
local floor, min, max = math.floor, math.min, math.max
local function I(v) return floor(v + 0.5) end
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end
local function count(tab)
  local n = 0
  for _ in pairs(tab) do n = n + 1 end
  return n
end

local t, mode, best, tx = 0.0, "title", 0, 0
local own_mac, LA, LB = "", input.label("a"), input.label("b")
local roster, sorted, ended, queue, cache = {}, {}, {}, {}, {}
local selected, scroll, qr_return = nil, 0, "about"
local tokens, hello_at, req_next = TX_BUCKET, 0.0, 0
local hold_at, hold_fired = nil, false
local practice, leaders = nil, {}

local function context()
  return { id = IDLE, end_t = 0.0, st = "C", hop = 0, exposure = 0.0,
    rate = 0.0, credits = CREDITS_START, credit_at = t + CREDIT_EVERY_S,
    score = 0, children = {}, screened = {}, pending = nil,
    clear_at = nil, result = nil, last_msg = "" }
end
local radio = context()

local function remain(c)
  return clamp(floor(c.end_t - t), 0, c == practice and PRACTICE_S or ROUND_S)
end
local function active() return radio.id ~= IDLE and remain(radio) > 0 end
local function latent(c)
  if c == practice then return t - c.start_t < LATENT_S end
  return c.id ~= IDLE and ROUND_S - (c.end_t - t) < LATENT_S
end
local function current() return practice or radio end
local function seen_end(id)
  for _, e in ipairs(ended) do if e == id then return true end end
  return false
end
local function award(c, points) c.score = min(99999, c.score + points) end

local function reset_round(id, seconds)
  radio = context()
  radio.id, radio.end_t = id, t + seconds
  queue, cache, leaders = {}, {}, {}
  hold_at, hold_fired = nil, false
  for _, p in pairs(roster) do
    p.round, p.st, p.hop, p.score, p.hello_t = nil, nil, nil, nil, nil
  end
  if mode == "end" or (mode == "qr" and qr_return == "end") then mode = "radar" end
  hello_at = t
end

local function capture_leaders(c)
  leaders = {}
  local source = c == practice and c.sims or roster
  for _, p in pairs(source) do
    if c == practice or p.round == c.id then
      leaders[#leaders + 1] = { name = p.name or p.mac:sub(-5), score = p.score or 0 }
    end
  end
  table.sort(leaders, function(a, b)
    if a.score == b.score then return a.name < b.name end
    return a.score > b.score
  end)
  while #leaders > 5 do table.remove(leaders) end
end

local function finish(c, result)
  capture_leaders(c)
  c.result, c.pending, c.clear_at = result, nil, nil
  hold_at, hold_fired = nil, false
  if c ~= practice then
    ended[#ended + 1] = c.id
    while #ended > ENDED_KEEP do table.remove(ended, 1) end
    c.id, c.end_t, c.st, c.hop, c.exposure, c.rate = IDLE, 0.0, "C", 0, 0.0, 0.0
    queue, cache = {}, {}
    hello_at = t
    if c.score > best then
      best = c.score
      kv.set("best", tostring(best))
    end
  end
  mode = "end"
end

-- All transmissions share the same bucket. Only requests, answers and reports queue.
local function remove_request(req)
  for i = #queue, 1, -1 do
    if queue[i].kind == "S" and queue[i].req == req then table.remove(queue, i) end
  end
end
local function transmit(item)
  if practice or tokens < 1 then return false end
  tokens, tx = tokens - 1, tx + 1
  -- Set the deadline before broadcast: a simulator may deliver the reply synchronously.
  local p = radio.pending
  if item.kind == "S" and p and p.req == item.req and p.target == item.target then
    p.sends, p.deadline, p.queued = p.sends + 1, t + REQ_TIMEOUT_S, false
  end
  net.broadcast(item.data)
  return true
end
local function enqueue(item)
  if practice then return end
  if #queue == 0 and transmit(item) then return end
  if #queue == 4 then
    local dropped = table.remove(queue, 1)
    if dropped.kind == "S" and radio.pending and radio.pending.req == dropped.req then
      radio.pending.queued = false
    end
  end
  queue[#queue + 1] = item
end
local function flush_queue()
  while tokens >= 1 and #queue > 0 do
    local item = table.remove(queue, 1)
    if item.kind ~= "S" or (radio.pending and radio.pending.req == item.req
        and radio.pending.target == item.target) then
      transmit(item)
    end
  end
end
local function hello()
  local c = radio
  local wire_st = c.st == "E" and "C" or c.st
  transmit({ kind = "H", data = table.concat({ "RT1", "H", c.id, wire_st,
    tostring(c.hop), tostring(c.score), tostring(remain(c)) }, "|") })
  hello_at = t + (c.st == "T" and HELLO_T_S or HELLO_S) + math.random() * JITTER_S
end

-- Validate the complete frame before allowing any state or roster change.
local function mac_ok(mac)
  return type(mac) == "string" and mac == mac:lower()
    and mac:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil
end
local function integer(s, lo, hi)
  local n = tonumber(s)
  n = n and math.tointeger(n)
  if n and math.type(n) == "integer" and n >= lo and n <= hi then return n end
end
local function parse(data)
  if type(data) ~= "string" or #data > 240 or data:sub(1, 4) ~= "RT1|"
      or data:find("[^\032-\126]") then return end
  local f = {}
  for part in (data .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
  if #f < 3 or #f[3] ~= 8 or not f[3]:match("^[0-9a-f]+$") then return end
  local m = { kind = f[2], round = f[3] }
  if m.kind == "H" and #f == 7 then
    if f[4] ~= "C" and f[4] ~= "T" and f[4] ~= "Q" then return end
    m.st, m.hop, m.score, m.remain = f[4], integer(f[5], 0, 9),
      integer(f[6], 0, 99999), integer(f[7], 0, ROUND_S)
    if not m.hop or not m.score or not m.remain then return end
  elseif m.kind == "S" and #f == 5 then
    m.req, m.target = integer(f[4], 1, 9999), f[5]
    if not m.req or not mac_ok(m.target) then return end
  elseif m.kind == "A" and #f == 7 then
    m.req, m.screener, m.res, m.hop = integer(f[4], 1, 9999), f[5], f[6], integer(f[7], 0, 9)
    if not m.req or not mac_ok(m.screener) or not m.hop
        or (m.res ~= "Q" and m.res ~= "D" and m.res ~= "N") then return end
  elseif m.kind == "P" and #f == 5 then
    m.parent, m.hop = f[4], integer(f[5], 0, 9)
    if not mac_ok(m.parent) or not m.hop then return end
  else
    return
  end
  return m
end

local function expire_roster()
  for mac, p in pairs(roster) do
    if t - p.heard > PEER_TTL_S then roster[mac] = nil end
  end
end
local function touch_peer(mac, rssi)
  expire_roster()
  local p = roster[mac]
  if not p then
    if count(roster) >= 20 then
      local oldest
      for _, e in pairs(roster) do
        if not oldest or e.heard < oldest.heard
            or (e.heard == oldest.heard and e.mac < oldest.mac) then oldest = e end
      end
      roster[oldest.mac] = nil
    end
    p = { mac = mac, rssi = rssi }
    roster[mac] = p
  else
    p.rssi = p.rssi + (rssi - p.rssi) * 0.3
  end
  p.heard = t
  return p
end

local function rebuild_list()
  sorted = {}
  if practice then
    for _, s in ipairs(practice.sims) do sorted[#sorted + 1] = s end
  else
    expire_roster()
    for _, p in pairs(roster) do sorted[#sorted + 1] = p end
  end
  table.sort(sorted, function(a, b)
    if a.rssi == b.rssi then return a.mac < b.mac end
    return a.rssi > b.rssi
  end)
  local index
  for i, p in ipairs(sorted) do if p.mac == selected then index = i end end
  if not index then index = 1; selected = sorted[1] and sorted[1].mac or nil end
  scroll = clamp(scroll, 0, max(0, #sorted - 8))
  if index <= scroll then scroll = index - 1 end
  if index > scroll + 8 then scroll = index - 8 end
end
local function move_selection(delta)
  rebuild_list()
  for i, p in ipairs(sorted) do
    if p.mac == selected then
      selected = sorted[clamp(i + delta, 1, #sorted)].mac
      break
    end
  end
  rebuild_list()
end

local function answer_for(c, is_latent)
  if c.st == "T" and not (c.hop == 0 and is_latent) then
    c.st, c.exposure, c.rate = "Q", 0.0, 0.0
    return "Q", c.hop
  elseif c.st == "Q" then
    return "D", c.hop
  end
  return "N", c.hop
end
local function accept_answer(c, target, res, hop)
  c.screened[target] = res
  if res == "Q" then
    award(c, max(10, 100 - 10 * hop))
    c.last_msg = "Quarantined: hop " .. hop
  elseif res == "D" then
    c.last_msg = "Already quarantined"
  else
    c.last_msg = "No taint found"
  end
end
local function send_request(p)
  p.queued, p.deadline = true, nil
  enqueue({ kind = "S", req = p.req, target = p.target,
    data = table.concat({ "RT1", "S", radio.id, tostring(p.req), p.target }, "|") })
end
local function screen_selected()
  local c = current()
  if c.pending then c.last_msg = "Screening in progress"; return end
  if (not practice and not active()) or (practice and practice.result) then return end
  rebuild_list()
  local p
  for _, e in ipairs(sorted) do if e.mac == selected then p = e; break end end
  if not p then c.last_msg = "No badge selected"; return end
  if c.screened[p.mac] == "Q" or c.screened[p.mac] == "D" then
    c.last_msg = "Already quarantined"; return
  end
  if t - p.heard > 3 then c.last_msg = "Badge out of date"; return end
  if p.rssi < SCREEN_RSSI then c.last_msg = "Move closer to screen"; return end
  if c.credits < 1 then c.last_msg = "No screening credits"; return end
  c.credits = c.credits - 1
  if practice then
    local res, hop = answer_for(p, latent(c))
    accept_answer(c, p.mac, res, hop)
  else
    req_next = req_next % 9999 + 1
    local pending = { req = req_next, target = p.mac, sends = 0, queued = false }
    c.pending, c.last_msg = pending, "Screening " .. p.mac:sub(-5)
    send_request(pending)
  end
end

local function expire_cache()
  for i = #cache, 1, -1 do if t >= cache[i].expires then table.remove(cache, i) end end
end
local function receive_screen(mac, m, rssi)
  if m.target ~= own_mac then return end
  local peer = roster[mac]
  if peer and t - peer.heard > PEER_TTL_S then peer = nil end
  if (peer and peer.rssi or rssi) < SCREEN_RSSI then return end
  expire_cache()
  local answer
  for _, e in ipairs(cache) do
    if e.mac == mac and e.req == m.req then answer = e.data; break end
  end
  if not answer then
    local res, hop = answer_for(radio, latent(radio))
    answer = table.concat({ "RT1", "A", radio.id, tostring(m.req), mac, res, tostring(hop) }, "|")
    if #cache == CACHE_MAX then table.remove(cache, 1) end
    cache[#cache + 1] = { mac = mac, req = m.req, data = answer, expires = t + CACHE_TTL_S }
  end
  enqueue({ kind = "A", data = answer })
end

function on_espnow(mac, data, rssi)
  if practice or not mac_ok(mac) or mac == own_mac or type(rssi) ~= "number"
      or rssi ~= rssi or rssi < -127 or rssi > 0 then return end
  local m = parse(data)
  if not m or seen_end(m.round) then return end
  if radio.id ~= IDLE and remain(radio) == 0 then
    finish(radio, "FUNDS ESCAPED")
    if seen_end(m.round) then return end
  end
  if m.kind == "H" then
    -- A finished badge stays on its end screen until the player presses
    -- SELECT; only then may it join the next round heard on the air.
    local on_end = mode == "end" or (mode == "qr" and qr_return == "end")
    if m.round ~= IDLE and m.remain > 0 and not (on_end and not active()) then
      if not active() or m.round < radio.id then
        reset_round(m.round, m.remain)
      end
    end
    local p = touch_peer(mac, rssi)
    if active() and m.round == radio.id then
      p.round, p.st, p.hop, p.score, p.hello_t = m.round, m.st, m.hop, m.score, t
    end
    return
  end
  if not active() or m.round ~= radio.id then return end
  if m.kind == "S" then
    receive_screen(mac, m, rssi)
  elseif m.kind == "A" then
    local p = radio.pending
    if p and mac == p.target and m.screener == own_mac and m.req == p.req then
      remove_request(p.req)
      radio.pending = nil
      accept_answer(radio, mac, m.res, m.hop)
    end
  elseif m.kind == "P" and m.parent == own_mac and not radio.children[mac]
      and m.hop == radio.hop + 1 and roster[mac] and count(radio.children) < 20 then
    radio.children[mac] = true
    award(radio, 25)
  end
end

-- The same exposure equation is used by real and simulated wallets.
local function expose(c, rate, parent, dt)
  c.rate = rate
  if c.st ~= "C" and c.st ~= "E" then return false end
  if rate > 0 then c.exposure = c.exposure + rate * dt
  else c.exposure = max(0, c.exposure - DECAY * dt) end
  if c.exposure >= EXPOSE_MAX and parent then
    c.st, c.hop, c.exposure = "T", min(parent.hop + 1, 9), EXPOSE_MAX
    return true
  end
  c.st = c.exposure > 0 and "E" or "C"
  return false
end
local function signal_rate(rssi)
  return clamp((rssi - RSSI_NONE) / (RSSI_FULL - RSSI_NONE), 0, 1)
end
local function credit_tick(c)
  if t >= c.credit_at then
    c.credits = min(CREDITS_MAX, c.credits + 1)
    c.credit_at = c.credit_at + CREDIT_EVERY_S
  end
end
local function containment(c, any_taint)
  if latent(c) or any_taint then c.clear_at = nil
  elseif not c.clear_at then c.clear_at = t
  elseif t - c.clear_at >= CONTAIN_S then finish(c, "CONTAINED") end
end
local function update_round(dt)
  local c = radio
  if c.id == IDLE then return end
  if remain(c) == 0 then finish(c, "FUNDS ESCAPED"); return end
  credit_tick(c)
  local rate, parent, any_taint = 0.0, nil, c.st == "T"
  for _, p in pairs(roster) do
    if p.round == c.id and p.st == "T" and p.hello_t and t - p.hello_t <= FRESH_S then
      any_taint = true
      local r = signal_rate(p.rssi)
      if r > rate or (r == rate and r > 0 and (not parent or p.mac < parent.mac)) then
        rate, parent = r, p
      end
    end
  end
  if expose(c, rate, parent, dt) then
    c.last_msg = "Funds moved here: hop " .. c.hop
    enqueue({ kind = "P", data = table.concat({ "RT1", "P", c.id, parent.mac, tostring(c.hop) }, "|") })
    any_taint = true
  end
  containment(c, any_taint)
end
local function update_pending()
  local p = radio.pending
  if not p then return end
  if p.deadline and t >= p.deadline then
    if p.sends >= REQ_TRIES then
      remove_request(p.req)
      radio.credits = min(CREDITS_MAX, radio.credits + 1)
      radio.pending, radio.last_msg = nil, "No answer"
      return
    end
    send_request(p)
  elseif not p.queued and not p.deadline then
    -- A saturated queue can discard a request. Requeue it without counting a send.
    send_request(p)
  end
end

local function start_outbreak()
  local b = badge.system.random_bytes(4)
  local id = string.format("%02x%02x%02x%02x", b:byte(1, 4))
  -- A zero or recently finished random id cannot name a new active round.
  if id == IDLE or seen_end(id) then radio.last_msg = "Try outbreak again"; return end
  reset_round(id, ROUND_S)
  radio.st, radio.hop, radio.last_msg = "T", 0, "Outbreak started"
end

local function pair_rssi(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return clamp(-45 - 0.6 * math.sqrt(dx * dx + dy * dy), -95, -45)
end
local function practice_positions(c)
  for i, s in ipairs(c.sims) do
    local angle = (0.15 + 0.03 * i) * (t - c.start_t) + i * 1.2
    local radius = 12 + 8 * i
    s.x, s.y = 50 + radius * math.cos(angle), 50 + radius * math.sin(angle)
    s.rssi, s.heard = pair_rssi(c, s), t
  end
end
local function enter_practice()
  if active() then return end
  roster, sorted, queue, cache = {}, {}, {}, {}
  radio.pending = nil
  selected, scroll, hold_at, hold_fired = nil, 0, nil, false
  local c = context()
  c.start_t, c.end_t, c.x, c.y, c.mac = t, t + PRACTICE_S, 50, 50, "YOU"
  c.next_screen, c.sims = t + (floor(LATENT_S / 8.0) + 1) * 8.0, {}
  for i = 1, 5 do
    c.sims[i] = { name = "SIM" .. i, mac = "SIM" .. i, st = i == 1 and "T" or "C",
      hop = 0, exposure = 0.0, rate = 0.0, children = {}, score = 0 }
  end
  practice, mode, leaders = c, "practice", {}
  c.last_msg = "Trace the heat. Screen a wallet."
  practice_positions(c)
  rebuild_list()
end
local function exit_practice()
  practice, leaders, sorted, selected, scroll = nil, {}, {}, nil, 0
  hold_at, hold_fired, mode = nil, false, "title"
  hello_at = t + HELLO_S
end
local function update_practice(dt)
  local c = practice
  if c.result then return end
  if remain(c) == 0 then finish(c, "FUNDS ESCAPED"); return end
  credit_tick(c)
  practice_positions(c)
  local all, changes = { c }, {}
  for _, s in ipairs(c.sims) do all[#all + 1] = s end
  -- Calculate from a frame snapshot, so array order cannot accelerate propagation.
  for _, a in ipairs(all) do
    local rate, parent = 0.0, nil
    for _, b in ipairs(all) do
      if a ~= b and b.st == "T" then
        local r = signal_rate(pair_rssi(a, b))
        if r > rate or (r == rate and r > 0 and (not parent or b.mac < parent.mac)) then
          rate, parent = r, b
        end
      end
    end
    changes[#changes + 1] = { a = a, rate = rate, parent = parent }
  end
  for _, change in ipairs(changes) do
    local a, parent = change.a, change.parent
    if expose(a, change.rate, parent, dt) then
      if not parent.children[a.mac] and a.hop == parent.hop + 1 then
        parent.children[a.mac] = true
        award(parent, 25)
      end
    end
  end
  if not latent(c) and t >= c.next_screen then
    c.next_screen = c.next_screen + 8.0
    local screener
    for _, s in ipairs(c.sims) do if s.st ~= "T" then screener = s; break end end
    if screener then
      local target, strongest = nil, -128
      for _, a in ipairs(all) do
        if a ~= screener and a.st == "T" then
          local r = pair_rssi(screener, a)
          if r > strongest or (r == strongest and (not target or a.mac < target.mac)) then
            target, strongest = a, r
          end
        end
      end
      if target and strongest >= SCREEN_RSSI then
        local res, hop = answer_for(target, latent(c))
        if res == "Q" then award(screener, max(10, 100 - 10 * hop)) end
        c.last_msg = screener.name .. " screened " .. (target.name or "YOU")
      end
    end
  end
  local any_taint = false
  for _, a in ipairs(all) do if a.st == "T" then any_taint = true end end
  containment(c, any_taint)
end

-- Integer-only drawing helpers keep float coordinates out of the badge bindings.
local function text(s, x, y, colour, size)
  g.text(s, I(x), I(y), colour or g.WHITE, size or 1)
end
local function centre(s, y, colour, size)
  g.text_center(s, 160, I(y), colour or g.WHITE, size or 1)
end
local function fill(x, y, w, h, colour)
  g.fill_rect(I(x), I(y), I(w), I(h), colour)
end
local function rule(y) fill(10, y, 300, 1, g.BORDER) end
local function state_colour(st)
  if st == "T" then return g.RED elseif st == "Q" then return g.BLUE
  elseif st == "E" then return g.ORANGE end
  return g.SOLANA_GREEN
end
local function state_word(c)
  if c.st == "T" then return "TAINTED hop " .. c.hop
  elseif c.st == "Q" then return "QUARANTINED"
  elseif c.st == "E" then return "EXPOSED" end
  return "CLEAN"
end
local function signal_bars(x, y, rssi)
  local bars = clamp(floor((rssi + 95) / 12.5), 0, 4)
  for i = 1, 4 do
    local h = 2 + i * 2
    fill(x + (i - 1) * 5, y + 10 - h, 3, h, i <= bars and g.SOLANA_GREEN or g.BORDER)
  end
end
local function draw_qr()
  g.clear(g.WHITE)
  local px = floor(min(320, 240 - 24) / (QR.size + 8))
  local x = floor((320 - px * (QR.size + 8)) / 2)
  local y = floor((240 - 24 - px * (QR.size + 8)) / 2)
  for row = 1, QR.size do
    local col = 1
    while col <= QR.size do
      if QR.rows[row]:sub(col, col) == "1" then
        local first = col
        repeat col = col + 1 until col > QR.size or QR.rows[row]:sub(col, col) ~= "1"
        g.fill_rect(x + (first + 3) * px, y + (row + 3) * px, (col - first) * px, px, g.BLACK)
      else col = col + 1 end
    end
  end
  g.text_center("Every transaction screened before the money moves.", 160, 240 - 18, g.BLACK, 1)
end
local function draw_title()
  centre("TAINT", 23, g.RED, 5)
  centre("by Range", 70, g.SOLANA_GREEN, 1)
  for i = 0, 4 do
    local x = 60 + i * 50
    if i < 4 then fill(x + 7, 110, 36, 2, g.BORDER) end
    g.circle(x, 111, 7, i < 2 and g.RED or g.SOLANA_GREEN)
  end
  centre("Stolen funds are on the move.", 135)
  centre("Trace the heat. Stop the spread.", 150, g.MUTED)
  centre(LA .. " radar   RIGHT about", 177)
  centre(active() and "Round active: open radar" or "DOWN practice", 192, g.SOLANA_GREEN)
  centre(LB .. " exit   BEST " .. best, 213, g.MUTED)
  centre("range.org", 230, g.MUTED)
end
local function draw_radar()
  local c = current()
  centre(practice and "PRACTICE: simulated wallets" or "TAINT / NEARBY BADGES", 4, g.SOLANA_GREEN)
  centre(state_word(c), 21, state_colour(c.st), 2)
  local seconds = remain(c)
  text(string.format("%d:%02d", seconds // 60, seconds % 60), 10, 46)
  text("CREDITS " .. c.credits, 66, 46, g.SOLANA_GREEN)
  text("SCORE " .. c.score, 146, 46)
  text("CH " .. net.channel(), 266, 46, g.MUTED)
  if c.st == "C" or c.st == "E" then
    text("HEAT", 10, 65, state_colour(c.st))
    fill(47, 63, 174, 11, g.BORDER)
    fill(48, 64, 172 * clamp(c.exposure / EXPOSE_MAX, 0, 1), 9, state_colour(c.st))
    text(I(100 * c.exposure / EXPOSE_MAX) .. "%", 230, 65, g.MUTED)
  elseif c.st == "T" then
    text("LAUNDERING: " .. count(c.children) .. " wallets reached", 10, 65, g.RED)
  else text("Immune for the rest of this round", 10, 65, g.BLUE) end
  rule(81)
  text("WALLET", 20, 86, g.MUTED)
  text("MY SCREEN", 115, 86, g.MUTED)
  text("SIGNAL   AGE", 220, 86, g.MUTED)
  if #sorted == 0 then
    centre("No nearby badges running Taint", 124, g.MUTED)
    centre("Use the same radio channel", 141, g.MUTED)
  end
  for row = 1, 8 do
    local p = sorted[scroll + row]
    if not p then break end
    local y = 100 + (row - 1) * 13
    if p.mac == selected then fill(8, y - 2, 304, 12, g.PANEL) end
    text((p.mac == selected and "> " or "  ") .. (p.name or p.mac:sub(-5)), 10, y)
    local res = c.screened[p.mac]
    text((res == "Q" or res == "D") and "QUAR" or res == "N" and "CLEAN" or "-",
      115, y, (res == "Q" or res == "D") and g.BLUE or g.MUTED)
    signal_bars(226, y - 2, p.rssi)
    text(floor(t - p.heard) .. "s", 277, y, g.MUTED)
  end
  rule(205)
  text(c.last_msg:sub(1, 50), 10, 210, g.YELLOW)
  if not practice and not active() then
    centre("Hold " .. LA .. " 2s: outbreak   " .. LB .. " menu", 226, g.MUTED)
    if hold_at then fill(10, 238, 300 * clamp((t - hold_at) / 2, 0, 1), 2, g.RED) end
  else centre("UP/DOWN choose  " .. LA .. " screen  " .. LB .. " menu", 226, g.MUTED) end
end
local function draw_about()
  centre("ABOUT TAINT", 18, g.SOLANA_GREEN, 2)
  local lines = {
    "Stolen funds hop from wallet to wallet.",
    "Trace the heat, screen a badge, stop the spread.",
    "", "Range: every transaction screened before",
    "the money moves. $35B+ on Solana protected.", "Web: range.org",
  }
  for i, line in ipairs(lines) do text(line, 10, 60 + (i - 1) * 19) end
  centre("DOWN QR   " .. LB .. " back", 222, g.MUTED)
end
local function draw_end()
  local c = current()
  centre(practice and "PRACTICE" or "ROUND COMPLETE", 15, g.SOLANA_GREEN)
  centre(c.result or "", 37, c.result == "CONTAINED" and g.SOLANA_GREEN or g.RED, 3)
  if c.result == "CONTAINED" then centre("(no taint seen for 15 s)", 69, g.MUTED) end
  centre("YOUR SCORE " .. c.score .. "   BEST " .. best, 88)
  rule(106)
  text("NEARBY WALLET SCORES", 22, 116, g.MUTED)
  for i, p in ipairs(leaders) do
    text(i .. ". " .. p.name, 22, 135 + (i - 1) * 14)
    text(tostring(p.score), 236, 135 + (i - 1) * 14, g.SOLANA_GREEN)
  end
  centre(LA .. " menu   DOWN QR", 222, g.MUTED)
end

function on_start()
  math.randomseed(string.unpack("<i4", badge.system.random_bytes(4)))
  local ok, mac = pcall(badge.wifi.mac)
  if ok and type(mac) == "string" and mac_ok(mac:lower()) then own_mac = mac:lower() end
  local stored = tonumber(kv.get("best", "0"))
  best = stored and math.tointeger(stored) and clamp(math.tointeger(stored), 0, 99999) or 0
  led.take()
  net.enable(true)
end

function on_update(dt)
  dt = clamp(dt, 0, 0.05)
  t = t + dt
  if practice then
    update_practice(dt)
  else
    tokens = min(TX_BUCKET, tokens + dt * TX_REFILL)
    update_round(dt)
    if mode == "radar" and not active() then
      if input.down("a") then
        if not hold_at then hold_at = t end
        if not hold_fired and t - hold_at >= 2 then
          hold_fired = true
          start_outbreak()
        end
      else hold_at, hold_fired = nil, false end
    else hold_at = nil end
    update_pending()
    flush_queue()
    if t >= hello_at then hello() end
    expire_cache()
  end
  rebuild_list()
  local c = current()
  local pulse = 0.25 + 0.75 * (math.sin(t * (c.st == "C" and 2 or 7)) + 1) / 2
  local r, green, b = 0, 0, 0
  if c.st == "C" then green = 55 * pulse
  elseif c.st == "E" then r, green = 150 * pulse * c.rate, 65 * pulse * c.rate
  elseif c.st == "T" then r = 160 * pulse
  else b = 80 end
  led.all(I(r), I(green), I(b))
  led.show()
end

function on_draw()
  if mode == "qr" then draw_qr(); return end
  g.clear(g.BG)
  if mode == "title" then draw_title()
  elseif mode == "about" then draw_about()
  elseif mode == "end" then draw_end()
  else draw_radar() end
end

function on_button(key, pressed)
  if key == "a" and not pressed then hold_at, hold_fired = nil, false end
  if not pressed then return end
  if mode == "qr" then
    if key == "b" or key == "up" then mode = qr_return end
  elseif mode == "title" then
    if key == "a" then mode = "radar"; hold_at, hold_fired = nil, false
    elseif key == "right" then mode = "about"
    elseif key == "down" then enter_practice()
    elseif key == "b" then badge.system.exit() end
  elseif mode == "about" then
    if key == "down" then qr_return, mode = "about", "qr"
    elseif key == "b" or key == "left" then mode = "title" end
  elseif mode == "end" then
    if key == "down" then qr_return, mode = "end", "qr"
    elseif key == "a" then
      if practice then exit_practice() else mode = "title" end
    end
  elseif mode == "radar" or mode == "practice" then
    if key == "b" then
      if practice then exit_practice() else mode = "title"; hold_at = nil end
    elseif key == "up" then move_selection(-1)
    elseif key == "down" then move_selection(1)
    elseif key == "a" then
      if practice or active() then screen_selected() else hold_at = t; hold_fired = false end
    end
  end
end

function on_stop() led.off() end

function __state()
  local c = current()
  local screened = {}
  for mac, res in pairs(c.screened) do screened[mac] = res end
  return { mode = mode, st = c.st, hop = c.hop, exposure = c.exposure,
    credits = c.credits, score = c.score, best = best, round = c.id,
    remain = remain(c), latent = latent(c),
    pending = c.pending and { req = c.pending.req, target = c.pending.target } or nil,
    roster = practice and #practice.sims or count(roster), screened = screened,
    result = c.result, children = count(c.children), tx = tx, last_msg = c.last_msg }
end
