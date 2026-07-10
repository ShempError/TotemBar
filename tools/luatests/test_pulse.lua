-- Offline test: core/pulsedata.lua + core/pulse.lua (pure pulse math for the
-- Pulse UI, spec docs/superpowers/specs/2026-07-09-pulse-ui-design.md).
-- Run from repo root: lua50.exe tools/luatests/test_pulse.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/pulsedata.lua")
dofile("core/pulse.lua")

H.run("PULSE_DATA: expected entries and shapes", function()
    H.assert_eq(TotemBar.PULSE_DATA["Magma Totem"].interval, 2.0, "Magma 2s tick")
    H.assert_eq(TotemBar.PULSE_DATA["Magma Totem"].ptype, "tick", "Magma is tick type")
    H.assert_eq(TotemBar.PULSE_DATA["Magma Totem"].firstTick, "delayed", "Magma first tick is delayed")
    H.assert_eq(TotemBar.PULSE_DATA["Magma Totem"].source, "server", "Magma sourced from server dump")
    H.assert_eq(TotemBar.PULSE_DATA["Tremor Totem"].interval, 4.0, "Tremor 4s tick (server-corrected from 3.0 book value)")
    H.assert_eq(TotemBar.PULSE_DATA["Tremor Totem"].firstTick, "immediate", "Tremor first tick is immediate")
    H.assert_eq(TotemBar.PULSE_DATA["Tremor Totem"].source, "server", "Tremor sourced from server dump")
    H.assert_eq(TotemBar.PULSE_DATA["Poison Cleansing Totem"].interval, 5.0, "Poison Cleansing 5s")
    H.assert_eq(TotemBar.PULSE_DATA["Disease Cleansing Totem"].interval, 5.0, "Disease Cleansing 5s")
    H.assert_eq(TotemBar.PULSE_DATA["Earthbind Totem"].interval, 3.0, "Earthbind 3s")
    H.assert_eq(TotemBar.PULSE_DATA["Healing Stream Totem"].anchor, "selfgain", "Healing Stream anchors on self-gain")
    H.assert_eq(TotemBar.PULSE_DATA["Mana Spring Totem"].anchor, "selfgain", "Mana Spring anchors on self-gain")
    H.assert_eq(TotemBar.PULSE_DATA["Fire Nova Totem"].ptype, "oneshot", "Fire Nova is one-shot")
    H.assert_eq(TotemBar.PULSE_DATA["Fire Nova Totem"].delay, 4.0, "Fire Nova 4s arming delay")
    H.assert_eq(TotemBar.PULSE_DATA["Stoneclaw Totem"].interval, 2.0, "Stoneclaw 2s threat pulse")
    H.assert_eq(TotemBar.PULSE_DATA["Stoneclaw Totem"].ptype, "tick", "Stoneclaw is tick type")
    H.assert_eq(TotemBar.PULSE_DATA["Stoneclaw Totem"].firstTick, "immediate", "Stoneclaw first tick is immediate")
    H.assert_eq(TotemBar.PULSE_DATA["Magma Totem"].verified, false, "server values start unverified pending in-game confirmation")
    H.assert_eq(TotemBar.PULSE_DATA["Searing Totem"], nil, "Searing has NO pulse entry (irregular attacks)")
    H.assert_eq(TotemBar.PULSE_DATA["Windfury Totem"], nil, "aura totems have NO pulse entry")
end)

H.run("PULSE_SOURCE_ALIASES: buff-name to totem-name", function()
    H.assert_eq(TotemBar.PULSE_SOURCE_ALIASES["Mana Spring"], "Mana Spring Totem", "Mana Spring alias")
    H.assert_eq(TotemBar.PULSE_SOURCE_ALIASES["Healing Stream"], "Healing Stream Totem", "Healing Stream alias")
end)

H.run("pulseInfo: lookup wrapper", function()
    H.assert_eq(TotemBar.pulseInfo("Magma Totem"), TotemBar.PULSE_DATA["Magma Totem"], "returns the entry")
    H.assert_eq(TotemBar.pulseInfo("Nope Totem"), nil, "unknown -> nil")
    H.assert_eq(TotemBar.pulseInfo(nil), nil, "nil -> nil")
end)

