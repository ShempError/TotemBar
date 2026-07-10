-- Offline test: Pulse UI SavedVariables defaults in core/config.lua.
-- Run from repo root: lua50.exe tools/luatests/test_pulseui_config.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
TotemBar.DEFAULT_GAP_SECONDS = 2
TotemBar.DEFAULT_RECALL_GUARD = 2
dofile("core/config.lua")

H.run("ensureDefaults: fills pulse-UI fields on a fresh DB", function()
    TotemBarDB = {}
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.showDurationRing, true, "ring on by default")
    H.assert_eq(TotemBarDB.ringStyle, "round", "round style by default")
    H.assert_eq(TotemBarDB.showPulseBars, true, "pulse bars on by default")
    H.assert_eq(TotemBarDB.showPulseWaves, true, "pulse waves on by default")
    H.assert_eq(TotemBarDB.pulseGlow, true, "glow on by default")
    H.assert_eq(TotemBarDB.showTimerText, true, "timer text stays on by default")
    H.assert_eq(TotemBarDB.barLayout, "1x6", "bar layout defaults to 1x6")
end)

H.run("ensureDefaults: respects explicit user choices", function()
    TotemBarDB = { showDurationRing = false, ringStyle = "square",
                   showPulseBars = false, showPulseWaves = false,
                   pulseGlow = false, showTimerText = false,
                   barLayout = "3x2" }
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.showDurationRing, false, "user ring OFF kept")
    H.assert_eq(TotemBarDB.ringStyle, "square", "user square style kept")
    H.assert_eq(TotemBarDB.showPulseBars, false, "user bars OFF kept")
    H.assert_eq(TotemBarDB.showPulseWaves, false, "user waves OFF kept")
    H.assert_eq(TotemBarDB.pulseGlow, false, "user glow OFF kept")
    H.assert_eq(TotemBarDB.showTimerText, false, "user text OFF kept")
    H.assert_eq(TotemBarDB.barLayout, "3x2", "user 3x2 layout kept")
end)

H.summary()
