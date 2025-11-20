-- modules/scanner_render.lua
-- Rendering helpers for Scanner Display (map area, side pane, hazard blink)

local M = {}

local function mwriteXY(mon, x, y, text, fg, bg)
  if fg then mon.setTextColor(fg) end
  if bg then mon.setBackgroundColor(bg) end
  mon.setCursorPos(x, y)
  mon.write(text)
end

local function fillRect(mon, x1, y1, x2, y2, bg)
  mon.setBackgroundColor(bg)
  for y = y1, y2 do
    mon.setCursorPos(x1, y)
    mon.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function drawBox(mon, x1, y1, x2, y2, fg)
  mon.setTextColor(fg)
  for x = x1, x2 do
    mon.setCursorPos(x, y1); mon.write("-")
    mon.setCursorPos(x, y2); mon.write("-")
  end
  for y = y1, y2 do
    mon.setCursorPos(x1, y); mon.write("|")
    mon.setCursorPos(x2, y); mon.write("|")
  end
end

function M.renderMapArea(mon, p)
  if not mon or not p.currentData then return end
  local w, h = mon.getSize()
  local leftWidth = math.floor(w * 3 / 4)
  if leftWidth < 8 then leftWidth = w - 4 end
  local mapX1, mapY1 = 1, 1
  local mapX2, mapY2 = leftWidth, h

  drawBox(mon, mapX1, mapY1, mapX2, mapY2, p.FRAME_COLOR)

  local pts = p.buildMapFn(p.currentData, p.currentView, p.sliceThick, p.sliceOffset)

  local gx1, gy1 = mapX1 + 1, mapY1 + 1
  local gx2, gy2 = mapX2 - 1, mapY2 - 1
  fillRect(mon, gx1, gy1, gx2, gy2, p.BG_COLOR)

  for py = gy1, gy2 do
    for px = gx1, gx2 do
      local gw, gh = gx2 - gx1 + 1, gy2 - 1 - (gy1 - 1)
      local nx = (px - gx1) / math.max(gw - 1, 1) * 2 - 1
      local ny = (py - gy1) / math.max(gh - 1, 1) * 2 - 1
      local du = math.floor(nx * p.currentRadius + 0.5)
      local dv = math.floor(-ny * p.currentRadius + 0.5)
      local val = pts[du .. "," .. dv]
      if val then
        mon.setBackgroundColor(val.c)
        mon.setCursorPos(px, py)
        mon.write(" ")
      end
    end
  end

  if p.SHOW_ORE_LABELS then
    for key, val in pairs(pts) do
      local label = val.label
      if label then
        local sdu, sdv = key:match("^(-?%d+),(-?%d+)$")
        if sdu and sdv then
          local du, dv = tonumber(sdu), tonumber(sdv)
          local px, py = p.uvToPixelFn(du, dv, gx1, gy1, gx2, gy2, p.currentRadius)
          if px >= gx1 and px <= gx2 and py >= gy1 and py <= gy2 then
            mon.setBackgroundColor(val.c)
            mon.setTextColor(colors.black)
            mon.setCursorPos(px, py)
            mon.write(label:sub(1,1))
            if #label > 1 and px + 1 <= gx2 then
              mon.setCursorPos(px + 1, py)
              mon.write(label:sub(2,2))
            end
          end
        end
      end
    end
  end

  local mx, my = p.uvToPixelFn(0, 0, gx1, gy1, gx2, gy2, p.currentRadius)
  if mx >= gx1 and mx <= gx2 and my >= gy1 and my <= gy2 then
    mon.setTextColor(p.MARK_FG)
    mon.setBackgroundColor(p.MARK_BG)
    mon.setCursorPos(mx, my)
    mon.write(p.MARK_CHAR)
  end
end

