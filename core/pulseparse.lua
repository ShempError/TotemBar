-- TotemBar - core/pulseparse.lua
-- PURE parser: periodic combat-log line -> totem name (or nil). Used by
-- ui.lua's CHAT_MSG_SPELL_PERIODIC_* handler to re-anchor pulse phase on
-- REAL observed ticks. Lua 5.0: string.find with captures only (no
-- string.match / no method-call syntax). Offline-tested via
-- tools/luatests/test_pulseparse.lua; exact accepted wordings get refined
-- from /tb pulsecal telemetry.

TotemBar = TotemBar or {}

-- Strips a trailing roman-numeral rank suffix (" IV", " VII", ...) - the
-- totem-as-caster shape names the ranked unit ("Healing Stream Totem VII").
local function stripRank(src)
    local _, _, base = string.find(src, "^(.-)%s+[IVXLC]+$")
    if base and base ~= "" then
        return base
    end
    return src
end

-- Maps a raw source name to a totem name: alias table first (buff names
-- like "Mana Spring"), then any source ending in " Totem".
local function resolveSource(src)
    local alias = TotemBar.PULSE_SOURCE_ALIASES and TotemBar.PULSE_SOURCE_ALIASES[src]
    if alias then
        return alias
    end
    -- Every totem's name ends in " Totem" (rank suffixes already stripped),
    -- so anchor at the end - a plain substring test would false-positive on
    -- player names like "Totemguy".
    if string.find(src, "%sTotem$") then
        return src
    end
    return nil
end

function TotemBar.parseSelfGain(msg)
    if not msg then
        return nil
    end
    local _, _, src = string.find(msg, "^You gain %d+ [Mm]ana from (.+)%.$")
    if not src then
        _, _, src = string.find(msg, "^You gain %d+ [Hh]ealth from (.+)%.$")
    end
    if not src then
        _, _, src = string.find(msg, "^(.-) heals you for %d+%.$")
    end
    if not src then
        return nil
    end
    return resolveSource(stripRank(src))
end