H.run("pulseRatio: dead-reckoned from placedAt", function()
    H.assert_eq(TotemBar.pulseRatio(100, nil, 2.0, 100), 0, "at placement -> 0")
    H.assert_eq(TotemBar.pulseRatio(100, nil, 2.0, 101), 0.5, "half interval -> 0.5")
    H.assert_eq(TotemBar.pulseRatio(100, nil, 2.0, 102), 0, "exactly one interval wraps to 0")
    H.assert_eq(TotemBar.pulseRatio(100, nil, 2.0, 103.5), 0.75, "wraps across intervals (3.5s -> 0.75)")
end)

H.run("pulseRatio: anchored origin wins over placedAt", function()
    H.assert_eq(TotemBar.pulseRatio(100, 101.3, 2.0, 102.3), 0.5, "anchor at 101.3 -> half at 102.3")
    H.assert_eq(TotemBar.pulseRatio(nil, 101.3, 2.0, 102.3), 0.5, "anchor alone suffices")
end)

H.run("pulseRatio: defensive edges", function()
    H.assert_eq(TotemBar.pulseRatio(nil, nil, 2.0, 100), nil, "no origin -> nil")
    H.assert_eq(TotemBar.pulseRatio(100, nil, nil, 101), nil, "no interval -> nil")
    H.assert_eq(TotemBar.pulseRatio(100, nil, 0, 101), nil, "zero interval -> nil")
    H.assert_eq(TotemBar.pulseRatio(100, nil, 2.0, 99), 0, "clock skew (now < origin) clamps to 0")
end)

H.run("oneshotRatio: fill once, clamp both ends", function()
    H.assert_eq(TotemBar.oneshotRatio(100, 4.0, 100), 0, "at placement -> 0")
    H.assert_eq(TotemBar.oneshotRatio(100, 4.0, 102), 0.5, "halfway -> 0.5")
    H.assert_eq(TotemBar.oneshotRatio(100, 4.0, 104), 1, "at delay -> 1")
    H.assert_eq(TotemBar.oneshotRatio(100, 4.0, 110), 1, "past delay clamps to 1")
    H.assert_eq(TotemBar.oneshotRatio(100, 4.0, 99), 0, "clock skew clamps to 0")
    H.assert_eq(TotemBar.oneshotRatio(nil, 4.0, 100), nil, "no placedAt -> nil")
    H.assert_eq(TotemBar.oneshotRatio(100, nil, 100), nil, "no delay -> nil")
end)

H.run("pulseImminent: 0.85 threshold", function()
    H.assert_eq(TotemBar.pulseImminent(0.84), false, "below threshold")
    H.assert_eq(TotemBar.pulseImminent(0.85), true, "at threshold")
    H.assert_eq(TotemBar.pulseImminent(0.99), true, "above threshold")
    H.assert_eq(TotemBar.pulseImminent(nil), false, "nil -> false")
end)

H.run("ringFrameIndex: 0=empty .. frameCount-1=full (Rev 2: 62-frame arc)", function()
    H.assert_eq(TotemBar.ringFrameIndex(20, 20, 62), 61, "full -> 61")
    H.assert_eq(TotemBar.ringFrameIndex(10, 20, 62), 31, "half -> 31")
    H.assert_eq(TotemBar.ringFrameIndex(0, 20, 62), 0, "empty -> 0")
    H.assert_eq(TotemBar.ringFrameIndex(-3, 20, 62), 0, "negative clamps to 0")
    H.assert_eq(TotemBar.ringFrameIndex(25, 20, 62), 61, "overfull clamps to max")
    H.assert_eq(TotemBar.ringFrameIndex(nil, 20, 62), 0, "nil remaining -> 0")
    H.assert_eq(TotemBar.ringFrameIndex(10, nil, 62), 0, "nil duration -> 0")
end)

