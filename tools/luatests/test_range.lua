-- Offline test: core/known.lua's pure parseRange() tooltip-line parser.
-- totemRange() itself (the tooltip-scanning wrapper) touches WoW API
-- (GetSpellName/CreateFrame/GameTooltip) and is NOT covered here
-- (in-game verification only). Run from repo root:
--   lua50.exe tools/luatests/test_range.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/known.lua")

H.run("parseRange: finds an English yards radius", function()
    local lines = {
        "Totem of the Elements",
        "Reduces the movement speed of enemies within 20 yards by 50%.",
        "Lasts 45 sec.",
    }
    H.assert_eq(TotemBar.parseRange(lines), 20, "20 yards found")
end)

H.run("parseRange: finds a German meters radius (locale-tolerant)", function()
    local lines = {
        "Erdungstotem",
        "Alle 5 Sek. wird ein Gegner im Umkreis von 30 Metern angegriffen.",
    }
    H.assert_eq(TotemBar.parseRange(lines), 30, "30 meters found")
end)

H.run("parseRange: no radius anywhere returns nil", function()
    local lines = {
        "Totemic Recall",
        "Instantly returns all totems to your hand.",
        "",
    }
    H.assert_eq(TotemBar.parseRange(lines), nil, "no yard/meter phrase -> nil")
end)

H.run("parseRange: empty table returns nil", function()
    H.assert_eq(TotemBar.parseRange({}), nil, "empty lines table -> nil")
end)

H.run("parseRange: nil input returns nil", function()
    H.assert_eq(TotemBar.parseRange(nil), nil, "nil lines -> nil")
end)

H.run("parseRange: tolerates nil/empty holes among the lines", function()
    local lines = { nil, "", nil, "Enemies within 8 yards take damage.", nil }
    H.assert_eq(TotemBar.parseRange(lines), 8, "skips nil/empty entries, finds the later match")
end)

H.run("parseRange: scans in order, first match wins", function()
    local lines = {
        "Restores mana within 40 yards.",
        "Also works within 12 meters for an unrelated reason.",
    }
    H.assert_eq(TotemBar.parseRange(lines), 40, "first line's radius wins over a later one")
end)

H.run("parseRange: singular 'yard' (no trailing s) still matches", function()
    local lines = { "Range: 1 yard." }
    H.assert_eq(TotemBar.parseRange(lines), 1, "singular yard matches too")
end)

H.summary()
