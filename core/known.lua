-- TotemBar - core/known.lua
-- knownTotems() is PURE (no WoW API) and offline-testable.
-- scanSpellbook() is a thin WoW-API wrapper kept minimal and separate so
-- the pure filtering logic never has to touch the real API to be tested.

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

-- Thin WoW-API wrapper: scans the player's spellbook and returns a flat
-- array of every spell name found (no filtering at all). Kept minimal
-- and separate from knownTotems() above so the pure logic stays
-- offline-testable without a live client.
function TotemBar.scanSpellbook()
    local names = {}
    local n = 0
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then
            break
        end
        n = n + 1
        names[n] = name
        i = i + 1
    end
    return names
end

-- Thin WoW-API wrapper: scans the player's spellbook for every entry
-- named `spellName` (multiple ranks of the same spell share a name)
-- and returns the highest rank number found, or nil if the spell isn't
-- known at all, or no matching entry carried a parseable rank number
-- (e.g. GetSpellName's rank string didn't contain a digit).
function TotemBar.highestKnownRank(spellName)
    if not spellName then
        return nil
    end
    local highest = nil
    local i = 1
    while true do
        local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then
            break
        end
        if name == spellName then
            local _, _, numStr = string.find(rank or "", "(%d+)")
            local num = numStr and tonumber(numStr)
            if num and (not highest or num > highest) then
                highest = num
            end
        end
        i = i + 1
    end
    return highest
end