H.run("buildRingTexCoords: 8x8 grid UVs (Rev 2: 62 arc + wave cell 62 + frame-band cell 63)", function()
    local c = TotemBar.buildRingTexCoords(64, 8)
    H.assert_eq(table.getn(c), 64, "64 entries")
    H.assert_eq(c[1].l, 0, "frame 0 left")
    H.assert_eq(c[1].t, 0, "frame 0 top")
    H.assert_eq(c[1].r, 0.125, "frame 0 right")
    H.assert_eq(c[1].b, 0.125, "frame 0 bottom")
    H.assert_eq(c[9].l, 0, "frame 8 wraps to row 2, col 0")
    H.assert_eq(c[9].t, 0.125, "frame 8 row 2 top")
    H.assert_eq(c[63].l, 0.75, "cell 62 (wave ring) col 6")
    H.assert_eq(c[63].t, 0.875, "cell 62 (wave ring) row 7")
    H.assert_eq(c[64].l, 0.875, "cell 63 (decorative frame band) col 7")
    H.assert_eq(c[64].t, 0.875, "cell 63 (decorative frame band) row 7")
end)

H.run("waveFrac: tick-totem ripple phase, clamped to half the interval", function()
    H.assert_eq(TotemBar.waveFrac(0, 2, 0.8), 0, "at pulse -> 0")
    H.assert_eq(TotemBar.waveFrac(0.2, 2, 0.8), 0.5, "age 0.4 of dur 0.8 -> 0.5")
    H.assert_eq(TotemBar.waveFrac(0.5, 2, 0.8), nil, "age 1.0 > dur 0.8 -> nil")
    H.assert_eq(TotemBar.waveFrac(0.2, 1.0, 0.8), 0.4, "dur clamped to half the 1.0s interval (0.5), age 0.2 -> 0.4")
    H.assert_eq(TotemBar.waveFrac(nil, 2, 0.8), nil, "nil ratio -> nil")
    H.assert_eq(TotemBar.waveFrac(0.2, nil, 0.8), nil, "nil interval -> nil")
    H.assert_eq(TotemBar.waveFrac(0.2, 0, 0.8), nil, "zero interval -> nil")
    H.assert_eq(TotemBar.waveFrac(0.2, 2, nil), nil, "nil waveDur -> nil")
    H.assert_eq(TotemBar.waveFrac(0.2, 2, 0), nil, "zero waveDur -> nil")
end)

H.run("oneshotWaveFrac: Fire Nova ripple starting at detonation", function()
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 104, 0.8), 0, "at detonation -> 0")
    -- NOTE: uses (100, 4, 104.5, 1.0) rather than the brief's (100, 4, 104.4,
    -- 0.8) example - both express the same "halfway through the wave"
    -- semantic (age == waveDur/2), but 104.4/0.8 leaves a ~5.7e-15 float
    -- residual ((104.4-100)-4 != double(0.4) bit-for-bit, since 104.4 isn't
    -- exactly representable and subtracting integers doesn't cancel that
    -- error) that fails H.assert_eq's exact ==; 104.5/1.0 are exact binary
    -- fractions (multiples of 0.5) with no such residual. See rev2-report.md.
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 104.5, 1.0), 0.5, "halfway through the wave -> 0.5")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 105, 0.8), nil, "past the wave's lifetime -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 103, 0.8), nil, "before detonation -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(nil, 4, 104, 0.8), nil, "nil placedAt -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, nil, 104, 0.8), nil, "nil delay -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, nil, 0.8), nil, "nil now -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 104, nil), nil, "nil waveDur -> nil")
    H.assert_eq(TotemBar.oneshotWaveFrac(100, 4, 104, 0), nil, "zero waveDur -> nil")
end)

H.run("resolveDuration: mirrors resolveRemaining precedence", function()
    H.assert_eq(TotemBar.resolveDuration(true, 15, 45, 40, 20), 45, "GTI active -> GTI duration")
    H.assert_eq(TotemBar.resolveDuration(true, 0, 45, 40, 20), nil, "GTI active but expired -> nil (no fallback)")
    H.assert_eq(TotemBar.resolveDuration(false, nil, nil, 40, 20), 20, "GTI inactive -> own duration")
    H.assert_eq(TotemBar.resolveDuration(nil, nil, nil, 40, 20), 20, "GTI absent -> own duration")
    H.assert_eq(TotemBar.resolveDuration(false, nil, nil, -1, 20), nil, "own expired -> nil")
    H.assert_eq(TotemBar.resolveDuration(false, nil, nil, nil, nil), nil, "nothing -> nil")
end)

