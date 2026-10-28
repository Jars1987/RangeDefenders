-- Solana Invaders by Range
-- Protect Solana from malicious actors.
--
-- Controls:  LEFT / RIGHT  move
--            SELECT or UP  fire (hold for auto-fire)
--            CANCEL        pause / back

local g     = badge.gfx
local input = badge.input
local led   = badge.led
local kv    = badge.storage.kv

---------------------------------------------------------------
-- EDIT ME: branding and contacts (About + alert screens)
---------------------------------------------------------------
local WEBSITE = "range.org"
local CONTACT = "range.org/get-in-touch"
local ABOUT_LINES = {
  "Range: security & risk intelligence",
  "for Solana. Real-time alerts,",
  "address screening, tx simulation.",
  "",
  "Web:      " .. WEBSITE,
  "Contact:  " .. CONTACT,
  "Built by: @your_handle",            -- EDIT ME
}

---------------------------------------------------------------
-- Layout constants (screen is 320 x 240)
---------------------------------------------------------------
local W, H         = 320, 240
local COLS, ROWS   = 8, 4
local AW, AH       = 20, 14      -- alien size
local COLSP, ROWSP = 28, 20      -- alien spacing
local PW, PH       = 22, 12      -- player size
local PY           = 214         -- player top
local GROUND       = 229
local UFO_Y        = 17
local CELL         = 4           -- bunker cell size
local BCOLS, BROWS = 6, 4
local BUNKER_Y     = 180

local LA = input.label("a")      -- "SELECT"
local LB = input.label("b")      -- "CANCEL"

-- The malicious actors. Row 1 is the top row.
local KINDS = {
  { name = "DPRK",    pts = 40, color = g.RED,            alert = "DPRK-linked wallet" },
  { name = "BYBIT",   pts = 30, color = g.ORANGE,         alert = "Bybit exploiter cluster" },
  { name = "OFAC",    pts = 20, color = g.YELLOW,         alert = "OFAC-sanctioned address" },
  { name = "DRAINER", pts = 10, color = g.SOLANA_MAGENTA, alert = "Wallet drainer" },
}
local UFO_ALERT = "Protocol exploiter"

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local floor = math.floor
local function I(v) return floor(v + 0.5) end   -- gfx wants integers
local function clamp(v, a, b)
  if v < a then return a elseif v > b then return b end
  return v
end
local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

---------------------------------------------------------------
-- State
---------------------------------------------------------------
local state, state_t = "title", 0
local t = 0
local score, best, lives, wave = 0, 0, 3, 1
local new_best = false
local px, fire_cd = 0, 0
local pbullets, ebullets = {}, {}
local aliens, alive = {}, 0
local fx, fy, fdir = 0, 0, 1
local anim_t, anim_f = 0, 0
local enemy_cd = 1
local ufo, ufo_cd = nil, 15
local bunkers = {}
local particles, popups = {}, {}
local flash, led_cd = 0, 0
local killer = nil

local stars = {}
for i = 1, 40 do
  stars[i] = { x = math.random(0, W - 1), y = math.random(0, H - 1), s = math.random(8, 30) }
end

local function set_state(s)
  state, state_t = s, 0
  if s == "play" or s == "wave" then led.off() end
end

