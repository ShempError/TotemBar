-- Offline test: core/cast.lua's pure decision functions (nextIndex,
-- findFilledSlot). castNext() itself touches CastSpellByName/GetTime
-- and is NOT covered here (in-game verification only). Run from repo
-- root:
--   lua50.exe tools/luatests/test_cast.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/cast.lua")

H.run("nextIndex: advances through slots and wraps", function()
    local n = table.getn(TotemBar.TOTEM_ELEMENTS)
    H.assert_eq(TotemBar.nextIndex(0, 0, 100, 2, n), 1, "no previous cast -> slot 1")
    H.assert_eq(TotemBar.nextIndex(1, 100, 100.5, 2, n), 2, "1 -> 2 within gap")
    H.assert_eq(TotemBar.nextIndex(2, 100.5, 101, 2, n), 3, "2 -> 3 within gap")
    H.assert_eq(TotemBar.nextIndex(3, 101, 101.5, 2, n), 4, "3 -> 4 within gap")
    H.assert_eq(TotemBar.nextIndex(4, 101.5, 102, 2, n), 1, "4 -> 1 wraps within gap")
end)

H.run("nextIndex: resets to 1 after gap exceeded", function()
    local n = table.getn(TotemBar.TOTEM_ELEMENTS)
    H.assert_eq(TotemBar.nextIndex(2, 100, 103, 2, n), 1, "3s gap > 2s allowed -> reset to slot 1")
    H.assert_eq(TotemBar.nextIndex(2, 100, 102, 2, n), 3, "exactly 2s (not exceeded) still advances normally")
end)

H.run("nextIndex: single-slot case always returns 1", function()
    H.assert_eq(TotemBar.nextIndex(0, 0, 100, 2, 1), 1, "no previous cast, 1 slot -> 1")
    H.assert_eq(TotemBar.nextIndex(1, 100, 100.5, 2, 1), 1, "1 slot wraps back to itself")
end)

H.run("findFilledSlot: skips empty slots, preserves order", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    local chosen = { Earth = "Stoneclaw Totem", Air = "Windfury Totem" }
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 1), 2, "starting at 1, first filled is Earth (slot 2)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 3), 4, "starting at 3, first filled is Air (slot 4)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 4), 4, "starting exactly on a filled slot stays there")
end)

H.run("findFilledSlot: wraps around the end of the list", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    local chosen = { Water = "Healing Stream Totem" }
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 4), 3, "wraps from 4 around to 3 (Water)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 3), 3, "starting exactly on the only filled slot")
end)

H.run("findFilledSlot: nothing filled returns nil", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    H.assert_eq(TotemBar.findFilledSlot({}, elements, 1), nil, "no slots chosen -> nil")
end)

H.run("findFilledSlot: single-element list", function()
    local elements = { "Fire" }
    H.assert_eq(TotemBar.findFilledSlot({ Fire = "Searing Totem" }, elements, 1), 1, "single slot filled -> 1")
    H.assert_eq(TotemBar.findFilledSlot({}, elements, 1), nil, "single slot empty -> nil")
end)

H.summary()
