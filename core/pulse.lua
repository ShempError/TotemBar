-- TotemBar - core/pulse.lua
-- PURE pulse/ring math for the Pulse UI (no WoW API; offline-tested via
-- tools/luatests/test_pulse.lua). ui.lua calls these from its throttled
-- timer tick - keep everything allocation-free except buildRingTexCoords
-- (called once at load).

TotemBar = TotemBar or {}

-- 0..1 phase toward the next pulse. Phase origin is anchorAt (the last
-- OBSERVED pulse, stamped by ui.lua's combat-message handler) when set,
-- else placedAt (dead reckoning). Lua 5.0: math.mod, not the % operator.
function TotemBar.pulseRatio(placedAt, anchorAt, interval, now)
    if not interval or interval <= 0 then
        return nil
    end
    local origin = anchorAt or placedAt
    if not origin or not now then
        return nil
    end
    local elapsed = now - origin
    if elapsed < 0 then
        return 0
    end
    return math.mod(elapsed, interval) / interval
end

-- 0..1 single fill from placement to detonation (Fire Nova). Clamped at
-- both ends; callers treat >=1 as "detonated" and hide the bar.
function TotemBar.oneshotRatio(placedAt, delay, now)
    if not placedAt or not delay or delay <= 0 or not now then
        return nil
    end
    local r = (now - placedAt) / delay
    if r < 0 then
        return 0
    end
    if r > 1 then
        return 1
    end
    return r
end

-- Blueprint state D ("pulse imminent"): glow from 85% fill on.
TotemBar.PULSE_IMMINENT_THRESHOLD = 0.85
function TotemBar.pulseImminent(ratio)
    if ratio and ratio >= TotemBar.PULSE_IMMINENT_THRESHOLD then
        return true
    end
    return false
end

-- Flipbook frame index for the duration ring: 0 = empty ... frameCount-1 =
-- full, rounded to nearest so the ring reads full right after placement.
-- Generic over frameCount; callers pass the arc's actual frame count (Rev 2:
-- 62, cells 0..61 of the ring_round.tga flipbook).
function TotemBar.ringFrameIndex(remaining, duration, frameCount)
    if not remaining or not duration or duration <= 0 or not frameCount then
        return 0
    end
    local ratio = remaining / duration
    if ratio < 0 then
        ratio = 0
    end
    if ratio > 1 then
        ratio = 1
    end
    return math.floor(ratio * (frameCount - 1) + 0.5)
end

-- Precomputed SetTexCoord rectangles for a square cols x cols grid texture,
-- row-major, 1-based array indexed by frame+1. Built ONCE at load; the
-- per-tick path just indexes it (zero allocation, zero math).
function TotemBar.buildRingTexCoords(frames, cols)
    local coords = {}
    local cell = 1 / cols
    for i = 0, frames - 1 do
        local col = math.mod(i, cols)
        local row = math.floor(i / cols)
        coords[i + 1] = {
            l = col * cell,
            r = (col + 1) * cell,
            t = row * cell,
            b = (row + 1) * cell,
        }
    end
    return coords
end

-- Duration counterpart of core/cast.lua's resolveRemaining, SAME precedence:
-- GTI (pfUI libtotem) is authoritative while it reports the slot active;
-- otherwise fall back to own tracking. Returns the TOTAL duration whose
-- remaining time resolveRemaining would have returned, or nil.
function TotemBar.resolveDuration(gtiActive, gtiRemaining, gtiDuration, ownRemaining, ownDuration)
    if gtiActive then
        if gtiRemaining and gtiRemaining > 0 then
            return gtiDuration
        end
        return nil
    end
    if ownRemaining and ownRemaining > 0 then
        return ownDuration
    end
    return nil
end

-- Ripple wave phase: seconds since the last pulse mapped to 0..1 over the
-- wave's lifetime, or nil when no wave is showing. For tick totems the wave
-- starts AT each pulse (phase wraps via pulseRatio); waveDur is clamped to
-- half the interval so the wave always dies before the next one spawns.
function TotemBar.waveFrac(ratio, interval, waveDur)
    if not ratio or not interval or interval <= 0 or not waveDur or waveDur <= 0 then
        return nil
    end
    local dur = waveDur
    if dur > interval * 0.5 then
        dur = interval * 0.5
    end
    local age = ratio * interval
    if age > dur then
        return nil
    end
    return age / dur
end

-- One-shot (Fire Nova): wave for waveDur seconds AFTER detonation.
function TotemBar.oneshotWaveFrac(placedAt, delay, now, waveDur)
    if not placedAt or not delay or not now or not waveDur or waveDur <= 0 then
        return nil
    end
    local age = (now - placedAt) - delay
    if age < 0 or age > waveDur then
        return nil
    end
    return age / waveDur
end

-- Anticipation glow: eased 0..1 ramp over the last (1 - rampStart) fraction
-- of the pulse phase; nil below rampStart (no glow) or on bad inputs.
function TotemBar.glowRamp(ratio, rampStart)
    if not ratio or not rampStart or rampStart >= 1 or ratio < rampStart then
        return nil
    end
    local t = (ratio - rampStart) / (1 - rampStart)
    if t > 1 then
        t = 1
    end
    return t * t
end

-- Traffic-light color for a remaining-time fraction (1 = full, 0 = empty):
-- green above 0.5, blending green->yellow->orange->red as time runs out.
-- Returns r, g, b as three numbers (no table - called per tick).
function TotemBar.timeColor(frac)
    if not frac then
        return 1, 1, 1
    end
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    if frac >= 0.5 then
        -- green (0.25,0.8,0.25) -> yellow (0.95,0.85,0.2) over 1.0..0.5
        local t = (1 - frac) * 2
        return 0.25 + 0.70 * t, 0.80 + 0.05 * t, 0.25 - 0.05 * t
    elseif frac >= 0.25 then
        -- yellow -> orange (1.0,0.55,0.1) over 0.5..0.25
        local t = (0.5 - frac) * 4
        return 0.95 + 0.05 * t, 0.85 - 0.30 * t, 0.20 - 0.10 * t
    end
    -- orange -> red (0.90,0.15,0.10) over 0.25..0
    local t = (0.25 - frac) * 4
    return 1.00 - 0.10 * t, 0.55 - 0.40 * t, 0.10
end
