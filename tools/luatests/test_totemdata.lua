-- Offline test: core/totemdata.lua (pure). Run from repo root:
--   lua50.exe tools/luatests/test_totemdata.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")

H.run("totemdata: element list", function()
    H.assert_eq(table.getn(TotemBar.TOTEM_ELEMENTS), 4, "4 elements")
    H.assert_eq(TotemBar.TOTEM_ELEMENTS[1], "Fire", "element 1 is Fire")
    H.assert_eq(TotemBar.TOTEM_ELEMENTS[2], "Earth", "element 2 is Earth")
    H.assert_eq(TotemBar.TOTEM_ELEMENTS[3], "Water", "element 3 is Water")
    H.assert_eq(TotemBar.TOTEM_ELEMENTS[4], "Air", "element 4 is Air")
end)

H.run("totemdata: elementOf resolves known totems", function()
    H.assert_eq(TotemBar.elementOf("Searing Totem"), "Fire", "Searing Totem is Fire")
    H.assert_eq(TotemBar.elementOf("Stoneclaw Totem"), "Earth", "Stoneclaw Totem is Earth")
    H.assert_eq(TotemBar.elementOf("Healing Stream Totem"), "Water", "Healing Stream Totem is Water")
    H.assert_eq(TotemBar.elementOf("Windfury Totem"), "Air", "Windfury Totem is Air")
end)

H.run("totemdata: elementOf handles non-matches", function()
    H.assert_eq(TotemBar.elementOf("Fireball"), nil, "non-totem spell has no element")
    H.assert_eq(TotemBar.elementOf(nil), nil, "nil name has no element")
    H.assert_eq(TotemBar.elementOf("Nonexistent Totem"), nil, "unknown totem name has no element")
end)

-- ui.lua's hover-flyout icon pool is sized from this. It used to be a
-- hard-coded 6 ("most totems any single element has"), which was wrong: Air
-- has SEVEN totems, so with the Air slot empty (the flyout then lists ALL
-- known Air totems, not "all minus the chosen one") the 7th entry -- Tranquil
-- Air Totem -- was silently dropped and could not be cast or made default
-- from the bar at all.
H.run("maxTotemsPerElement: matches the largest element list in the data", function()
    local expected = 0
    for i = 1, table.getn(TotemBar.TOTEM_ELEMENTS) do
        local n = table.getn(TotemBar.TOTEMS_BY_ELEMENT[TotemBar.TOTEM_ELEMENTS[i]])
        if n > expected then
            expected = n
        end
    end
    H.assert_eq(TotemBar.maxTotemsPerElement(), expected, "computed from the data, not hard-coded")
    H.assert_eq(TotemBar.maxTotemsPerElement(), 7, "today that is Air's 7 totems")
    H.assert_eq(table.getn(TotemBar.TOTEMS_BY_ELEMENT.Air), 7, "Air really does list 7 totems")
end)

H.summary()