H.run("glowRamp: eased anticipation ramp over the last (1-rampStart) fraction", function()
    H.assert_eq(TotemBar.glowRamp(0.5, 0.78), nil, "below rampStart -> nil")
    H.assert_eq(TotemBar.glowRamp(0.78, 0.78), 0, "at rampStart -> 0")
    H.assert_eq(TotemBar.glowRamp(0.89, 0.78), 0.25, "t=0.5 -> squared 0.25")
    H.assert_eq(TotemBar.glowRamp(2, 0.78), 1, "past 1 clamps to 1")
    H.assert_eq(TotemBar.glowRamp(nil, 0.78), nil, "nil ratio -> nil")
    H.assert_eq(TotemBar.glowRamp(0.9, nil), nil, "nil rampStart -> nil")
    H.assert_eq(TotemBar.glowRamp(0.9, 1), nil, "rampStart >= 1 -> nil")
end)

H.run("timeColor: traffic-light color for a remaining-time fraction", function()
    -- Round to 2dp before comparing (H.assert_eq is an exact ==) - the
    -- blend math involves float multiplies that don't land bit-exact on
    -- the documented 2dp waypoints.
    local function rnd(x)
        return math.floor(x * 100 + 0.5) / 100
    end

    local r, g, b = TotemBar.timeColor(1)
    H.assert_eq(rnd(r), 0.25, "frac=1 (full) -> r")
    H.assert_eq(rnd(g), 0.80, "frac=1 (full) -> g")
    H.assert_eq(rnd(b), 0.25, "frac=1 (full) -> b")

    r, g, b = TotemBar.timeColor(0.5)
    H.assert_eq(rnd(r), 0.95, "frac=0.5 (green/yellow boundary) -> r")
    H.assert_eq(rnd(g), 0.85, "frac=0.5 (green/yellow boundary) -> g")
    H.assert_eq(rnd(b), 0.20, "frac=0.5 (green/yellow boundary) -> b")

    r, g, b = TotemBar.timeColor(0.25)
    H.assert_eq(rnd(r), 1.00, "frac=0.25 (yellow/orange boundary) -> r")
    H.assert_eq(rnd(g), 0.55, "frac=0.25 (yellow/orange boundary) -> g")
    H.assert_eq(rnd(b), 0.10, "frac=0.25 (yellow/orange boundary) -> b")

    r, g, b = TotemBar.timeColor(0)
    H.assert_eq(rnd(r), 0.90, "frac=0 (empty) -> r")
    H.assert_eq(rnd(g), 0.15, "frac=0 (empty) -> g")
    H.assert_eq(rnd(b), 0.10, "frac=0 (empty) -> b")

    r, g, b = TotemBar.timeColor(nil)
    H.assert_eq(r, 1, "frac=nil -> r")
    H.assert_eq(g, 1, "frac=nil -> g")
    H.assert_eq(b, 1, "frac=nil -> b")

    r, g, b = TotemBar.timeColor(1.5)
    H.assert_eq(rnd(r), 0.25, "frac=1.5 clamps like 1 -> r")
    H.assert_eq(rnd(g), 0.80, "frac=1.5 clamps like 1 -> g")
    H.assert_eq(rnd(b), 0.25, "frac=1.5 clamps like 1 -> b")

    r, g, b = TotemBar.timeColor(-0.2)
    H.assert_eq(rnd(r), 0.90, "frac=-0.2 clamps like 0 -> r")
    H.assert_eq(rnd(g), 0.15, "frac=-0.2 clamps like 0 -> g")
    H.assert_eq(rnd(b), 0.10, "frac=-0.2 clamps like 0 -> b")
end)

H.summary()
