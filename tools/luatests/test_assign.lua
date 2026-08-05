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

H.run("ReceiveAssignment: stores pending + calls ShowAssignPanel", function()
    TotemBar.pending = nil
    local shown = false
    TotemBar.ShowAssignPanel = function() shown = true end
    local ok = TotemBar.ReceiveAssignment({ Fire = "Searing Totem" }, "TEST")
    H.assert_eq(ok, true, "valid assignment accepted")
    H.assert_eq(TotemBar.pending.set.Fire, "Searing Totem", "pending set stored")
    H.assert_eq(TotemBar.pending.label, "TEST", "pending label stored")
    H.assert_eq(shown, true, "ShowAssignPanel called")
    TotemBar.ShowAssignPanel = nil
end)

H.run("ReceiveAssignment: rejects invalid, no pending set", function()
    TotemBar.pending = nil
    local ok = TotemBar.ReceiveAssignment({}, "x")
    H.assert_eq(ok, false, "empty set rejected")
    H.assert_eq(TotemBar.pending, nil, "no pending stored on reject")
end)

H.run("ClearAssignment: drops pending + calls HideAssignPanel", function()
    TotemBar.pending = { set = { Fire = "Searing Totem" }, label = "x" }
    local hidden = false
    TotemBar.HideAssignPanel = function() hidden = true end
    TotemBar.ClearAssignment()
    H.assert_eq(TotemBar.pending, nil, "pending cleared")
    H.assert_eq(hidden, true, "HideAssignPanel called")
    TotemBar.HideAssignPanel = nil
end)

H.run("ApplyPending: writes known totems to chosen, skips unknown, clears", function()
    TotemBarDB = { chosen = {} }
    TotemBar.pending = {
        set = { Fire = "Searing Totem", Air = "Windfury Totem" }, label = "TEST",
    }
    TotemBar.isTotemKnown = function(name) return name == "Searing Totem" end
    local refreshed = false
    TotemBar.RefreshAll = function() refreshed = true end
    local appliedArg = nil
    TotemBar.onAssignmentApplied = function(s) appliedArg = s end

    TotemBar.ApplyPending()

    H.assert_eq(TotemBarDB.chosen.Fire, "Searing Totem", "known totem applied")
    H.assert_eq(TotemBarDB.chosen.Air, nil, "unknown totem skipped")
    H.assert_eq(refreshed, true, "RefreshAll called")
    H.assert_eq(appliedArg.Fire, "Searing Totem", "onAssignmentApplied got applied set")
    H.assert_eq(TotemBar.pending, nil, "pending cleared after apply")

    TotemBar.isTotemKnown = nil
    TotemBar.RefreshAll = nil
    TotemBar.onAssignmentApplied = nil
    TotemBarDB = nil
end)

H.run("ApplyPending: no-op when nothing pending", function()
    TotemBar.pending = nil
    TotemBar.ApplyPending()   -- must not error
    H.assert_eq(TotemBar.pending, nil, "still nil")
end)

H.summary()
