-- modules/scanner_cache.lua
-- Computes cached aggregates for the Scanner side pane (LEGEND, POIs, HAZARDS)

local M = {}

-- params expected fields:
-- currentData, currentView, sliceThick, cycleMinOffset, cycleMaxOffset,
-- VIEW_DEF, classifyColorFn, oreLabelFromNameFn, centerFromBlocksFn, axisValFn,
-- ORE_COLOR
function M.recompute(params)
  local cache = { legendCounts = {}, poiFound = {}, hazardFound = {} }
  local data = params.currentData
  if not data or #data == 0 then return cache end

  local vd = params.VIEW_DEF[params.currentView] or params.VIEW_DEF.top
  local C = params.centerFromBlocksFn(data)

  local half = math.floor((params.sliceThick - 1) / 2)
  local rangeMinOffset = math.min(params.cycleMinOffset, params.cycleMaxOffset)
  local rangeMaxOffset = math.max(params.cycleMinOffset, params.cycleMaxOffset)
  local wRangeMin = C[vd.W] + rangeMinOffset - half
  local wRangeMax = C[vd.W] + rangeMaxOffset + (params.sliceThick - 1 - half)

  -- Count distinct labels for early exit
  local totalPoiLabels, poiSeenLabels = 0, {}
  for _, rule in ipairs(params.poiRules or {}) do
    if not poiSeenLabels[rule.label] then poiSeenLabels[rule.label] = true; totalPoiLabels = totalPoiLabels + 1 end
  end
  local totalHazardLabels, hazardSeenLabels = 0, {}
  for _, rule in ipairs(params.hazardRules or {}) do
    if not hazardSeenLabels[rule.label] then hazardSeenLabels[rule.label] = true; totalHazardLabels = totalHazardLabels + 1 end
  end

  local poiFoundCount, hazardFoundCount = 0, 0

  for _, b in ipairs(data) do
    local wCoord = params.axisValFn(b, vd.W)
    if wCoord >= wRangeMin and wCoord <= wRangeMax then
      local n = (b.name or ""):lower()
      local tags = b.tags or {}

      -- Legend ore counts
      local col = params.classifyColorFn(b.name or "", tags)
      if col == params.ORE_COLOR then
        local label = params.oreLabelFromNameFn(b.name or "")
        if label then cache.legendCounts[label] = (cache.legendCounts[label] or 0) + 1 end
      end

      -- POIs
      if poiFoundCount < totalPoiLabels then
        for _, rule in ipairs(params.poiRules or {}) do
          if not cache.poiFound[rule.label] and params.matchRuleFn(n, tags, rule) then
            cache.poiFound[rule.label] = true
            poiFoundCount = poiFoundCount + 1
            if poiFoundCount >= totalPoiLabels then break end
          end
        end
      end

      -- Hazards
      if hazardFoundCount < totalHazardLabels then
        for _, rule in ipairs(params.hazardRules or {}) do
          if not cache.hazardFound[rule.label] and params.matchRuleFn(n, tags, rule) then
            cache.hazardFound[rule.label] = true
            hazardFoundCount = hazardFoundCount + 1
            if hazardFoundCount >= totalHazardLabels then break end
          end
        end
      end

      if poiFoundCount >= totalPoiLabels and hazardFoundCount >= totalHazardLabels then
        -- continue counting ores only
      end
    end
  end

  return cache
end

return M