---------------------------------------------------------------
-- World setup
---------------------------------------------------------------
local function build_bunkers()
  bunkers = {}
  local bw = BCOLS * CELL
  for i = 1, 3 do
    local cx = I(W * i / 4)
    local b = { x = cx - bw // 2, y = BUNKER_Y, cells = {} }
    for r = 0, BROWS - 1 do
      for c = 0, BCOLS - 1 do
        local arch = (r == BROWS - 1) and (c == 2 or c == 3)
        b.cells[r * BCOLS + c] = not arch
      end
    end
    bunkers[i] = b
  end
end

local function build_wave()
  aliens = {}
  for r = 0, ROWS - 1 do
    for c = 0, COLS - 1 do
      aliens[#aliens + 1] = { col = c, row = r, kind = r + 1, alive = true }
    end
  end
  alive = #aliens
  local fw = (COLS - 1) * COLSP + AW
  fx = (W - fw) // 2
  fy = 34 + math.min((wave - 1) * 6, 36)
  fdir = 1
  pbullets, ebullets = {}, {}
  enemy_cd = 1.5
  ufo, ufo_cd = nil, math.random(12, 20)
  build_bunkers()
end

local function new_game()
  score, lives, wave = 0, 3, 1
  new_best, killer = false, nil
  px = (W - PW) // 2
  particles, popups = {}, {}
  build_wave()
  set_state("wave")
end

---------------------------------------------------------------
-- Effects
---------------------------------------------------------------
local function burst(x, y, color, n)
  for _ = 1, n or 10 do
    if #particles > 150 then return end
    local a = math.random() * math.pi * 2
    local s = 30 + math.random() * 80
    particles[#particles + 1] = {
      x = x, y = y, vx = math.cos(a) * s, vy = math.sin(a) * s,
      life = 0.5, color = color,
    }
  end
end

local function popup(x, y, text, color)
  popups[#popups + 1] = { x = x, y = y, text = text, color = color, life = 0.9 }
end

local function update_effects(dt)
  for i = #particles, 1, -1 do
    local p = particles[i]
    p.life = p.life - dt
    if p.life <= 0 then
      table.remove(particles, i)
    else
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    end
  end
  for i = #popups, 1, -1 do
    local p = popups[i]
    p.life = p.life - dt
    if p.life <= 0 then table.remove(popups, i) else p.y = p.y - 20 * dt end
  end
end

---------------------------------------------------------------
-- Bunkers ("treasury defenses")
---------------------------------------------------------------
-- Erodes the first cell (or every cell if all=true) touching the box.
local function bunker_hit(x, y, w, h, all)
  local hit = false
  for _, b in ipairs(bunkers) do
    if overlap(x, y, w, h, b.x, b.y, BCOLS * CELL, BROWS * CELL) then
      for r = 0, BROWS - 1 do
        for c = 0, BCOLS - 1 do
          local k = r * BCOLS + c
          if b.cells[k] and overlap(x, y, w, h, b.x + c * CELL, b.y + r * CELL, CELL, CELL) then
            b.cells[k] = false
            if not all then return true end
            hit = true
          end
        end
      end
    end
  end
  return hit
end

---------------------------------------------------------------
-- Game over
---------------------------------------------------------------
local function game_over()
  lives = 0
  if score > best then
    best, new_best = score, true
    kv.set("best", tostring(best))
  end
  led_cd = 0
  set_state("over")
end

local function player_hit(text)
  lives = lives - 1
  killer = text
  flash = 0.4
  burst(px + PW / 2, PY + PH / 2, g.SOLANA_GREEN, 20)
  led.pulse(255, 0, 0, 600)
  ebullets = {}
  if lives <= 0 then game_over() else set_state("dying") end
end

---------------------------------------------------------------
-- Gameplay update
---------------------------------------------------------------
local function update_play(dt)
  -- player movement
  local speed = 150
  if input.down("left") then px = px - speed * dt end
  if input.down("right") then px = px + speed * dt end
  px = clamp(px, 2, W - PW - 2)

  -- firing
  fire_cd = fire_cd - dt
  if (input.down("a") or input.down("up")) and fire_cd <= 0 and #pbullets < 2 then
    pbullets[#pbullets + 1] = { x = px + PW / 2 - 1, y = PY - 6 }
    fire_cd = 0.28
  end

  -- formation movement: speeds up as actors are removed
  local ratio = alive / (COLS * ROWS)
  local fspeed = 16 + wave * 5 + (1 - ratio) ^ 2 * 110
  fx = fx + fdir * fspeed * dt

  local minc, maxc, maxr = COLS, -1, -1
  for _, a in ipairs(aliens) do
    if a.alive then
      if a.col < minc then minc = a.col end
      if a.col > maxc then maxc = a.col end
      if a.row > maxr then maxr = a.row end
    end
  end
  local left  = fx + minc * COLSP
  local right = fx + maxc * COLSP + AW
  if (fdir > 0 and right >= W - 4) or (fdir < 0 and left <= 4) then
    fdir = -fdir
    fy = fy + 8
    fx = fx + fdir * 2
  end

  anim_t = anim_t + dt * (0.8 + fspeed / 40)
  if anim_t >= 1 then anim_t = anim_t - 1; anim_f = 1 - anim_f end

  -- actors chew through the defenses, and reaching the bottom is game over
  local bottom = fy + maxr * ROWSP + AH
  if bottom >= BUNKER_Y then
    for _, a in ipairs(aliens) do
      if a.alive then
        local ay = fy + a.row * ROWSP
        if ay + AH >= BUNKER_Y then
          bunker_hit(fx + a.col * COLSP, ay, AW, AH, true)
        end
      end
    end
  end
  if bottom >= PY then
    killer = "Treasury breached"
    flash = 0.4
    led.pulse(255, 0, 0, 600)
    game_over()
    return
  end

  -- player bullets
  for i = #pbullets, 1, -1 do
    local b = pbullets[i]
    b.y = b.y - 280 * dt
    local hit = false
    if b.y < 14 then
      hit = true
    elseif bunker_hit(b.x, b.y, 2, 6) then
      hit = true
    elseif ufo and overlap(b.x, b.y, 2, 6, ufo.x, UFO_Y, 30, 12) then
      score = score + ufo.pts
      burst(ufo.x + 15, UFO_Y + 6, g.CYAN, 18)
      popup(ufo.x + 15, UFO_Y, "EXPLOITER +" .. ufo.pts, g.CYAN)
      led.pulse(0, 255, 255, 300)
      ufo = nil
      hit = true
    else
      for _, a in ipairs(aliens) do
        if a.alive then
          local ax, ay = fx + a.col * COLSP, fy + a.row * ROWSP
          if overlap(b.x, b.y, 2, 6, ax, ay, AW, AH) then
            local k = KINDS[a.kind]
            a.alive = false
            alive = alive - 1
            score = score + k.pts
            burst(ax + AW / 2, ay + AH / 2, k.color, 10)
            popup(ax + AW / 2, ay, k.name .. " +" .. k.pts, k.color)
            led.pulse(20, 241, 149, 150)
            hit = true
            break
          end
        end
      end
    end
    if hit then table.remove(pbullets, i) end
  end

  -- enemy fire: a random actor at the bottom of its column shoots
  enemy_cd = enemy_cd - dt
  if enemy_cd <= 0 and alive > 0 then
    local lowest = {}
    for _, a in ipairs(aliens) do
      if a.alive then
        local cur = lowest[a.col]
        if not cur or a.row > cur.row then lowest[a.col] = a end
      end
    end
    local shooters = {}
    for _, a in pairs(lowest) do shooters[#shooters + 1] = a end
    local s = shooters[math.random(#shooters)]
    ebullets[#ebullets + 1] = {
      x = fx + s.col * COLSP + AW / 2 - 1,
      y = fy + s.row * ROWSP + AH,
      kind = s.kind,
    }
    enemy_cd = math.max(0.3, 1.3 - wave * 0.1 - (1 - ratio) * 0.5) * (0.6 + math.random() * 0.8)
  end

  -- enemy bullets
  local espeed = 100 + wave * 12
  for i = #ebullets, 1, -1 do
    local b = ebullets[i]
    b.y = b.y + espeed * dt
    if b.y > GROUND then
      table.remove(ebullets, i)
    elseif bunker_hit(b.x, b.y, 3, 7) then
      table.remove(ebullets, i)
    elseif overlap(b.x, b.y, 3, 7, px + 3, PY + 2, PW - 6, PH - 2) then
      player_hit(KINDS[b.kind].alert)
      return
    end
  end

  -- the exploiter mothership
  if ufo then
    ufo.x = ufo.x + ufo.dir * 70 * dt
    if ufo.x < -40 or ufo.x > W + 40 then ufo = nil end
  else
    ufo_cd = ufo_cd - dt
    if ufo_cd <= 0 then
      local dir = (math.random(2) == 1) and 1 or -1
      local pts = ({ 50, 100, 150, 300 })[math.random(4)]
      ufo = { x = (dir == 1) and -30 or W, dir = dir, pts = pts }
      ufo_cd = math.random(15, 25)
    end
  end

  -- wave cleared: bonus life (max 5) and the next wave starts lower
  if alive == 0 then
    wave = wave + 1
    lives = math.min(lives + 1, 5)
    popup(W // 2, 120, "WAVE CLEARED +1 LIFE", g.SOLANA_GREEN)
    build_wave()
    set_state("wave")
  end
end

---------------------------------------------------------------
-- Drawing: sprites
---------------------------------------------------------------
local BLACK = g.BLACK

local function draw_alien(kind, x, y, f)
  local c = KINDS[kind].color
  if kind == 1 then
    -- DPRK: squid
    g.fill_triangle(x + 10, y, x + 3, y + 8, x + 17, y + 8, c)
    g.fill_rect(x + 3, y + 6, 15, 4, c)
    g.fill_rect(x + 7, y + 5, 2, 2, BLACK)
    g.fill_rect(x + 12, y + 5, 2, 2, BLACK)
    if f == 0 then
      g.line(x + 5, y + 10, x + 2, y + 13, c)
      g.line(x + 10, y + 10, x + 10, y + 13, c)
      g.line(x + 15, y + 10, x + 18, y + 13, c)
    else
      g.line(x + 5, y + 10, x + 7, y + 13, c)
      g.line(x + 10, y + 10, x + 10, y + 13, c)
      g.line(x + 15, y + 10, x + 13, y + 13, c)
    end
  elseif kind == 2 then
    -- BYBIT hacker: crab with snapping claws
    g.fill_round_rect(x + 4, y + 3, 12, 8, 2, c)
    g.line(x + 7, y + 3, x + 5, y, c)
    g.line(x + 13, y + 3, x + 15, y, c)
    g.fill_rect(x + 6, y + 5, 2, 2, BLACK)
    g.fill_rect(x + 12, y + 5, 2, 2, BLACK)
    local cy = (f == 0) and 2 or 6
    g.fill_rect(x, y + cy, 3, 6, c)
    g.fill_rect(x + 17, y + cy, 3, 6, c)
    if f == 0 then
      g.line(x + 6, y + 11, x + 4, y + 13, c)
      g.line(x + 14, y + 11, x + 16, y + 13, c)
    else
      g.line(x + 6, y + 11, x + 8, y + 13, c)
      g.line(x + 14, y + 11, x + 12, y + 13, c)
    end
  elseif kind == 3 then
    -- OFAC sanctioned: a walking "banned" sign
    g.fill_circle(x + 10, y + 6, 6, c)
    g.fill_circle(x + 10, y + 6, 3, BLACK)
    g.line(x + 7, y + 3, x + 13, y + 9, c)
    g.line(x + 8, y + 3, x + 14, y + 9, c)
    local o = (f == 0) and 0 or 2
    g.line(x + 5 + o, y + 12, x + 5 + o, y + 13, c)
    g.line(x + 9 + o, y + 12, x + 9 + o, y + 13, c)
    g.line(x + 13 - o, y + 12, x + 13 - o, y + 13, c)
  else
    -- DRAINER: a wallet with fangs
    g.fill_round_rect(x + 1, y + 1, 18, 10, 2, c)
    g.fill_rect(x + 12, y + 4, 7, 4, BLACK)
    g.fill_rect(x + 14, y + 5, 2, 2, c)
    local fl = (f == 0) and 3 or 1
    g.fill_triangle(x + 3, y + 11, x + 7, y + 11, x + 5, y + 11 + fl, g.WHITE)
    g.fill_triangle(x + 8, y + 11, x + 12, y + 11, x + 10, y + 11 + fl, g.WHITE)
  end
end

local function draw_ufo(x, y)
  g.fill_round_rect(x + 8, y, 14, 6, 3, g.SOLANA_TEAL)
  g.fill_round_rect(x, y + 4, 30, 6, 3, g.CYAN)
  local on = (I(t * 6) % 2 == 0)
  for i = 0, 3 do
    g.fill_rect(x + 4 + i * 7, y + 6, 2, 2, ((i % 2 == 0) == on) and g.WHITE or BLACK)
  end
end

local function draw_ship(x, y)
  g.fill_rect(x, y + 8, PW, 4, g.SOLANA_GREEN)
  g.fill_triangle(x + 2, y + 8, x + 11, y, x + 20, y + 8, g.SOLANA_PURPLE)
  g.fill_rect(x + 10, y - 3, 2, 4, g.SOLANA_GREEN)
end

local function draw_life(x, y)
  g.fill_triangle(x, y + 6, x + 5, y, x + 10, y + 6, g.SOLANA_GREEN)
end

---------------------------------------------------------------
-- Drawing: scenes
---------------------------------------------------------------
local function draw_bar(y)
  for x = 0, W - 1, 4 do g.fill_rect(x, y, 4, 3, g.gradient(x / W)) end
end

local function draw_stars()
  for _, s in ipairs(stars) do
    g.pixel(floor(s.x), floor(s.y), (s.s > 22) and g.WHITE or g.MUTED)
  end
end

local function draw_hud()
  draw_bar(0)
  g.text("SCORE " .. string.format("%05d", score), 4, 5, g.WHITE)
  g.text_center("WAVE " .. wave, W // 2, 5, g.SOLANA_TEAL)
  for i = 1, lives do draw_life(W - i * 14, 5) end
end

local function draw_world()
  g.clear(g.BG)
  draw_stars()

  for _, b in ipairs(bunkers) do
    for r = 0, BROWS - 1 do
      for c = 0, BCOLS - 1 do
        if b.cells[r * BCOLS + c] then
          g.fill_rect(b.x + c * CELL, b.y + r * CELL, CELL, CELL, g.SOLANA_TEAL)
        end
      end
    end
  end

  local ix, iy = I(fx), I(fy)
  for _, a in ipairs(aliens) do
    if a.alive then draw_alien(a.kind, ix + a.col * COLSP, iy + a.row * ROWSP, anim_f) end
  end
  if ufo then draw_ufo(I(ufo.x), UFO_Y) end

  for _, b in ipairs(pbullets) do
    g.fill_rect(I(b.x), I(b.y), 2, 6, g.SOLANA_GREEN)
  end
  local zig = (I(t * 12) % 2 == 0) and 1 or 0
  for _, b in ipairs(ebullets) do
    local bx, by, c = I(b.x), I(b.y), KINDS[b.kind].color
    g.fill_rect(bx + zig, by, 2, 4, c)
    g.fill_rect(bx + 1 - zig, by + 4, 2, 3, c)
  end

  if state ~= "dying" or I(state_t * 10) % 2 == 0 then draw_ship(I(px), PY) end

  for _, p in ipairs(particles) do g.fill_rect(I(p.x), I(p.y), 2, 2, p.color) end
  for _, p in ipairs(popups) do g.text_center(p.text, I(p.x), I(p.y), p.color) end

  g.line(0, GROUND, W - 1, GROUND, g.SOLANA_GREEN)
  g.text_center("protected by " .. WEBSITE, W // 2, GROUND + 3, g.MUTED)
  draw_hud()

  if flash > 0 then
    g.rect(0, 0, W, H, g.RED)
    g.rect(1, 1, W - 2, H - 2, g.RED)
  end
end

local function draw_title()
  g.clear(g.BG)
  draw_stars()
  draw_bar(0)
  local p = (math.sin(t * 2) + 1) / 2
  g.text_center("SOLANA", W // 2, 12, g.gradient(p), 3)
  g.text_center("INVADERS", W // 2, 38, g.gradient(1 - p), 3)
  g.text_center("by Range", W // 2, 66, g.SOLANA_TEAL)
  g.text_center("Protect Solana from malicious actors", W // 2, 80, g.WHITE)

  local lx = 85
  for i, k in ipairs(KINDS) do
    local y = 96 + (i - 1) * 19
    draw_alien(i, lx, y, anim_f)
    g.text(k.name, lx + 30, y + 3, k.color)
    g.text_right(k.pts .. " pts", lx + 150, y + 3, g.MUTED)
  end
  local y = 96 + 4 * 19
  draw_ufo(lx - 5, y + 2)
  g.text("EXPLOITER", lx + 30, y + 3, g.CYAN)
  g.text_right("??? pts", lx + 150, y + 3, g.MUTED)

  if I(t * 2) % 2 == 0 then
    g.text_center(LA .. " start  RIGHT about  " .. LB .. " exit", W // 2, 198, g.WHITE)
  end
  g.text_center("BEST " .. best, W // 2, 213, g.SOLANA_GREEN)
  g.text_center(WEBSITE, W // 2, 228, g.MUTED)
end

local function draw_about()
  g.clear(g.BG)
  draw_stars()
  draw_bar(0)
  g.text_center("ABOUT", W // 2, 14, g.SOLANA_GREEN, 2)
  g.text_center("SOLANA INVADERS by Range", W // 2, 38, g.WHITE)
  for i, line in ipairs(ABOUT_LINES) do
    g.text(line, 20, 60 + (i - 1) * 14, g.WHITE)
  end
  g.text_center(WEBSITE, W // 2, 172, g.gradient((math.sin(t * 2) + 1) / 2), 2)
  g.text_center(LB .. " back", W // 2, 222, g.MUTED)
end

-- Game over, styled as a Range monitoring alert
local function draw_over()
  g.clear(g.BG)
  draw_stars()
  local blink = I(state_t * 3) % 2 == 0
  g.fill_round_rect(10, 10, 300, 220, 8, g.PANEL)
  g.round_rect(10, 10, 300, 220, 8, blink and g.RED or g.BORDER)
  for x = 14, 302, 4 do g.fill_rect(x, 14, 4, 3, g.gradient((x - 14) / 292)) end

  g.text("RANGE ALERT", 22, 26, g.WHITE, 2)
  g.fill_round_rect(214, 24, 84, 16, 4, g.RED)
  g.text_center("CRITICAL", 256, 28, g.WHITE)
  g.line(22, 48, 298, 48, g.BORDER)

  g.text("Anomalous movement of funds", 22, 58, g.ORANGE)
  g.text("detected on Solana", 22, 70, g.ORANGE)
  g.text("Flagged:  " .. (killer or "Unknown actor"), 22, 88, g.WHITE)
  g.text("Rule:     Treasury outflow > limit", 22, 100, g.WHITE)
  g.text("Status:   Defenses down", 22, 112, g.WHITE)
  g.line(22, 128, 298, 128, g.BORDER)

  g.text("SCORE", 22, 136, g.MUTED)
  g.text(tostring(score), 22, 148, g.WHITE, 2)
  g.text("BEST", 130, 136, g.MUTED)
  g.text(tostring(best), 130, 148, new_best and g.SOLANA_GREEN or g.WHITE, 2)
  g.text("WAVE", 238, 136, g.MUTED)
  g.text(tostring(wave), 238, 148, g.WHITE, 2)
  if new_best then g.text("NEW BEST!", 130, 166, g.SOLANA_GREEN) end

  g.text_center("Get real-time onchain alerts:", W // 2, 178, g.MUTED)
  g.text_center(WEBSITE, W // 2, 190, g.gradient((math.sin(t * 2) + 1) / 2), 2)
  if state_t > 0.8 then
    g.text_center(LA .. " retry  RIGHT about  " .. LB .. " menu", W // 2, 214, g.WHITE)
  end
end

---------------------------------------------------------------
-- Runtime callbacks
---------------------------------------------------------------
function on_start()
  led.take()
  best = tonumber(kv.get("best", "0")) or 0
  badge.log("Solana Invaders by Range - best " .. best)
end

function on_update(dt)
  if dt > 0.05 then dt = 0.05 end
  t = t + dt
  state_t = state_t + dt
  if flash > 0 then flash = flash - dt end

  for _, s in ipairs(stars) do
    s.y = s.y + s.s * dt
    if s.y >= H then s.y = s.y - H; s.x = math.random(0, W - 1) end
  end

  if state == "play" then
    update_play(dt)
  else
    anim_t = anim_t + dt * 1.5
    if anim_t >= 1 then anim_t = anim_t - 1; anim_f = 1 - anim_f end
    if state == "wave" and state_t > 1.4 then set_state("play")
    elseif state == "dying" and state_t > 1.2 then set_state("play") end
  end

  -- LEDs: brand breathing on menus, red alert pulse on game over
  if state == "title" or state == "about" then
    led.gradient(0, (math.sin(t * 1.5) + 1) / 2, 0.3)
    led.gradient(1, (math.cos(t * 1.5) + 1) / 2, 0.3)
    led.show()
  elseif state == "over" then
    led_cd = led_cd - dt
    if led_cd <= 0 then led.pulse(255, 0, 0, 500); led_cd = 0.8 end
  end

  update_effects(dt)
end

function on_draw()
  if state == "title" then
    draw_title()
  elseif state == "about" then
    draw_about()
  elseif state == "over" then
    draw_over()
  else
    draw_world()
    if state == "wave" then
      g.text_center("WAVE " .. wave, W // 2, 110, g.SOLANA_GREEN, 3)
      g.text_center("Malicious actors incoming", W // 2, 140, g.WHITE)
    elseif state == "pause" then
      g.fill_round_rect(60, 90, 200, 60, 6, g.PANEL)
      g.round_rect(60, 90, 200, 60, 6, g.BORDER)
      g.text_center("PAUSED", W // 2, 100, g.WHITE, 2)
      g.text_center(LA .. " resume   " .. LB .. " menu", W // 2, 128, g.MUTED)
    end
  end
end

function on_button(key, pressed)
  if not pressed then return end
  if state == "title" then
    if key == "a" then new_game()
    elseif key == "right" or key == "down" then set_state("about")
    elseif key == "b" then badge.system.exit() end
  elseif state == "about" then
    if key == "b" or key == "left" or key == "a" then set_state("title") end
  elseif state == "play" then
    if key == "b" then set_state("pause") end
  elseif state == "pause" then
    if key == "a" then set_state("play")
    elseif key == "b" then set_state("title") end
  elseif state == "over" then
    if state_t > 0.8 then
      if key == "a" then new_game()
      elseif key == "right" then set_state("about")
      elseif key == "b" then set_state("title") end
    end
  end
end

function on_stop()
  led.off()
end
