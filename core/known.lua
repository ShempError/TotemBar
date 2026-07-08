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

-- Upper bound on how many tooltip-line slots parseRange() will look at.
-- Real spell tooltips run to well under this; scanning a fixed cap (and
-- guarding every slot against nil) sidesteps relying on table.getn/# on
-- a table that may have nil holes (unset TextLeftN FontStrings), which
-- is unreliable in Lua 5.0.
local RANGE_SCAN_MAX_LINES = 32

-- Pure: given a table of tooltip text lines (strings; some entries may
-- be nil or empty), scans them in order and returns the first totem
-- aura radius mentioned, as a number, or nil if none of the lines
-- mention one. Locale-tolerant: looks for a digit run immediately
-- followed (optionally through some spaces) by a yards/meters unit
-- word - English "yard(s)" or German "Meter(n)" - and returns that
-- number. Only string.find with captures is used (Lua 5.0 has no
-- string.match/gmatch).
function TotemBar.parseRange(lines)
    if not lines then
        return nil
    end
    for i = 1, RANGE_SCAN_MAX_LINES do
        local line = lines[i]
        if line and line ~= "" then
            local _, _, numStr = string.find(line, "(%d+)%s*[Yy]ard")
            if not numStr then
                _, _, numStr = string.find(line, "(%d+)%s*[Mm]eter")
            end
            if numStr then
                return tonumber(numStr)
            end
        end
    end
    return nil
end

-- Fallback aura radius (yards) used when a totem's tooltip can't be
-- resolved (not in the spellbook, or its tooltip text doesn't match
-- parseRange's patterns - locale/phrasing dependent, unverified
-- in-game as of writing).
TotemBar.DEFAULT_TOTEM_RANGE = 20

-- Per-session cache: spellName -> resolved range (yards). The tooltip
-- scan below is only worth doing once per totem name per session (the
-- radius doesn't change while playing, short of a talent/gear swap the
-- player makes mid-session, which is an accepted staleness tradeoff).
local rangeCache = {}

-- Lazily-created hidden scanning tooltip, shared by every totemRange()
-- call (one frame for the whole addon, not one per totem).
local scanTip = nil

-- Thin WoW-API wrapper: resolves the aura radius (in yards) of totem
-- spell `spellName` by reading its LIVE spellbook tooltip (so it
-- reflects talents/items that modify totem radii, unlike a hardcoded
-- table). Resolves the spellbook index, scans the tooltip's text lines
-- with a hidden GameTooltip, and hands them to the pure parseRange()
-- above. Falls back to TotemBar.DEFAULT_TOTEM_RANGE when the spell
-- isn't known or no line parses. Caches by spell name per session (see
-- rangeCache above) so repeated calls (e.g. every UpdateTimerDisplays
-- tick in ui.lua) don't rescan the tooltip.
function TotemBar.totemRange(spellName)
    if not spellName then
        return TotemBar.DEFAULT_TOTEM_RANGE
    end

    local cached = rangeCache[spellName]
    if cached then
        return cached
    end

    local idx = nil
    local i = 1
    while true do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then
            break
        end
        if name == spellName then
            idx = i
            break
        end
        i = i + 1
    end

    local range = TotemBar.DEFAULT_TOTEM_RANGE
    if idx then
        if not scanTip then
            scanTip = CreateFrame("GameTooltip", "TotemBarScanTip", nil, "GameTooltipTemplate")
        end
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetSpell(idx, BOOKTYPE_SPELL)

        -- GameTooltip:NumLines() exists in the 1.12 API (confirmed via
        -- KG lookup against a live TWoW addon reference) and reports
        -- exactly how many lines this SetSpell populated; ~8 is a
        -- defensive fallback in case that method is ever missing, and
        -- RANGE_SCAN_MAX_LINES is a hard safety cap either way.
        local numLines = (scanTip.NumLines and scanTip:NumLines()) or 8
        if numLines > RANGE_SCAN_MAX_LINES then
            numLines = RANGE_SCAN_MAX_LINES
        end

        local lines = {}
        for n = 1, numLines do
            local fs = getglobal("TotemBarScanTipTextLeft" .. n)
            lines[n] = fs and fs:GetText()
        end

        local parsed = TotemBar.parseRange(lines)
        if parsed then
            range = parsed
        end
        scanTip:Hide()
    end

    rangeCache[spellName] = range
    return range
end
