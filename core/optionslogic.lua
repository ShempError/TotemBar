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

-- Bar-layout grid data + math (feature: selectable 1x6 / 2x3 / 3x2 bar
-- arrangement, see ui.lua's ApplyBarLayout). Pure so the button positions
-- and pixel-size math can be pinned offline instead of eyeballed in-game.

-- Explicit per-layout button positions {col, row} (0-based), button order:
-- Fire, Earth, Water, Air, Recall, DropSet. "2x3" groups the four element
-- totems as a 2x2 block in the first two columns (user request); "3x2"
-- groups them as the top 2x2 block with the utility row below.
TotemBar.BAR_LAYOUT_POSITIONS = {
    ["1x6"] = { {0,0},{1,0},{2,0},{3,0},{4,0},{5,0} },
    ["2x3"] = { {0,0},{1,0},{0,1},{1,1},{2,0},{2,1} },
    ["3x2"] = { {0,0},{1,0},{0,1},{1,1},{0,2},{1,2} },
}

-- Pixel dimensions of the bar frame for a grid of `count` buttons arranged
-- in `cols` columns of `size`x`size` buttons with `gap` spacing. `rowPitchExtra`
-- widens the vertical pitch between rows (multi-row layouts: room for the
-- timer text hanging below each row plus the next row's ring overhang - see
-- ui.lua's BUTTON_GAP comment); pass 0 for a single row.
-- height = top gap + rows*size + (rows-1)*(gap+extra) + bottom gap.
function TotemBar.barDimensions(count, cols, size, gap, rowPitchExtra)
    local rows = math.ceil(count / cols)
    local width = cols * (size + gap) + gap
    local height = gap + rows * size + (rows - 1) * (gap + rowPitchExtra) + gap
    return width, height, rows
end
