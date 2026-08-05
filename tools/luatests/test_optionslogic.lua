-- Offline test: core/optionslogic.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_optionslogic.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/optionslogic.lua")

local function round(n) return math.floor(n + 0.5) end

H.run("angleToOffset: cardinal angles on radius 100", function()
    local x, y = TotemBar.angleToOffset(0, 100)
    H.assert_eq(round(x), 100, "0deg x=100"); H.assert_eq(round(y), 0, "0deg y=0")
    x, y = TotemBar.angleToOffset(90, 100)
    H.assert_eq(round(x), 0, "90deg x=0"); H.assert_eq(round(y), 100, "90deg y=100")
    x, y = TotemBar.angleToOffset(180, 100)
    H.assert_eq(round(x), -100, "180deg x=-100"); H.assert_eq(round(y), 0, "180deg y=0")
    x, y = TotemBar.angleToOffset(270, 100)
    H.assert_eq(round(x), 0, "270deg x=0"); H.assert_eq(round(y), -100, "270deg y=-100")
end)

H.run("clampValue: below / within / above", function()
    H.assert_eq(TotemBar.clampValue(-1, 0, 5), 0, "below -> min")
    H.assert_eq(TotemBar.clampValue(3, 0, 5), 3, "within -> unchanged")
    H.assert_eq(TotemBar.clampValue(9, 0, 5), 5, "above -> max")
end)

H.run("macroSpec: fixed name/body/icon", function()
    local name, body, icon = TotemBar.macroSpec()
    H.assert_eq(name, "Totems", "macro name")
    H.assert_eq(body, "/script TotemBar.recallAndCastAll()", "macro body")
    H.assert_eq(icon, "Spell_Nature_TremorTotem", "macro icon (bare name)")
end)

-- Button order in every positions table: Fire, Earth, Water, Air, Recall,
-- DropSet (matches ui.lua's ApplyBarLayout button-list order).
local BUTTON_LABELS = { "Fire", "Earth", "Water", "Air", "Recall", "DropSet" }

local function assert_positions(layout, expected)
    local positions = TotemBar.BAR_LAYOUT_POSITIONS[layout]
    H.assert_eq(table.getn(positions), 6, layout .. " has 6 slots")
    for idx = 1, 6 do
        local label = layout .. " " .. BUTTON_LABELS[idx]
        H.assert_eq(positions[idx][1], expected[idx][1], label .. " col")
        H.assert_eq(positions[idx][2], expected[idx][2], label .. " row")
    end
end

H.run("BAR_LAYOUT_POSITIONS: 1x6 - one row of six", function()
    assert_positions("1x6", { {0,0}, {1,0}, {2,0}, {3,0}, {4,0}, {5,0} })
end)

H.run("BAR_LAYOUT_POSITIONS: 2x3 - elements as 2x2 block, utilities in col 3", function()
    -- User request: the four element totems fill the first two COLUMNS as a
    -- 2x2 block; Recall/DropSet stack in the third column.
    assert_positions("2x3", { {0,0}, {1,0}, {0,1}, {1,1}, {2,0}, {2,1} })
end)

H.run("BAR_LAYOUT_POSITIONS: 3x2 - elements as top 2x2 block, utility row below", function()
    assert_positions("3x2", { {0,0}, {1,0}, {0,1}, {1,1}, {0,2}, {1,2} })
end)

-- Optional DropSet button ("Show drop-all button", TotemBarDB.showDropSetButton):
-- when it is off, ui.lua's ApplyBarLayout leaves it out of the button list, so
-- only slots 1..5 are used. Pin that the first five slots of every layout are
-- exactly the six-button ones minus the tail - i.e. the element 2x2 block and
-- Recall must NOT move, and DropSet must stay the last entry of every table.
local function assert_visible_positions(layout, count, expected)
    local positions = TotemBar.BAR_LAYOUT_POSITIONS[layout]
    for idx = 1, count do
        local label = layout .. " w/o DropSet " .. BUTTON_LABELS[idx]
        H.assert_eq(positions[idx][1], expected[idx][1], label .. " col")
        H.assert_eq(positions[idx][2], expected[idx][2], label .. " row")
    end
end

H.run("BAR_LAYOUT_POSITIONS: DropSet is the last slot in every layout", function()
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["1x6"][6][1], 5, "1x6 DropSet col")
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["1x6"][6][2], 0, "1x6 DropSet row")
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["2x3"][6][1], 2, "2x3 DropSet col")
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["2x3"][6][2], 1, "2x3 DropSet row")
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["3x2"][6][1], 1, "3x2 DropSet col")
    H.assert_eq(TotemBar.BAR_LAYOUT_POSITIONS["3x2"][6][2], 2, "3x2 DropSet row")
