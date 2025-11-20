-- modules/scanner_utils.lua
-- Shared utilities for ODMK3 Scanner Display

local M = {}

function M.matchRule(n, tags, rule)
    if rule.equals then
        for _, v in ipairs(rule.equals) do if n == v then return true end end
    end
    if rule.suffixes then
        for _, s in ipairs(rule.suffixes) do if n:sub(-#s) == s then return true end end
    end
    if rule.contains then
        for _, c in ipairs(rule.contains) do if n:find(c, 1, true) then return true end end
    end
    if rule.patterns then
        for _, p in ipairs(rule.patterns) do if n:match(p) then return true end end
    end
    if rule.tags and tags then
        for _, t in ipairs(rule.tags) do if tags[t] then return true end end
    end
    return false
end

function M.classifyColor(name, tags, cfg, defaultColor)
    local n = (name or ""):lower()
    local rules = (cfg and cfg.classificationRules) or {}
    for _, rule in ipairs(rules) do
        if M.matchRule(n, tags, rule) then
            local c = rule.colorName and cfg.colors and cfg.colors[rule.colorName]
            if c then return c end
        end
    end
    return defaultColor
end

function M.oreLabelFromName(name)
    if not name then return nil end
    local n = name
    n = n:gsub("^.-:", "")
    n = n:gsub("^deepslate_", "")
    if n:find("diamond_ore")      then return "Di" end
    if n:find("emerald_ore")      then return "Em" end
    if n:find("gold_ore")         then return "Au" end
    if n:find("iron_ore")         then return "Fe" end
    if n:find("copper_ore")       then return "Cu" end
    if n:find("coal_ore")         then return "C"  end
    if n:find("lapis_ore") or n:find("lapis") then return "Lz" end
    if n:find("redstone_ore")     then return "Rs" end
    if n:find("ancient_debris")   then return "Nt" end
    return nil
end

M.VIEW_DEF = {
    top   = {U="x", V="z", W="y", name="TOP (XZ)"},
    front = {U="x", V="y", W="z", name="FRONT (XY)"},
    side  = {U="z", V="y", W="x", name="SIDE (ZY)"},
}

function M.axisVal(b, axis) return b[axis] end

function M.centerFromBlocks(_)
    return { x = 0, y = 0, z = 0 }
end

function M.buildMap(blocks, viewKey, sliceThick, sliceOffset, cfg, showOreLabels, defaultColors)
    local vd = M.VIEW_DEF[viewKey] or M.VIEW_DEF.top
    local C = M.centerFromBlocks(blocks)
    local half = math.floor((sliceThick - 1) / 2)
    local wMin = C[vd.W] + sliceOffset - half
    local wMax = C[vd.W] + sliceOffset + (sliceThick - 1 - half)
    local pts = {}
    local ORE_COLOR   = defaultColors.ORE_COLOR
    local FLUID_COLOR = defaultColors.FLUID_COLOR
    local WOOD_COLOR  = defaultColors.WOOD_COLOR
    local POINT_COLOR = defaultColors.POINT_COLOR
    local prio = {[ORE_COLOR]=3, [FLUID_COLOR]=2, [WOOD_COLOR]=1, [POINT_COLOR]=0}
    for _, b in ipairs(blocks) do
        local w = M.axisVal(b, vd.W)
        if w >= wMin and w <= wMax then
            local du = M.axisVal(b, vd.U) - C[vd.U]
            local dv = M.axisVal(b, vd.V) - C[vd.V]
            local key = du .. "," .. dv
            local col = M.classifyColor(b.name or "", b.tags or {}, cfg, POINT_COLOR)
            local label = nil
            if showOreLabels and col == ORE_COLOR then
                label = M.oreLabelFromName(b.name or "")
            end
            local existing = pts[key]
            if (not existing) or prio[col] > prio[existing.c] then
                pts[key] = { c = col, label = label }
            end
        end
    end
    return pts, C
end

function M.uvToPixel(du, dv, gx1, gy1, gx2, gy2, radius)
    local gw, gh = gx2 - gx1 + 1, gy2 - gy1 + 1
    local nx = (du / radius + 1) / 2
    local ny = (-dv / radius + 1) / 2
    local px = gx1 + math.floor(nx * (gw - 1) + 0.5)
    local py = gy1 + math.floor(ny * (gh - 1) + 0.5)
    return px, py
end

function M.getGameTicks()
    return os.day() * 24000 + math.floor(os.time() * 1000 + 0.5)
end

function M.formatGameAge(lastTicks)
    if not lastTicks or lastTicks <= 0 then return "No data" end
    local ageTicks = M.getGameTicks() - lastTicks
    if ageTicks < 0 then ageTicks = 0 end
    local secs = math.floor(ageTicks / 20)
    if secs < 60 then return string.format("Age:%ds", secs) end
    local mins = math.floor(secs / 60)
    local remSecs = secs % 60
    if mins < 60 then
        if remSecs == 0 then return string.format("Age:%dm", mins) end
        return string.format("Age:%dm %ds", mins, remSecs)
    end
    local hours = math.floor(mins / 60)
    local remMins = mins % 60
    if hours < 24 then
        if remMins == 0 then return string.format("Age:%dh", hours) end
        return string.format("Age:%dh %dm", hours, remMins)
    end
    local days = math.floor(hours / 24)
    local remHours = hours % 24
    if remHours == 0 then return string.format("Age:%dd", days) end
    return string.format("Age:%dd %dh", days, remHours)
end

return M
