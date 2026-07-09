-- TotemBar - core/optionslogic.lua
-- PURE helpers for the options panel + minimap button (no WoW API), so the
-- fiddly bits (orbit math, slider clamping, the macro contract) are
-- offline-testable under real Lua 5.0. The UI (minimap.lua / options.lua)
-- calls these.

TotemBar = TotemBar or {}

-- Orbit offset (x, y) for a minimap button at angleDeg on a circle of the
-- given radius. 0deg -> (radius,0); 90 -> (0,radius); 180 -> (-radius,0).
function TotemBar.angleToOffset(angleDeg, radius)
    local rad = math.rad(angleDeg)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

-- Clamp v into [minVal, maxVal].
function TotemBar.clampValue(v, minVal, maxVal)
    if v < minVal then
        return minVal
    end
    if v > maxVal then
        return maxVal
    end
    return v
end

-- The fixed spec for the "Totems" convenience macro: name, body, and a BARE
-- icon file name (no Interface\Icons\ prefix, no extension - TurtleWoW's
-- CreateMacro/EditMacro prepend the path themselves).
function TotemBar.macroSpec()
    return "Totems", "/script TotemBar.recallAndCastAll()", "Spell_Nature_TremorTotem"
end
