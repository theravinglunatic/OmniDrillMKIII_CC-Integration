-- modules/scanner_orientation.lua
-- Encapsulates direction/view selection and slice cycling for ODMK3 Scanner

local M = {}

function M.computeSettings(cardinal, vertical, directionSettings)
    local dir
    if vertical == "U" or vertical == "D" then
        dir = vertical
    else
        dir = cardinal or "N"
    end
    local ds = directionSettings[dir] or directionSettings["N"]
    local view = ds.view
    local minOffset = ds.minOffset
    local maxOffset = ds.maxOffset

    local cycleDir
    local initOffset
    if dir == "W" or dir == "D" then
        cycleDir = -1
        initOffset = maxOffset
    else
        cycleDir = 1
        initOffset = math.min(minOffset, maxOffset)
    end

    return {
        direction = dir,
        view = view,
        cycleMinOffset = minOffset,
        cycleMaxOffset = maxOffset,
        cycleDirection = cycleDir,
        initSliceOffset = initOffset,
    }
end

function M.nextSliceOffset(state, currentOffset)
    local dir = state.direction
    local minOffset = state.cycleMinOffset
    local maxOffset = state.cycleMaxOffset
    local step = state.cycleDirection

    if dir == "W" or dir == "D" then
        local next = currentOffset + step
        if next < minOffset then
            return maxOffset
        end
        return next
    else
        local actualMin = math.min(minOffset, maxOffset)
        local actualMax = math.max(minOffset, maxOffset)
        local next = currentOffset + step
        if next > actualMax then
            return actualMin
        elseif next < actualMin then
            return actualMax
        end
        return next
    end
end

return M
