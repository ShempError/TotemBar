-- TotemBar - core/totemdata.lua
-- PURE data module (no WoW API calls) - offline-testable.
--
-- Static element -> totem name map for vanilla shaman totems.
--
-- NOTE: TurtleWoW may rename or add totems relative to vanilla 1.12.
-- Use "/tb scan" in-game to print the player's actual known totem spell
-- strings and cross-check them against this map before trusting it.

TotemBar = TotemBar or {}

TotemBar.TOTEM_ELEMENTS = { "Fire", "Earth", "Water", "Air" }

TotemBar.TOTEMS_BY_ELEMENT = {
    Fire = {
        "Searing Totem",
        "Fire Nova Totem",
        "Magma Totem",
        "Flametongue Totem",
        "Frost Resistance Totem",
    },
    Earth = {
        "Earthbind Totem",
        "Stoneclaw Totem",
        "Stoneskin Totem",
        "Strength of Earth Totem",
        "Tremor Totem",
    },
    Water = {
        "Fire Resistance Totem",
        "Healing Stream Totem",
        "Mana Spring Totem",
        "Poison Cleansing Totem",
        "Disease Cleansing Totem",
        "Mana Tide Totem",
    },
    Air = {
        "Grace of Air Totem",
        "Grounding Totem",
        "Nature Resistance Totem",
        "Sentry Totem",
        "Windfury Totem",
        "Windwall Totem",
        "Tranquil Air Totem",
    },
}

-- Build the reverse lookup (totem name -> element) once at load time.
local elementByName = {}
for elemIdx = 1, table.getn(TotemBar.TOTEM_ELEMENTS) do
    local element = TotemBar.TOTEM_ELEMENTS[elemIdx]
    local list = TotemBar.TOTEMS_BY_ELEMENT[element]
    for totemIdx = 1, table.getn(list) do
        elementByName[list[totemIdx]] = element
    end
end

-- Returns the element ("Fire"/"Earth"/"Water"/"Air") a totem spell name
-- belongs to, or nil if the name isn't in the static map.
function TotemBar.elementOf(name)
    if not name then
        return nil
    end
    return elementByName[name]
end

-- Totem lifetime durations (seconds), tuned to TurtleWoW server timers
-- (mirrors pfUI libtotem's verified values). Keyed by totem spell name;
-- any totem not listed here falls back to DEFAULT_TOTEM_DURATION.
-- Searing Totem is rank-aware (see SEARING_TOTEM_DURATIONS below) and
-- is intentionally NOT listed in this flat table.
TotemBar.DEFAULT_TOTEM_DURATION = 120

TotemBar.SEARING_TOTEM_DURATIONS = {
    [1] = 30,
    [2] = 35,
    [3] = 40,
    [4] = 45,
    [5] = 50,
    [6] = 55,
}
TotemBar.SEARING_TOTEM_MAX_RANK = 6
TotemBar.SEARING_TOTEM_DEFAULT_DURATION = 55

TotemBar.TOTEM_DURATIONS = {
    -- Fire
    ["Magma Totem"] = 20,
    ["Fire Nova Totem"] = 5,
    ["Flametongue Totem"] = 120,
    ["Frost Resistance Totem"] = 120,
    -- Earth
    ["Stoneclaw Totem"] = 15,
    ["Earthbind Totem"] = 45,
    ["Stoneskin Totem"] = 120,
    ["Strength of Earth Totem"] = 120,
    ["Tremor Totem"] = 120,
    -- Water
    ["Mana Tide Totem"] = 12,
    ["Healing Stream Totem"] = 60,
    ["Mana Spring Totem"] = 60,
    ["Fire Resistance Totem"] = 120,
    ["Disease Cleansing Totem"] = 120,
    ["Poison Cleansing Totem"] = 120,
    -- Air
    ["Grounding Totem"] = 45,
    ["Grace of Air Totem"] = 120,
    ["Nature Resistance Totem"] = 120,
    ["Tranquil Air Totem"] = 120,
    ["Windfury Totem"] = 120,
    ["Windwall Totem"] = 120,
}

-- Pure: seconds a totem will remain active for, given its exact spell
-- name and (for Searing Totem only) the player's highest known rank
-- number. Unknown/unmapped totems fall back to DEFAULT_TOTEM_DURATION
-- (a safe overestimate, rather than a timer that disappears too early).
function TotemBar.totemDuration(name, highestRank)
    if not name then
        return TotemBar.DEFAULT_TOTEM_DURATION
    end
    if name == "Searing Totem" then
        if not highestRank or highestRank < 1 then
            return TotemBar.SEARING_TOTEM_DEFAULT_DURATION
        end
        local rank = highestRank
        if rank > TotemBar.SEARING_TOTEM_MAX_RANK then
            rank = TotemBar.SEARING_TOTEM_MAX_RANK
        end
        return TotemBar.SEARING_TOTEM_DURATIONS[rank] or TotemBar.SEARING_TOTEM_DEFAULT_DURATION
    end
    return TotemBar.TOTEM_DURATIONS[name] or TotemBar.DEFAULT_TOTEM_DURATION
end
