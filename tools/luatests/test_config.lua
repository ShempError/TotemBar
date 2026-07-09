-- Offline test: core/config.lua ensureDefaults fills the new SavedVariables
-- fields. Run from repo root: lua50.exe tools/luatests/test_config.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
TotemBar.DEFAULT_GAP_SECONDS = 2
TotemBar.DEFAULT_RECALL_GUARD = 2
dofile("core/config.lua")

H.run("ensureDefaults: fills new fields on a fresh DB", function()
    TotemBarDB = {}
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.scale, 1.0, "scale default 1.0")
    H.assert_eq(TotemBarDB.minimapAngle, 225, "minimapAngle default 225")
    H.assert_eq(TotemBarDB.hidden, false, "hidden default false")
    H.assert_eq(TotemBarDB.recallGuardSeconds, 2, "recallGuardSeconds default 2")
end)

H.run("ensureDefaults: preserves existing values", function()
    TotemBarDB = { scale = 1.5, minimapAngle = 40, hidden = true, recallGuardSeconds = 3 }
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.scale, 1.5, "scale preserved")
    H.assert_eq(TotemBarDB.minimapAngle, 40, "angle preserved")
    H.assert_eq(TotemBarDB.hidden, true, "hidden preserved")
    H.assert_eq(TotemBarDB.recallGuardSeconds, 3, "guard preserved")
end)

H.summary()
