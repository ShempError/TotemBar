-- TotemBar - core/known.lua
-- knownTotems() is PURE (no WoW API) and offline-testable.
-- The WoW-API spellbook scan it consumes (scanSpellbook) now lives in
-- core/spellindex.lua, alongside the other spellbook-index accessors
-- (findSpellIndex/findHighestRankSlot/highestKnownRank) -- kept minimal
-- and separate so the pure filtering logic below never has to touch the
-- real API to be tested.

TotemBar = TotemBar or {}

-- Pure: given a flat list of spell names (strings) known to the player
-- and an element name ("Fire"/"Earth"/"Water"/"Air"), returns an array
-- of the subset of those names that are totems belonging to that
-- element, in the static map's order.
--
-- - Names not present in the static map (non-totem spells) are ignored.
-- - Totems in the static map that aren't in spellNames (not known) are
--   omitted from the result.
-- - An unknown/unmapped element returns an empty array.
function TotemBar.knownTotems(spellNames, element)
    local result = {}
    local candidates = TotemBar.TOTEMS_BY_ELEMENT[element]
    if not candidates then
        return result
    end

    local known = {}
    if spellNames then
        for i = 1, table.getn(spellNames) do
            known[spellNames[i]] = true
        end
    end

    local n = 0
    for i = 1, table.getn(candidates) do
        local name = candidates[i]
        if known[name] then
            n = n + 1
            result[n] = name
        end
    end

    return result
end

-- TotemBar.scanSpellbook() and TotemBar.highestKnownRank() used to be
-- defined here as thin WoW-API wrappers, each doing its own fresh linear
-- GetSpellName() scan. They're now cache-backed views provided by
-- core/spellindex.lua (loaded earlier in the TOC) instead, so a totem
-- drop no longer re-walks the spellbook once per caller. Same names,
-- same signatures, same return values -- callers here are unchanged.
