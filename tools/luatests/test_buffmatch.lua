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

-- Icon names that are a strict PREFIX of another totem's icon must not match.
-- 1.12 has exactly such a pair: Windwall Totem = Spell_Nature_EarthBind,
-- Strength of Earth Totem = Spell_Nature_EarthBindTotem. A substring search
-- reported "Windwall is buffing me" whenever the player carried the Strength
-- of Earth buff, so the Air slot never turned red out of range.
H.run("buffTexturesMatch: a longer buff icon name does NOT match a shorter totem icon", function()
    local buffs = {
        "Interface\\Icons\\Ability_Warrior_BattleShout",
        "Interface\\Icons\\Spell_Nature_EarthBindTotem",   -- Strength of Earth
    }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\Spell_Nature_EarthBind"), false,
        "Strength of Earth's buff must not match Windwall's icon")
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\Spell_Nature_EarthBindTotem"), true,
        "the real owner still matches")
end)

H.run("buffTexturesMatch: a shorter buff icon name does NOT match a longer totem icon", function()
    local buffs = { "Interface\\Icons\\Spell_Nature_EarthBind" }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Interface\\Icons\\Spell_Nature_EarthBindTotem"), false,
        "prefix collision blocked in both directions")
end)

H.run("buffTexturesMatch: differing path prefixes still match on the icon name", function()
    local buffs = { "Interface\\Icons\\Spell_Nature_Windfury" }
    H.assert_eq(TotemBar.buffTexturesMatch(buffs, "Spell_Nature_Windfury"), true,
        "bare icon name matches a full path (path tolerance kept)")
    H.assert_eq(TotemBar.buffTexturesMatch({ "Spell_Nature_Windfury" }, "Interface\\Icons\\Spell_Nature_Windfury"), true,
        "and the other way round")
end)

H.summary()
