-- TotemBar - core/pulsedata.lua
-- Pulse metadata per totem name (PURE data, no WoW API). Drives the pulse
-- progress bar in ui.lua. Totems absent from PULSE_DATA get NO pulse bar
-- (better no info than invented info) - notably Searing Totem (irregular
-- attack cadence, not a fixed pulse), Grounding (event-consumed) and every
-- aura totem (continuous aura, no verified pulse mechanic).
--
-- Values are server-dump-derived (TWoW server dump, snapshot 2024-07,
-- patch_1172 branch; tw_world.sql + SpellAuras.cpp:8647-8714), not book
-- values - source="server" records that provenance. verified=false stays
-- reserved for IN-GAME confirmation: /tb pulsecal (core/pulsecal.lua)
-- captures the real timings; once measured in-game, update the value AND
-- flip verified=true. Spec:
-- docs/superpowers/specs/2026-07-09-pulse-ui-design.md section 3.
--
-- firstTick: "immediate" means the aura's periodic tick fires at t=0 (the
-- totem is on SpellAuras.cpp's CalculatePeriodic exception list);
-- "delayed" means the first tick lands only after one full amplitude has
-- elapsed. NOTE: the pulseRatio math is identical either way - the bar
-- reaches 1.0 at every tick instant, including the t=0 wrap for
-- "immediate" totems - so firstTick is currently documentative only (no
-- consumer branches on it yet). Kept for future use, e.g. a distinct
-- wave/flash at t=0 for "immediate" totems.

TotemBar = TotemBar or {}

-- ptype "tick"    -> repeating pulse every `interval` seconds
-- ptype "oneshot" -> single detonation `delay` seconds after placement
-- anchor "selfgain" -> phase re-anchors on observed periodic self-gain
--                      combat messages (see core/pulseparse.lua + ui.lua)
TotemBar.PULSE_DATA = {
    ["Magma Totem"]             = { ptype = "tick", interval = 2.0, firstTick = "delayed", source = "server", verified = false },
    -- 4.0s confirmed by server dump - corrects the earlier 3.0s book value.
    ["Tremor Totem"]            = { ptype = "tick", interval = 4.0, firstTick = "immediate", source = "server", verified = false },
    ["Earthbind Totem"]         = { ptype = "tick", interval = 3.0, firstTick = "immediate", source = "server", verified = false },
    ["Poison Cleansing Totem"]  = { ptype = "tick", interval = 5.0, firstTick = "immediate", source = "server", verified = false },
    ["Disease Cleansing Totem"] = { ptype = "tick", interval = 5.0, firstTick = "immediate", source = "server", verified = false },
    ["Healing Stream Totem"]    = { ptype = "tick", interval = 2.0, anchor = "selfgain", firstTick = "delayed", source = "server", verified = false },
    ["Mana Spring Totem"]       = { ptype = "tick", interval = 2.0, anchor = "selfgain", firstTick = "delayed", source = "server", verified = false },
    -- server models it as a periodic 4s trigger like Magma, but with the 5s
    -- totem duration exactly one nova lands at t=4s, so the oneshot model
    -- is behaviorally equivalent.
    ["Fire Nova Totem"]         = { ptype = "oneshot", delay = 4.0, firstTick = "delayed", source = "server", verified = false },
    -- threat pulse every 2s.
    ["Stoneclaw Totem"]         = { ptype = "tick", interval = 2.0, firstTick = "immediate", source = "server", verified = false },
}

-- Periodic gain lines name the BUFF ("You gain 10 Mana from Mana Spring."),
-- not the totem spell - map those source names back to the totem. Exact
-- wording gets pinned by pulsecal telemetry; extend as measured.
TotemBar.PULSE_SOURCE_ALIASES = {
    ["Mana Spring"]    = "Mana Spring Totem",
    ["Healing Stream"] = "Healing Stream Totem",
}

function TotemBar.pulseInfo(totemName)
    if not totemName then
        return nil
    end
    return TotemBar.PULSE_DATA[totemName]
end