end)

H.run("BAR_LAYOUT_POSITIONS: DropSet hidden - the other five keep their slots", function()
    assert_visible_positions("1x6", 5, { {0,0}, {1,0}, {2,0}, {3,0}, {4,0} })
    assert_visible_positions("2x3", 5, { {0,0}, {1,0}, {0,1}, {1,1}, {2,0} })
    assert_visible_positions("3x2", 5, { {0,0}, {1,0}, {0,1}, {1,1}, {0,2} })
end)

H.run("barDimensions: 1x6 - single row, no extra pitch", function()
    local w, h, rows = TotemBar.barDimensions(6, 6, 36, 10, 0)
    H.assert_eq(w, 286, "1x6 width")
    H.assert_eq(h, 56, "1x6 height")
    H.assert_eq(rows, 1, "1x6 rows")
end)

H.run("barDimensions: 2x3 - two rows, extra pitch 16", function()
    local w, h, rows = TotemBar.barDimensions(6, 3, 36, 10, 16)
    H.assert_eq(w, 148, "2x3 width")
    H.assert_eq(h, 118, "2x3 height")
    H.assert_eq(rows, 2, "2x3 rows")
end)

H.run("barDimensions: 3x2 - three rows, extra pitch 16", function()
    local w, h, rows = TotemBar.barDimensions(6, 2, 36, 10, 16)
    H.assert_eq(w, 102, "3x2 width")
    H.assert_eq(h, 180, "3x2 height")
    H.assert_eq(rows, 3, "3x2 rows")
end)

-- Frame size with and without the optional DropSet button, using the pitch
-- ui.lua actually passes today (rowPitchExtra = 0 in ApplyBarLayout), so these
-- are the live pixel sizes. Expectation: only "1x6" shrinks (its row really is
-- one button shorter); "2x3"/"3x2" still need every column and row for five
-- buttons and must keep their exact size - shrinking them would mean tearing
-- the element 2x2 block apart, which the layouts above deliberately protect.
H.run("barDimensions: 1x6 with vs. without DropSet (live pitch 0)", function()
    local w, h, rows = TotemBar.barDimensions(6, 6, 36, 10, 0)
    H.assert_eq(w, 286, "1x6 width, 6 buttons"); H.assert_eq(h, 56, "1x6 height, 6 buttons"); H.assert_eq(rows, 1, "1x6 rows, 6 buttons")
    w, h, rows = TotemBar.barDimensions(5, 6, 36, 10, 0)
    H.assert_eq(w, 240, "1x6 width, 5 buttons (shrinks by one button+gap)")
    H.assert_eq(h, 56, "1x6 height, 5 buttons (unchanged)")
    H.assert_eq(rows, 1, "1x6 rows, 5 buttons")
end)

H.run("barDimensions: 2x3 with vs. without DropSet (live pitch 0)", function()
    local w, h, rows = TotemBar.barDimensions(6, 3, 36, 10, 0)
    H.assert_eq(w, 148, "2x3 width, 6 buttons"); H.assert_eq(h, 102, "2x3 height, 6 buttons"); H.assert_eq(rows, 2, "2x3 rows, 6 buttons")
    w, h, rows = TotemBar.barDimensions(5, 3, 36, 10, 0)
    H.assert_eq(w, 148, "2x3 width, 5 buttons (unchanged)")
    H.assert_eq(h, 102, "2x3 height, 5 buttons (unchanged)")
    H.assert_eq(rows, 2, "2x3 rows, 5 buttons")
end)

H.run("barDimensions: 3x2 with vs. without DropSet (live pitch 0)", function()
    local w, h, rows = TotemBar.barDimensions(6, 2, 36, 10, 0)
    H.assert_eq(w, 102, "3x2 width, 6 buttons"); H.assert_eq(h, 148, "3x2 height, 6 buttons"); H.assert_eq(rows, 3, "3x2 rows, 6 buttons")
    w, h, rows = TotemBar.barDimensions(5, 2, 36, 10, 0)
    H.assert_eq(w, 102, "3x2 width, 5 buttons (unchanged)")
    H.assert_eq(h, 148, "3x2 height, 5 buttons (unchanged)")
    H.assert_eq(rows, 3, "3x2 rows, 5 buttons")
end)

