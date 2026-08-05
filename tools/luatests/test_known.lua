-- Offline test: core/known.lua's pure knownTotems() filter. Run from
-- repo root:
--   lua50.exe tools/luatests/test_known.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/known.lua")

H.run("known: filters to the element's known totems", function()
    local spells = { "Searing Totem", "Healing Stream Totem", "Fireball", "Frost Nova" }
    local fire = TotemBar.knownTotems(spells, "Fire")
    H.assert_eq(table.getn(fire), 1, "one known Fire totem")
    H.assert_eq(fire[1], "Searing Totem", "Searing Totem found")
end)

H.run("known: totems the player doesn't know are omitted", function()
    local spells = { "Fireball" }
    local fire = TotemBar.knownTotems(spells, "Fire")
    H.assert_eq(table.getn(fire), 0, "no known Fire totems")
end)

H.run("known: non-totem spells are ignored entirely", function()
    local spells = { "Fireball", "Frost Nova", "Healing Stream Totem" }
    local water = TotemBar.knownTotems(spells, "Water")
    H.assert_eq(table.getn(water), 1, "one known Water totem")
    H.assert_eq(water[1], "Healing Stream Totem", "Healing Stream Totem found")
end)

H.run("known: unknown element returns empty", function()
    local spells = { "Searing Totem" }
    local result = TotemBar.knownTotems(spells, "Spirit")
    H.assert_eq(table.getn(result), 0, "unmapped element yields empty result")
end)

H.run("known: multiple known totems preserve static map order", function()
    local spells = { "Tremor Totem", "Earthbind Totem", "Stoneclaw Totem" }
    local earth = TotemBar.knownTotems(spells, "Earth")
    H.assert_eq(table.getn(earth), 3, "three known Earth totems")
    H.assert_eq(earth[1], "Earthbind Totem", "order preserved: Earthbind first")
    H.assert_eq(earth[2], "Stoneclaw Totem", "order preserved: Stoneclaw second")
    H.assert_eq(earth[3], "Tremor Totem", "order preserved: Tremor third")
end)

H.run("known: nil spell list yields empty result", function()
    local result = TotemBar.knownTotems(nil, "Fire")
    H.assert_eq(table.getn(result), 0, "nil spell list yields empty result")
end)

H.summary()
