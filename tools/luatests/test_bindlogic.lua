-- Offline test: core/bindlogic.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_bindlogic.lua
dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")   -- TOTEM_ELEMENTS
dofile("core/bindlogic.lua")

H.run("bindingSuffix: uppercase + non-alnum to underscore", function()
    H.assert_eq(TotemBar.bindingSuffix("Searing Totem"), "SEARING_TOTEM", "spaces")
    H.assert_eq(TotemBar.bindingSuffix("Grace of Air Totem"), "GRACE_OF_AIR_TOTEM", "multi word")
    H.assert_eq(TotemBar.bindingSuffix("Fire Nova Totem"), "FIRE_NOVA_TOTEM", "three words")
    H.assert_eq(TotemBar.bindingSuffix(nil), "", "nil -> empty")
end)

H.run("modifierPrefix: order ALT-CTRL-SHIFT", function()
    H.assert_eq(TotemBar.modifierPrefix(nil, nil, nil), "", "none")
    H.assert_eq(TotemBar.modifierPrefix(nil, nil, 1), "SHIFT-", "shift")
    H.assert_eq(TotemBar.modifierPrefix(1, nil, nil), "ALT-", "alt")
    H.assert_eq(TotemBar.modifierPrefix(1, 1, 1), "ALT-CTRL-SHIFT-", "all three, in order")
    H.assert_eq(TotemBar.modifierPrefix(nil, 1, 1), "CTRL-SHIFT-", "ctrl+shift")
end)

H.run("actionForButton: buttons -> CLICK, flyout totem -> named binding", function()
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonFire", nil), "CLICK TotemBarButtonFire:LeftButton", "element")
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonRecall", nil), "CLICK TotemBarButtonRecall:LeftButton", "recall")
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonDropSet", nil), "CLICK TotemBarButtonDropSet:LeftButton", "dropset")
    H.assert_eq(TotemBar.actionForButton("TotemBarFlyoutIcon1", "Searing Totem"), "TOTEMBAR_TOTEM_SEARING_TOTEM", "flyout totem")
    H.assert_eq(TotemBar.actionForButton("SomethingElse", nil), nil, "unknown -> nil")
    H.assert_eq(TotemBar.actionForButton(nil, nil), nil, "nil -> nil")
end)

H.summary()
