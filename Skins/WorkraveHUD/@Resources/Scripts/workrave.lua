-- WorkraveHUD / workrave.lua
-- FSM + idle threshold + STRICT/RELAXED + WAV sounds + progress bars + fullscreen overlay + skip

local STATE_WORK        = "WORK"
local STATE_MICRO_BREAK = "MICRO_BREAK"
local STATE_REST_BREAK  = "REST_BREAK"
local STATE_DAILY_LIMIT = "DAILY_LIMIT"

local cfg = {}
local ctx = {
  state = STATE_WORK,

  activeToday = 0,
  microActive = 0,
  restActive  = 0,

  idleInBreak = 0,

  lastDayKey = nil,
  prevIdleTime = nil,
  lastUpdateTs = nil,

  breakStartedAt = nil,
  breakDeadline = nil,

  overlayVisible = false,
  overlayLoaded = false,
}

local varCache = {}

local function vnum(name) return tonumber(SKIN:GetVariable(name)) end
local function vstr(name) return tostring(SKIN:GetVariable(name)) end

local function clamp01(x)
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function fmt_hms(sec)
  if sec < 0 then sec = 0 end
  sec = math.floor(sec + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

local function now()
  return os.time()
end

local function dayKey(t, resetHour)
  local y = t.year
  local yd = t.yday
  if t.hour < resetHour then yd = yd - 1 end
  return string.format("%04d-%03d", y, yd)
end

local function playSound(path)
  if path and path ~= "" then
    SKIN:Bang('!Play "' .. path .. '"')
  end
end

local function cacheSetVar(name, value, target)
  local key = (target or "SELF") .. ":" .. name
  local valStr = tostring(value)
  if varCache[key] ~= valStr then
    varCache[key] = valStr
    if target then
      SKIN:Bang("!SetVariable", name, valStr, target)
    else
      SKIN:Bang("!SetVariable", name, valStr)
    end
  end
end

local function showStateText(text)
  cacheSetVar("StateText", text)
end

-- =========================
-- Overlay helpers (robust)
-- =========================
local OVERLAY_CONFIG = "WorkraveHUD\\Overlay"
local OVERLAY_FILE   = "Overlay.ini"
local OVERLAY_REF    = OVERLAY_CONFIG

local function overlayShow()
  if not ctx.overlayVisible then
    SKIN:Bang("!Show", OVERLAY_REF)
    SKIN:Bang("!ZPos", "2", OVERLAY_REF)
    ctx.overlayVisible = true
  end
end

local function overlayHide()
  if ctx.overlayVisible then
    SKIN:Bang("!Hide", OVERLAY_REF)
    ctx.overlayVisible = false
  end
end

local function overlaySet(mode, elapsed, remain, total, bar)
  -- SetVariable catre overlay (target explicit)
  cacheSetVar("BreakMode", mode, OVERLAY_REF)
  cacheSetVar("Elapsed", elapsed, OVERLAY_REF)
  cacheSetVar("Remain", remain, OVERLAY_REF)
  cacheSetVar("Total", total, OVERLAY_REF)
  cacheSetVar("Bar", tostring(bar), OVERLAY_REF)

  local title
  if mode == "MICRO" then title = "Micro break"
  elseif mode == "REST" then title = "Rest break"
  else title = "Daily limit" end

  cacheSetVar("BreakTitle", title, OVERLAY_REF)

  -- fortam refresh UI overlay (doar daca suntem vizibili)
  if ctx.overlayVisible then
    SKIN:Bang("!Update", OVERLAY_REF)
    SKIN:Bang("!Redraw", OVERLAY_REF)
  end
end


-- =========================
-- Break lifecycle
-- =========================
local function clearBreak()
  ctx.idleInBreak = 0
  ctx.breakStartedAt = nil
  ctx.breakDeadline = nil
end

local function requiredIdle(mode)
  if mode == "MICRO" then return cfg.microRequiredIdle end
  if mode == "REST"  then return cfg.restRequiredIdle end
  return 0
end

local function startBreak(mode)
  ctx.idleInBreak = 0
  ctx.breakStartedAt = now()

  if cfg.breakPolicy == "RELAXED" and cfg.relaxedTimeout > 0 then
    ctx.breakDeadline = ctx.breakStartedAt + cfg.relaxedTimeout
  else
    ctx.breakDeadline = nil
  end

  playSound(cfg.soundStart)
  overlayShow()
end

local function endBreak(mode)
  playSound(cfg.soundEnd)

  if mode == "MICRO" then
    ctx.microActive = 0
  elseif mode == "REST" then
    ctx.restActive = 0
    ctx.microActive = 0
  elseif mode == "DAILY" then
    -- Skip/complete daily: we DON'T reset activeToday anymore
    -- to prevent "starting a new day" immediately.
    -- The counter will only reset at DailyResetHour.
    ctx.microActive = 0
    ctx.restActive  = 0
  end

  clearBreak()
  overlayHide()
end

local function isResetMoment()
  local t = os.date("*t")
  local key = dayKey(t, cfg.dailyResetHour)
  if ctx.lastDayKey == nil then
    ctx.lastDayKey = key
    return false
  end
  if key ~= ctx.lastDayKey then
    ctx.lastDayKey = key
    return true
  end
  return false
end

-- Exposed to overlay button via !CommandMeasure
function SkipBreak()
  if ctx.state == STATE_MICRO_BREAK then
    endBreak("MICRO")
    ctx.state = STATE_WORK
  elseif ctx.state == STATE_REST_BREAK then
    endBreak("REST")
    ctx.state = STATE_WORK
  elseif ctx.state == STATE_DAILY_LIMIT then
    endBreak("DAILY")
    ctx.state = STATE_WORK
  end

  overlayHide()
  
end

local function setBarsAndTexts(isIdle, idleSec)
  -- Optional debug vars
  cacheSetVar("ActiveTodayText", fmt_hms(ctx.activeToday))
  cacheSetVar("MicroActiveText", fmt_hms(ctx.microActive))
  cacheSetVar("RestActiveText",  fmt_hms(ctx.restActive))

  -- Compute elapsed/remain/total per timer (WORK semantics)
  local microTotal   = cfg.microInterval
  local microElapsed = ctx.microActive
  local microRemain  = microTotal - microElapsed

  local restTotal   = cfg.restInterval
  local restElapsed = ctx.restActive
  local restRemain  = restTotal - restElapsed

  local dailyTotal   = cfg.dailyLimit
  local dailyElapsed = ctx.activeToday
  local dailyRemain  = dailyTotal - dailyElapsed

  -- Break semantics: show idle progress toward requirement (for micro/rest)
  if ctx.state == STATE_MICRO_BREAK then
    microTotal   = requiredIdle("MICRO")
    microElapsed = ctx.idleInBreak
    microRemain  = microTotal - microElapsed
  end

  if ctx.state == STATE_REST_BREAK then
    restTotal   = requiredIdle("REST")
    restElapsed = ctx.idleInBreak
    restRemain  = restTotal - restElapsed
  end

  if ctx.state == STATE_DAILY_LIMIT then
    dailyRemain = 0
  end

  -- Clamp remains
  if microRemain < 0 then microRemain = 0 end
  if restRemain  < 0 then restRemain  = 0 end
  if dailyRemain < 0 then dailyRemain = 0 end

  -- Export 3 vars / block
  cacheSetVar("MicroElapsedText", fmt_hms(microElapsed))
  cacheSetVar("MicroRemainText",  fmt_hms(microRemain))
  cacheSetVar("MicroTotalText",   fmt_hms(microTotal))

  cacheSetVar("RestElapsedText", fmt_hms(restElapsed))
  cacheSetVar("RestRemainText",  fmt_hms(restRemain))
  cacheSetVar("RestTotalText",   fmt_hms(restTotal))

  cacheSetVar("DailyElapsedText", fmt_hms(dailyElapsed))
  cacheSetVar("DailyRemainText",  fmt_hms(dailyRemain))
  cacheSetVar("DailyTotalText",   fmt_hms(dailyTotal))

  -- Bars
  local microBar, restBar, dailyBar = 0, 0, 0

  if ctx.state == STATE_MICRO_BREAK then
    local req = requiredIdle("MICRO")
    microBar = (req > 0) and clamp01(ctx.idleInBreak / req) or 0
  else
    microBar = (cfg.microInterval > 0) and clamp01(ctx.microActive / cfg.microInterval) or 0
  end

  if ctx.state == STATE_REST_BREAK then
    local req = requiredIdle("REST")
    restBar = (req > 0) and clamp01(ctx.idleInBreak / req) or 0
  else
    restBar = (cfg.restInterval > 0) and clamp01(ctx.restActive / cfg.restInterval) or 0
  end

  dailyBar = (cfg.dailyLimit > 0) and clamp01(ctx.activeToday / cfg.dailyLimit) or 0

  cacheSetVar("MicroBar", tostring(microBar))
  cacheSetVar("RestBar",  tostring(restBar))
  cacheSetVar("DailyBar", tostring(dailyBar))

  local idleTxt = isIdle and ("YES (" .. math.floor(idleSec) .. "s)") or ("NO (" .. math.floor(idleSec) .. "s)")
  cacheSetVar("IdleText", idleTxt)

  -- Sync overlay live (only when needed)
  if ctx.state == STATE_MICRO_BREAK then
    overlayShow()
    overlaySet("MICRO", fmt_hms(microElapsed), fmt_hms(microRemain), fmt_hms(microTotal), microBar)
  elseif ctx.state == STATE_REST_BREAK then
    overlayShow()
    overlaySet("REST", fmt_hms(restElapsed), fmt_hms(restRemain), fmt_hms(restTotal), restBar)
  elseif ctx.state == STATE_DAILY_LIMIT then
    overlayShow()
    overlaySet("DAILY", fmt_hms(dailyElapsed), fmt_hms(dailyRemain), fmt_hms(dailyTotal), dailyBar)
  else
    overlayHide()
  end
end

function Initialize()
  cfg.microInterval     = vnum("MicroInterval")
  cfg.microRequiredIdle = vnum("MicroRequiredIdle")
  cfg.restInterval      = vnum("RestInterval")
  cfg.restRequiredIdle  = vnum("RestRequiredIdle")
  cfg.dailyLimit        = vnum("DailyLimit")
  cfg.dailyResetHour    = vnum("DailyResetHour")

  cfg.idleThreshold     = vnum("IdleThreshold")
  cfg.breakPolicy       = vstr("BreakPolicy")
  cfg.relaxedTimeout    = vnum("RelaxedBreakTimeout")

  cfg.soundStart        = vstr("SoundStart")
  cfg.soundEnd          = vstr("SoundEnd")

  cacheSetVar("StateText", "INIT")
  cacheSetVar("MicroBar", "0")
  cacheSetVar("RestBar", "0")
  cacheSetVar("DailyBar", "0")
  cacheSetVar("IdleText", "NO")

  cacheSetVar("MicroElapsedText", "--:--")
  cacheSetVar("MicroRemainText",  "--:--")
  cacheSetVar("MicroTotalText",   "--:--")

  cacheSetVar("RestElapsedText", "--:--")
  cacheSetVar("RestRemainText",  "--:--")
  cacheSetVar("RestTotalText",   "--:--")

  cacheSetVar("DailyElapsedText", "--:--")
  cacheSetVar("DailyRemainText",  "--:--")
  cacheSetVar("DailyTotalText",   "--:--")

  ctx.prevIdleTime = nil
  ctx.lastUpdateTs = now()

  -- Load overlay once
  if not ctx.overlayLoaded then
    SKIN:Bang("!ActivateConfig", OVERLAY_CONFIG, OVERLAY_FILE)
    ctx.overlayLoaded = true
  end
  
  ctx.overlayVisible = false
  overlayHide()
end

function Update()
  -- 1) daily reset edge
  if isResetMoment() then
    ctx.activeToday = 0
    ctx.microActive = 0
    ctx.restActive  = 0

    if ctx.state == STATE_DAILY_LIMIT then
      clearBreak()
      ctx.state = STATE_WORK
      overlayHide()
    end
  end

  -- 2) Timing delta (accurate for sleep/hibernate)
  local currentTs = now()
  local delta = currentTs - (ctx.lastUpdateTs or currentTs)
  ctx.lastUpdateTs = currentTs

  if delta < 0 then delta = 0 end -- clock went backwards?

  -- 3) idle time from SysInfo
  local mIdle = SKIN:GetMeasure("MeasureIdleTime")
  local idleSec = tonumber(mIdle:GetValue()) or 0
  local isIdle = (idleSec >= cfg.idleThreshold)

  -- 4) DAILY LIMIT (overlay stays)
  if ctx.state == STATE_DAILY_LIMIT then
    showStateText("DAILY LIMIT")
    if isIdle then
      ctx.idleInBreak = ctx.idleInBreak + delta
    end
    setBarsAndTexts(isIdle, idleSec)
    return
  end

  -- 5) BREAK states
  if ctx.state == STATE_MICRO_BREAK or ctx.state == STATE_REST_BREAK then
    local mode = (ctx.state == STATE_MICRO_BREAK) and "MICRO" or "REST"

    if cfg.breakPolicy == "RELAXED" and ctx.breakDeadline ~= nil and now() >= ctx.breakDeadline then
      startBreak(mode)
    end

    if isIdle then
      ctx.idleInBreak = ctx.idleInBreak + delta
    else
      if cfg.breakPolicy == "STRICT" then
        ctx.idleInBreak = 0
      end
    end

    if ctx.idleInBreak >= requiredIdle(mode) then
      endBreak(mode)
      ctx.state = STATE_WORK
    end

    showStateText((mode == "MICRO") and "MICRO BREAK" or "REST BREAK")
    setBarsAndTexts(isIdle, idleSec)
    return
  end

  -- 6) WORK: count active only when not idle
  if not isIdle then
    ctx.activeToday = ctx.activeToday + delta
    ctx.microActive = ctx.microActive + delta
    ctx.restActive  = ctx.restActive  + delta
  end

  -- Priority: Daily > Rest > Micro
  if ctx.activeToday >= cfg.dailyLimit then
    ctx.state = STATE_DAILY_LIMIT
    startBreak("DAILY")
    showStateText("DAILY LIMIT")
    setBarsAndTexts(isIdle, idleSec)
    return
  end

  if ctx.restActive >= cfg.restInterval then
    ctx.state = STATE_REST_BREAK
    startBreak("REST")
    showStateText("REST BREAK")
    setBarsAndTexts(isIdle, idleSec)
    return
  end

  if ctx.microActive >= cfg.microInterval then
    ctx.state = STATE_MICRO_BREAK
    startBreak("MICRO")
    showStateText("MICRO BREAK")
    setBarsAndTexts(isIdle, idleSec)
    return
  end

  -- Normal work
  ctx.state = STATE_WORK
  showStateText("WORK")
  setBarsAndTexts(isIdle, idleSec)
end
