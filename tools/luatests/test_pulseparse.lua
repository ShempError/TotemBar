-- Offline test: core/pulseparse.lua (periodic combat line -> totem name).
-- Run from repo root: lua50.exe tools/luatests/test_pulseparse.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/pulsedata.lua")
dofile("core/pulseparse.lua")

H.run("parseSelfGain: mana gain via buff-name alias", function()
    H.assert_eq(TotemBar.parseSelfGain("You gain 10 Mana from Mana Spring."),
        "Mana Spring Totem", "Mana Spring buff line")
    H.assert_eq(TotemBar.parseSelfGain("You gain 123 Mana from Mana Spring."),
        "Mana Spring Totem", "multi-digit gain")
end)

H.run("parseSelfGain: health gain wording", function()
    H.assert_eq(TotemBar.parseSelfGain("You gain 6 health from Healing Stream."),
        "Healing Stream Totem", "lowercase health wording")
    H.assert_eq(TotemBar.parseSelfGain("You gain 6 Health from Healing Stream."),
        "Healing Stream Totem", "capitalized Health wording")
end)

H.run("parseSelfGain: totem-as-caster heal shape", function()
    H.assert_eq(TotemBar.parseSelfGain("Healing Stream Totem heals you for 6."),
        "Healing Stream Totem", "totem heals you")
    H.assert_eq(TotemBar.parseSelfGain("Healing Stream Totem VII heals you for 6."),
        "Healing Stream Totem", "rank suffix VII stripped")
    H.assert_eq(TotemBar.parseSelfGain("Healing Stream Totem IV heals you for 6."),
        "Healing Stream Totem", "rank suffix IV stripped")
end)

H.run("parseSelfGain: full totem name in a gain line", function()
    H.assert_eq(TotemBar.parseSelfGain("You gain 10 Mana from Mana Spring Totem."),
        "Mana Spring Totem", "already a Totem name passes through")
end)

H.run("parseSelfGain: rejects non-totem sources", function()
    H.assert_eq(TotemBar.parseSelfGain("You gain 15 health from Renew."), nil, "Renew is not a totem")
    H.assert_eq(TotemBar.parseSelfGain("You gain 40 Mana from Blessing of Wisdom."), nil, "BoW is not a totem")
    H.assert_eq(TotemBar.parseSelfGain("Bighealer heals you for 500."), nil, "player heals are not totems")
end)

H.run("parseSelfGain: rejects garbage", function()
    H.assert_eq(TotemBar.parseSelfGain(nil), nil, "nil msg")
    H.assert_eq(TotemBar.parseSelfGain(""), nil, "empty msg")
    H.assert_eq(TotemBar.parseSelfGain("You gain experience."), nil, "unrelated gain line")
end)

H.run("parseSelfGain: 'Totem' substring in player names does not false-positive", function()
    H.assert_eq(TotemBar.parseSelfGain("Totemguy heals you for 500."), nil, "player named Totemguy rejected")
    H.assert_eq(TotemBar.parseSelfGain("You gain 5 Mana from Totemguy."), nil, "gain from player Totemguy rejected")
    H.assert_eq(TotemBar.parseSelfGain("Mana Spring Totem heals you for 6."), "Mana Spring Totem", "real totem name still passes (ends in ' Totem')")
end)

H.summary()
