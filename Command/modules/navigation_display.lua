-- modules/navigation_display.lua (Pocket Primary)
-- Scanner view control logic (no rendering on pocket UI)

local NavigationDisplay = {}
local Config = require("modules.config")

-- Cycling state variables
local currentDirection = "N"
local cycleMinOffset = -12
local cycleMaxOffset = -2
local cycleDirection = -1

local DIRECTION_SETTINGS = {
    N = {view = "front", minOffset = -12, maxOffset = -2},
    W = {view = "side",  minOffset = -12, maxOffset = -2},
    F = {view = "front", minOffset = -12, maxOffset = -2},
    D = {view = "top",   minOffset = -12, maxOffset = -2},
    E = {view = "side",  minOffset = 2,  maxOffset = 12},
    S = {view = "front", minOffset = 2,  maxOffset = 12},
    U = {view = "top",   minOffset = 2,  maxOffset = 12},
}

function NavigationDisplay.updateDisplaySettings(systemState)
    local newDirection
    if systemState.currentVertical == "U" or systemState.currentVertical == "D" then
        newDirection = systemState.currentVertical
    else
        newDirection = systemState.currentCardinal
    end

    if newDirection and DIRECTION_SETTINGS[newDirection] and newDirection ~= currentDirection then
        currentDirection = newDirection
        local settings = DIRECTION_SETTINGS[currentDirection]
        systemState.currentView = settings.view
        cycleMinOffset = settings.minOffset
        cycleMaxOffset = settings.maxOffset

        local actualMin = math.min(cycleMinOffset, cycleMaxOffset)
        local actualMax = math.max(cycleMinOffset, cycleMaxOffset)

        if currentDirection == "W" or currentDirection == "D" then
            cycleDirection = -1
            systemState.sliceOffset = cycleMaxOffset
        else
            cycleDirection = 1
            systemState.sliceOffset = actualMin
        end
    end

    return systemState
end

return NavigationDisplay