-- Same five-button case against the formula pitch the six-button pins above
-- use (rowPitchExtra 16), so both halves of each pair stay comparable, plus
-- the slider maximum where the 1x6 saving is largest.
H.run("barDimensions: DropSet hidden, extra pitch 16 / slider max gap", function()
    local w, h, rows = TotemBar.barDimensions(5, 3, 36, 10, 16)
    H.assert_eq(w, 148, "2x3 width @extra16"); H.assert_eq(h, 118, "2x3 height @extra16"); H.assert_eq(rows, 2, "2x3 rows @extra16")
    w, h, rows = TotemBar.barDimensions(5, 2, 36, 10, 16)
    H.assert_eq(w, 102, "3x2 width @extra16"); H.assert_eq(h, 180, "3x2 height @extra16"); H.assert_eq(rows, 3, "3x2 rows @extra16")
    w, h, rows = TotemBar.barDimensions(5, 6, 36, 30, 0)
    H.assert_eq(w, 360, "1x6 width @30px, 5 buttons (426 with DropSet)")
    H.assert_eq(h, 96, "1x6 height @30px, 5 buttons"); H.assert_eq(rows, 1, "1x6 rows @30px, 5 buttons")
end)

H.run("barDimensions: column cap only ever shrinks a too-wide grid", function()
    -- count >= cols: cap is a no-op, all the six-button pins stay valid.
    local w, h, rows = TotemBar.barDimensions(6, 6, 36, 10, 0)
    H.assert_eq(w, 286, "count == cols -> untouched")
    w, h, rows = TotemBar.barDimensions(5, 3, 36, 10, 0)
    H.assert_eq(w, 148, "count > cols -> untouched")
    -- count < cols: never more columns than buttons (guards any future
    -- optional button, not just DropSet).
    w, h, rows = TotemBar.barDimensions(4, 6, 36, 10, 0)
    H.assert_eq(w, 194, "4 buttons in a 6-wide row -> 4 columns")
    H.assert_eq(rows, 1, "4 buttons in a 6-wide row -> 1 row")
    w, h, rows = TotemBar.barDimensions(1, 6, 36, 10, 0)
    H.assert_eq(w, 56, "1 button in a 6-wide row -> 1 column")
    H.assert_eq(h, 56, "1 button -> single-row height")
    H.assert_eq(rows, 1, "1 button -> 1 row")
end)

-- Button-spacing slider bounds (range 10-30px, see the options panel's
-- "Button spacing" slider / ui.lua's SetButtonGap): pin the pixel math for
-- both slider extremes across all three bar layouts, so a change to
-- barDimensions can't silently break the spacing feature.
H.run("barDimensions: button spacing 10px (slider min) across all layouts", function()
    local w, h, rows = TotemBar.barDimensions(6, 6, 36, 10, 0)
    H.assert_eq(w, 286, "1x6 width @10px"); H.assert_eq(h, 56, "1x6 height @10px"); H.assert_eq(rows, 1, "1x6 rows @10px")
    w, h, rows = TotemBar.barDimensions(6, 3, 36, 10, 16)
    H.assert_eq(w, 148, "2x3 width @10px"); H.assert_eq(h, 118, "2x3 height @10px"); H.assert_eq(rows, 2, "2x3 rows @10px")
    w, h, rows = TotemBar.barDimensions(6, 2, 36, 10, 16)
    H.assert_eq(w, 102, "3x2 width @10px"); H.assert_eq(h, 180, "3x2 height @10px"); H.assert_eq(rows, 3, "3x2 rows @10px")
end)

H.run("barDimensions: button spacing 30px (slider max) across all layouts", function()
    local w, h, rows = TotemBar.barDimensions(6, 6, 36, 30, 0)
    H.assert_eq(w, 426, "1x6 width @30px"); H.assert_eq(h, 96, "1x6 height @30px"); H.assert_eq(rows, 1, "1x6 rows @30px")
    w, h, rows = TotemBar.barDimensions(6, 3, 36, 30, 16)
    H.assert_eq(w, 228, "2x3 width @30px"); H.assert_eq(h, 178, "2x3 height @30px"); H.assert_eq(rows, 2, "2x3 rows @30px")
    w, h, rows = TotemBar.barDimensions(6, 2, 36, 30, 16)
    H.assert_eq(w, 162, "3x2 width @30px"); H.assert_eq(h, 260, "3x2 height @30px"); H.assert_eq(rows, 3, "3x2 rows @30px")
end)

H.run("clampValue: button-gap slider bounds (10..30)", function()
    H.assert_eq(TotemBar.clampValue(9, 10, 30), 10, "9 -> 10 (below min)")
    H.assert_eq(TotemBar.clampValue(31, 10, 30), 30, "31 -> 30 (above max)")
    H.assert_eq(TotemBar.clampValue(10, 10, 30), 10, "10 -> 10 (at min)")
    H.assert_eq(TotemBar.clampValue(30, 10, 30), 30, "30 -> 30 (at max)")
end)

H.summary()
