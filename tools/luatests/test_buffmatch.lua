-- Offline test: core/cast.lua's pure buffTexturesMatch() buff-icon
-- matcher (the out-of-range red-tint feature's core logic). The live
-- hasBuffWithIcon() wrapper (UnitBuff scan) touches WoW API and is NOT
-- covered here (in-game verification only). Run from repo root:
--   lua50.exe tools/luatests/test_buffmatch.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/cast.lua")

H.run("buffTexturesMatch: matches an identical full path", function()
    local buffs = { "Interface\\Icons\\Spell_Nature_EarthBindTotem" }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\Spell_Nature_EarthBindTotem"), true, "identical path matches")
end)

H.run("buffTexturesMatch: case-insensitive", function()
    local buffs = { "Interface\\Icons\\SPELL_NATURE_WINDFURY" }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "interface\\icons\\spell_nature_windfury"), true, "case differences still match")
end)

H.run("buffTexturesMatch: finds a match among several buffs", function()
    local buffs = {
        "Interface\\Icons\\Spell_Holy_Renew",
        "Interface\\Icons\\INV_Spear_04",
        "Interface\\Icons\\Ability_Warrior_BattleShout",
    }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\INV_Spear_04"), true, "match found among several buffs")
end)

H.run("buffTexturesMatch: nil iconPath returns false", function()
    local buffs = { "Interface\\Icons\\Spell_Nature_EarthBindTotem" }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, nil), false, "nil iconPath -> false")
end)

H.run("buffTexturesMatch: no-match list returns false", function()
    local buffs = {
        "Interface\\Icons\\Spell_Holy_Renew",
        "Interface\\Icons\\Ability_Warrior_BattleShout",
    }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\Spell_Nature_Windfury"), false, "no match anywhere -> false")
end)

H.run("buffTexturesMatch: nil buff list returns false", function()
    H.assert_eq(TotemBar.buffTexturesMatch(nil, "Interface\\Icons\\Spell_Nature_Windfury"), false, "nil buff list -> false")
end)

H.run("buffTexturesMatch: empty buff list returns false", function()
    H.assert_eq(TotemBar.buffTexturesMatch({}, "Interface\\Icons\\Spell_Nature_Windfury"), false, "empty buff list -> false")
end)

H.summary()