function M.renderSidePane(mon, p, cache, cfg)
  local w, h = mon.getSize()
  local leftWidth = math.floor(w * 3 / 4)
  if leftWidth < 8 then leftWidth = w - 4 end
  local legendX1 = leftWidth + 1
  local legendX2 = w
  local legendWidth = legendX2 - legendX1 + 1
  local topEnd = math.floor(h / 3)
  local midStart = topEnd + 1
  local midEnd = math.floor(2 * h / 3)
  local botStart = midEnd + 1

  fillRect(mon, legendX1, 1, legendX2, h, p.BG_COLOR)

  local line = 1
  local headerText = "LEGEND"
  fillRect(mon, legendX1, line, legendX2, line, p.HEADER_BG)
  mwriteXY(mon, legendX1 + math.floor((legendWidth - #headerText) / 2), line, headerText, p.HEADER_FG, p.HEADER_BG)
  line = line + 1

  mwriteXY(mon, legendX1, line, p.VIEW_DEF[p.currentView].name, p.STATUS_COLOR, p.BG_COLOR); line = line + 1
  mwriteXY(mon, legendX1, line, p.formatGameAgeFn(p.lastScanGameTicks), p.STATUS_COLOR, p.BG_COLOR); line = line + 1
  if p.lastError and line <= topEnd then mwriteXY(mon, legendX1, line, "ERR", p.ERROR_COLOR, p.BG_COLOR); line = line + 1 end
  if p.scanInProgress and line <= topEnd then mwriteXY(mon, legendX1, line, "Scanning...", colors.yellow, p.BG_COLOR); line = line + 1 end

  if next(cache.legendCounts) then
    for label, cnt in pairs(cache.legendCounts) do
      if line > topEnd then break end
      mwriteXY(mon, legendX1, line, string.format("%s:%d", label, cnt), p.STATUS_COLOR, p.BG_COLOR); line = line + 1
    end
  else
    if line <= topEnd then mwriteXY(mon, legendX1, line, "No ores", colors.lightGray, p.BG_COLOR); line = line + 1 end
  end
  if line <= topEnd then
    local relayTxt = p.relayOnline and "Relay:On" or "Relay:Off"
    mwriteXY(mon, legendX1, line, relayTxt, p.STATUS_COLOR, p.BG_COLOR); line = line + 1
  end
  if p.waitingCooldown and line <= topEnd then
    local remain = math.max(0, math.floor((p.pendingScanEta - os.epoch("utc")) / 1000))
    mwriteXY(mon, legendX1, line, string.format("Wait:%ds", remain), colors.yellow, p.BG_COLOR); line = line + 1
  elseif p.relayCooldownMs and p.relayCooldownMs > 0 and line <= topEnd then
    mwriteXY(mon, legendX1, line, string.format("CD:%ds", math.floor(p.relayCooldownMs/1000)), colors.lightGray, p.BG_COLOR); line = line + 1
  end

  if midStart <= midEnd then
    fillRect(mon, legendX1, midStart, legendX2, midStart, p.HEADER_BG)
    mwriteXY(mon, legendX1 + math.floor((legendWidth - #"NEARBY POIs") / 2), midStart, "NEARBY POIs", p.HEADER_FG, p.HEADER_BG)
    local pline = midStart + 1
    for _, rule in ipairs(cfg.poiRules or {}) do
      if pline > midEnd then break end
      if cache.poiFound[rule.label] then
        local col = (rule.colorName and cfg.colors[rule.colorName]) or p.STATUS_COLOR
        mwriteXY(mon, legendX1, pline, rule.label, col, p.BG_COLOR)
        pline = pline + 1
      end
    end
  end

  local hazardStart = botStart
  if hazardStart <= h then
    fillRect(mon, legendX1, hazardStart, legendX2, hazardStart, p.HEADER_BG)
    mwriteXY(mon, legendX1 + math.floor((legendWidth - #"NEARBY HAZARDS:") / 2), hazardStart, "NEARBY HAZARDS:", p.HEADER_FG, p.HEADER_BG)
    local hline = hazardStart + 1
    local hazardFound = cache.hazardFound or {}
    local blinkOn = (math.floor(os.clock() * 2) % 2) == 0
    for _, rule in ipairs(cfg.hazardRules or {}) do
      if hline > h then break end
      if hazardFound[rule.label] then
        local col = (rule.colorName and cfg.colors[rule.colorName]) or p.STATUS_COLOR
        if rule.blink then
          fillRect(mon, legendX1, hline, legendX2, hline, p.BG_COLOR)
          if blinkOn then mwriteXY(mon, legendX1, hline, rule.label, col, p.BG_COLOR) end
        else
          mwriteXY(mon, legendX1, hline, rule.label, col, p.BG_COLOR)
        end
        hline = hline + 1
      end
    end
  end
end

function M.renderHazardBlinkUpdate(mon, p, cache, cfg)
  local w, h = mon.getSize()
  local leftWidth = math.floor(w * 3 / 4)
  if leftWidth < 8 then leftWidth = w - 4 end
  local legendX1 = leftWidth + 1
  local legendX2 = w
  local topEnd = math.floor(h / 3)
  local midStart = topEnd + 1
  local midEnd = math.floor(2 * h / 3)
  local botStart = midEnd + 1

  local hazardStart = botStart
  if hazardStart > h then return end
  local hline = hazardStart + 1
  local hazardFound = cache.hazardFound or {}
  local blinkOn = (math.floor(os.clock() * 2) % 2) == 0
  for _, rule in ipairs(cfg.hazardRules or {}) do
    if hline > h then break end
    if hazardFound[rule.label] then
      if rule.blink then
        fillRect(mon, legendX1, hline, legendX2, hline, p.BG_COLOR)
        if blinkOn then
          local col = (rule.colorName and cfg.colors[rule.colorName]) or p.STATUS_COLOR
          mwriteXY(mon, legendX1, hline, rule.label, col, p.BG_COLOR)
        end
      end
      hline = hline + 1
    end
  end
end

-- Lightweight refresh for the scan age line (line 3 of side pane)
function M.renderStatusAgeUpdate(mon, p)
  local w, h = mon.getSize()
  local leftWidth = math.floor(w * 3 / 4)
  if leftWidth < 8 then leftWidth = w - 4 end
  local legendX1 = leftWidth + 1
  local legendX2 = w
  local ageLine = 3
  fillRect(mon, legendX1, ageLine, legendX2, ageLine, p.BG_COLOR)
  mwriteXY(mon, legendX1, ageLine, p.formatGameAgeFn(p.lastScanGameTicks), p.STATUS_COLOR, p.BG_COLOR)
end

-- Render the no-data splash screen with centered messages and status line
function M.renderNoData(mon, p)
  if not mon then return end

  mon.setBackgroundColor(p.BG_COLOR)
  mon.clear()
  mon.setCursorPos(1, 1)

  local w, h = mon.getSize()
  local msg1 = "Omni-Drill MKIII Geo Scanner"
  local msg2
  if p.relayOnline then
    if p.scanInProgress then
      msg2 = "Performing scan..."
    elseif p.scanRequestTime > 0 and (os.epoch("utc") - p.scanRequestTime) > 8000 then
      msg2 = "Scan delayed - retrying..."
    else
      msg2 = "Awaiting scan data..."
    end
  else
    msg2 = "Connecting to scanner relay..."
  end
  local msg3 = p.lastError and ("Error: " .. p.lastError) or ""

  mwriteXY(mon, math.floor((w - #msg1) / 2) + 1, math.floor(h / 2) - 1, msg1, p.STATUS_COLOR, p.BG_COLOR)
  mwriteXY(mon, math.floor((w - #msg2) / 2) + 1, math.floor(h / 2), msg2, p.STATUS_COLOR, p.BG_COLOR)
  if msg3 ~= "" then
    mwriteXY(mon, math.floor((w - #msg3) / 2) + 1, math.floor(h / 2) + 1, msg3, p.ERROR_COLOR, p.BG_COLOR)
  end

  local ageTxt = p.lastStatusResponseTime == 0 and "?" or math.floor((os.epoch("utc") - p.lastStatusResponseTime)/1000).."s"
  mwriteXY(mon, 1, h, string.format("Relay:%s (last:%s)", p.relayOnline and "On" or "Off", ageTxt), colors.lightGray, p.BG_COLOR)
end

return M
