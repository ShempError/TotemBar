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

H.summary()
