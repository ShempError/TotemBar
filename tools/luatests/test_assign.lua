-- Offline test: core/assign.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_assign.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/assign.lua")

H.run("isElement: valid and invalid keys", function()
    H.assert_eq(TotemBar.isElement("Fire"), true, "Fire is an element")
    H.assert_eq(TotemBar.isElement("Air"), true, "Air is an element")
    H.assert_eq(TotemBar.isElement("Spirit"), false, "Spirit is not an element")
    H.assert_eq(TotemBar.isElement(nil), false, "nil is not an element")
end)

H.run("validateAssignment: accepts a valid set", function()
    local ok = TotemBar.validateAssignment({ Fire = "Searing Totem", Air = "Windfury Totem" })
    H.assert_eq(ok, true, "valid set accepted")
end)

H.run("validateAssignment: rejects non-table", function()
    local ok, reason = TotemBar.validateAssignment("nope")
    H.assert_eq(ok, false, "string rejected")
    H.assert_eq(type(reason), "string", "reason is a string")
end)

H.run("validateAssignment: rejects empty set", function()
    local ok = TotemBar.validateAssignment({})
    H.assert_eq(ok, false, "empty set rejected")
end)

H.run("validateAssignment: rejects unknown element key", function()
    local ok = TotemBar.validateAssignment({ Spirit = "Ghost Totem" })
    H.assert_eq(ok, false, "unknown element key rejected")
end)

H.run("validateAssignment: rejects non-string / empty totem name", function()
    H.assert_eq(TotemBar.validateAssignment({ Fire = 123 }), false, "numeric name rejected")
    H.assert_eq(TotemBar.validateAssignment({ Fire = "" }), false, "empty name rejected")
end)

H.run("copySet: keeps only element keys, returns a copy", function()
    local src = { Fire = "Searing Totem", Junk = "x" }
    local out = TotemBar.copySet(src)
    H.assert_eq(out.Fire, "Searing Totem", "Fire copied")
    H.assert_eq(out.Junk, nil, "non-element key dropped")
    out.Fire = "changed"
    H.assert_eq(src.Fire, "Searing Totem", "source not mutated (copy)")
end)

H.run("GetChosenSet: returns a fresh copy of TotemBarDB.chosen", function()
    TotemBarDB = { chosen = { Fire = "Magma Totem", Water = "Mana Spring Totem" } }
    local snap = TotemBar.GetChosenSet()
    H.assert_eq(snap.Fire, "Magma Totem", "Fire chosen read")
    H.assert_eq(snap.Water, "Mana Spring Totem", "Water chosen read")
    snap.Fire = "mutated"
    H.assert_eq(TotemBarDB.chosen.Fire, "Magma Totem", "underlying DB not mutated")
    TotemBarDB = nil
end)

H.run("filterKnown: splits by predicate", function()
    local set = { Fire = "Searing Totem", Air = "Windfury Totem" }
    local isKnown = function(name) return name == "Searing Totem" end
    local applied, skipped = TotemBar.filterKnown(set, isKnown)
    H.assert_eq(applied.Fire, "Searing Totem", "known kept in applied")
    H.assert_eq(applied.Air, nil, "unknown not in applied")
    H.assert_eq(skipped.Air, "Windfury Totem", "unknown in skipped")
    H.assert_eq(skipped.Fire, nil, "known not in skipped")
end)

H.summary()
