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
