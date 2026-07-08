-- Offline test: core/totemdata.lua's totemDuration() and core/cast.lua's
-- small pure timer-display helpers (remaining, resolveRemaining,
-- formatRemaining). Run from repo root:
--   lua50.exe tools/luatests/test_duration.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/cast.lua")

H.run("totemDuration: Searing Totem is rank-aware", function()
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 1), 30, "rank 1 -> 30s")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 2), 35, "rank 2 -> 35s")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 3), 40, "rank 3 -> 40s")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 4), 45, "rank 4 -> 45s")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 5), 50, "rank 5 -> 50s")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 6), 55, "rank 6 -> 55s")
end)

H.run("totemDuration: Searing Totem unknown/missing rank defaults to 55", function()
    H.assert_eq(TotemBar.totemDuration("Searing Totem", nil), 55, "no rank -> 55 (highest)")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 0), 55, "rank 0 -> 55 (invalid, fall back)")
    H.assert_eq(TotemBar.totemDuration("Searing Totem", 99), 55, "rank above max clamps to 55")
end)

H.run("totemDuration: flat durations for listed totems", function()
    H.assert_eq(TotemBar.totemDuration("Magma Totem"), 20, "Magma Totem")
    H.assert_eq(TotemBar.totemDuration("Fire Nova Totem"), 5, "Fire Nova Totem")
    H.assert_eq(TotemBar.totemDuration("Flametongue Totem"), 120, "Flametongue Totem")
    H.assert_eq(TotemBar.totemDuration("Frost Resistance Totem"), 120, "Frost Resistance Totem")
    H.assert_eq(TotemBar.totemDuration("Stoneclaw Totem"), 15, "Stoneclaw Totem")
    H.assert_eq(TotemBar.totemDuration("Earthbind Totem"), 45, "Earthbind Totem")
    H.assert_eq(TotemBar.totemDuration("Stoneskin Totem"), 120, "Stoneskin Totem")
    H.assert_eq(TotemBar.totemDuration("Strength of Earth Totem"), 120, "Strength of Earth Totem")
    H.assert_eq(TotemBar.totemDuration("Tremor Totem"), 120, "Tremor Totem")
    H.assert_eq(TotemBar.totemDuration("Mana Tide Totem"), 12, "Mana Tide Totem")
    H.assert_eq(TotemBar.totemDuration("Healing Stream Totem"), 60, "Healing Stream Totem")
    H.assert_eq(TotemBar.totemDuration("Mana Spring Totem"), 60, "Mana Spring Totem")
    H.assert_eq(TotemBar.totemDuration("Fire Resistance Totem"), 120, "Fire Resistance Totem")
    H.assert_eq(TotemBar.totemDuration("Disease Cleansing Totem"), 120, "Disease Cleansing Totem")
    H.assert_eq(TotemBar.totemDuration("Poison Cleansing Totem"), 120, "Poison Cleansing Totem")
    H.assert_eq(TotemBar.totemDuration("Grounding Totem"), 45, "Grounding Totem")
    H.assert_eq(TotemBar.totemDuration("Grace of Air Totem"), 120, "Grace of Air Totem")
    H.assert_eq(TotemBar.totemDuration("Nature Resistance Totem"), 120, "Nature Resistance Totem")
    H.assert_eq(TotemBar.totemDuration("Tranquil Air Totem"), 120, "Tranquil Air Totem")
    H.assert_eq(TotemBar.totemDuration("Windfury Totem"), 120, "Windfury Totem")
    H.assert_eq(TotemBar.totemDuration("Windwall Totem"), 120, "Windwall Totem")
end)

H.run("totemDuration: unknown totem name defaults to 120", function()
    H.assert_eq(TotemBar.totemDuration("Sentry Totem"), 120, "Sentry Totem not in table -> default 120")
    H.assert_eq(TotemBar.totemDuration("Totally Made Up Totem"), 120, "made-up name -> default 120")
    H.assert_eq(TotemBar.totemDuration(nil), 120, "nil name -> default 120")
end)

H.run("remaining: pure start+duration-now math", function()
    H.assert_eq(TotemBar.remaining(100, 20, 110), 10, "10s left")
    H.assert_eq(TotemBar.remaining(100, 20, 120), 0, "exactly expired")
    H.assert_eq(TotemBar.remaining(100, 20, 130), -10, "past expiry goes negative")
    H.assert_eq(TotemBar.remaining(nil, 20, 100), nil, "missing start -> nil")
    H.assert_eq(TotemBar.remaining(100, nil, 100), nil, "missing duration -> nil")
end)

H.run("resolveRemaining: GTI active wins over own tracking", function()
    H.assert_eq(TotemBar.resolveRemaining(true, 15, 40), 15, "GTI active -> use GTI remaining")
end)

H.run("resolveRemaining: GTI active but out of time reports nothing (no fallback)", function()
    H.assert_eq(TotemBar.resolveRemaining(true, 0, 40), nil, "GTI active with 0 remaining -> nil, no fallback")
    H.assert_eq(TotemBar.resolveRemaining(true, nil, 40), nil, "GTI active with no timing data -> nil, no fallback")
end)

H.run("resolveRemaining: falls back to own tracking when GTI inactive or absent", function()
    H.assert_eq(TotemBar.resolveRemaining(false, nil, 40), 40, "GTI reports inactive -> own tracking")
    H.assert_eq(TotemBar.resolveRemaining(nil, nil, 40), 40, "GTI absent (nil active) -> own tracking")
end)

H.run("resolveRemaining: nothing active anywhere -> nil", function()
    H.assert_eq(TotemBar.resolveRemaining(false, nil, nil), nil, "no GTI, no own record -> nil")
    H.assert_eq(TotemBar.resolveRemaining(false, nil, -5), nil, "own record already expired -> nil")
end)

H.run("formatRemaining: seconds below a minute", function()
    H.assert_eq(TotemBar.formatRemaining(1), "1", "1s")
    H.assert_eq(TotemBar.formatRemaining(45), "45", "45s")
    H.assert_eq(TotemBar.formatRemaining(59.4), "60", "rounds up under a minute")
end)

H.run("formatRemaining: minutes at/above 60s", function()
    H.assert_eq(TotemBar.formatRemaining(60), "1m", "exactly 60s -> 1m")
    H.assert_eq(TotemBar.formatRemaining(61), "2m", "61s rounds up to 2m")
    H.assert_eq(TotemBar.formatRemaining(120), "2m", "120s -> 2m")
end)

H.summary()
