-- TotemBar - core/spellindex.lua
-- A single cached name -> spellbook-slot index, replacing the four
-- separate linear GetSpellName(i, BOOKTYPE_SPELL) scans that used to be
-- duplicated across ui.lua (FindSpellIndexByName), core/cast.lua
-- (findSpellIndexByName), core/manacost.lua (findHighestRankSlot) and
-- core/known.lua (scanSpellbook/highestKnownRank). Each of those walked
-- the WHOLE spellbook on every call; SPELL_UPDATE_COOLDOWN/cast events
-- fire several of them per totem drop, so a 4-totem-drop macro press
-- could re-walk the book several times in one frame (perf review
-- 2026-07-16, TotemBar finding #14: ui.lua:210 + cast.lua:175 +
-- manacost.lua:116).
--
-- buildSpellIndex() below is PURE (no WoW API) and offline-tested: given
-- a flat array of {name=, rank=} entries in spellbook slot order (array
-- index N == what GetSpellName(N, BOOKTYPE_SPELL) returned for slot N),
-- it returns a name -> record table where each record is:
--   bookIndex    - the FIRST (lowest) slot with this name. Mirrors the
--                  old FindSpellIndexByName/findSpellIndexByName
--                  first-match behavior (icon/cooldown/"is it known"
--                  lookups don't care which rank's slot they read --
--                  GetSpellTexture/GetSpellCooldown are identical across
--                  ranks of the same totem).
--   maxRankIndex - the slot of the HIGHEST parsed rank. Mirrors the old
--                  manacost.lua findHighestRankSlot: this is the slot
--                  CastSpellByName actually casts and the one
--                  tooltip/mana-cost scans must read. Falls back to the
--                  LAST matching slot if no entry's rank string for this
--                  name ever parsed a number (matches the old
--                  fallback -- ranks are listed ascending, so the last
--                  slot is still the best guess).
--   maxRank      - the highest parsed rank NUMBER, or nil if none of
--                  this name's entries carried a parseable rank. Mirrors
--                  the old known.lua highestKnownRank() return value.

TotemBar = TotemBar or {}

function TotemBar.buildSpellIndex(entries)
    local idx = {}
    if not entries then
        return idx
    end
    for i = 1, table.getn(entries) do
        local e = entries[i]
        local name = e and e.name
        if name then
            local rec = idx[name]
            if not rec then
                rec = { bookIndex = i, maxRankIndex = i, maxRank = nil }
                idx[name] = rec
            end
            local _, _, numStr = string.find(e.rank or "", "(%d+)")
            local num = numStr and tonumber(numStr)
            if num and (not rec.maxRank or num > rec.maxRank) then
                rec.maxRank = num
                rec.maxRankIndex = i
            elseif not rec.maxRank then
                -- No rank number has parsed for this name in any entry
                -- seen so far; keep sliding the fallback to the LAST
                -- matching slot (mirrors the old findHighestRankSlot
                -- fallback for names whose rank string never parses).
                rec.maxRankIndex = i
            end
        end
    end
    return idx
end

-- ===== WoW-API layer (not offline-executed) =====
-- Guarded by CreateFrame's presence, same as manacost.lua's own event
-- block, so dofile-ing this module under plain Lua (offline tests)
-- never errors.

local cachedEntries = nil   -- flat array {name=, rank=}, 1..n, book order
local cachedIndex = nil     -- name -> {bookIndex, maxRankIndex, maxRank}

local function scanLiveSpellbook()
    local entries = {}
    local i = 1
    while true do
        local name, rank = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then
            break
        end
        entries[i] = { name = name, rank = rank }
        i = i + 1
    end
    return entries
end

local function ensureBuilt()
    if cachedIndex then
        return
    end
    cachedEntries = scanLiveSpellbook()
    cachedIndex = TotemBar.buildSpellIndex(cachedEntries)
end

-- Drops the cache; the next accessor call below rebuilds it from a
-- fresh scan (lazy -- nothing re-scans until actually asked for). Wired
-- to SPELLS_CHANGED below; also safe to call manually.
function TotemBar.invalidateSpellIndex()
    cachedEntries = nil
    cachedIndex = nil
end

-- Returns the cached name -> record index, building it lazily on first
-- access. Lazy-build matters at login/reload: the spellbook
-- (GetSpellName/GetSpellTexture) isn't reliably populated as early as
-- ADDON_LOADED fires (see ui.lua's own SPELLS_CHANGED comment) -- an
-- eager build at file-load time could cache an empty book.
function TotemBar.getSpellIndex()
    ensureBuilt()
    return cachedIndex
end

-- How many spellbook slots the cached scan holds (0 when the book was empty
-- at scan time). Lets a caller tell "this spell is provably NOT known" apart
-- from "we have no usable spellbook data yet" -- the book isn't reliably
-- populated at login, and the cache is built lazily, so a nil findSpellIndex
-- alone can't distinguish the two. Used by core/cast.lua's recordCast.
function TotemBar.spellbookEntryCount()
    ensureBuilt()
    return table.getn(cachedEntries)
end

-- Mirrors old FindSpellIndexByName (ui.lua) / findSpellIndexByName
-- (cast.lua): first-match spellbook slot, or nil if unknown.
function TotemBar.findSpellIndex(name)
    if not name then
        return nil
    end
    local rec = TotemBar.getSpellIndex()[name]
    return rec and rec.bookIndex
end

-- Mirrors old manacost.lua findHighestRankSlot: the slot of the
-- highest-known rank, or nil if unknown.
function TotemBar.findHighestRankSlot(name)
    if not name then
        return nil
    end
    local rec = TotemBar.getSpellIndex()[name]
    return rec and rec.maxRankIndex
end

-- Mirrors old known.lua highestKnownRank: the highest known rank
-- NUMBER, or nil if unknown / no rank string ever parsed.
function TotemBar.highestKnownRank(name)
    if not name then
        return nil
    end
    local rec = TotemBar.getSpellIndex()[name]
    return rec and rec.maxRank
end

-- Mirrors old known.lua scanSpellbook: flat array of every spellbook
-- entry's name, ONE PER SLOT (a multi-rank totem appears once per rank
-- it has) -- ShowFlyout's knownTotems() filter and PrintScan's raw dump
-- both rely on that shape. The by-name index above intentionally
-- collapses ranks together, so this stays a separate view over the same
-- cached scan rather than something derived from the index.
function TotemBar.scanSpellbook()
    ensureBuilt()
    local names = {}
    for i = 1, table.getn(cachedEntries) do
        names[i] = cachedEntries[i].name
    end
    return names
end

-- SPELLS_CHANGED is the event this codebase already relies on elsewhere
-- (manacost.lua's manaCache, ui.lua's icon refresh) for "spellbook
-- changed" -- fires on learning a new spell/rank and on talent changes.
-- LEARNED_SPELL_IN_TAB was checked and does not exist as a 1.12 client
-- event (not in this project's confirmed WoW 1.12 event list; it's a
-- later-expansion API) -- SPELLS_CHANGED alone is the correct signal.
if CreateFrame then
    local siEvents = CreateFrame("Frame", "TotemBarSpellIndexEventFrame", UIParent)
    siEvents:RegisterEvent("SPELLS_CHANGED")
    siEvents:SetScript("OnEvent", function()
        if event == "SPELLS_CHANGED" then
            TotemBar.invalidateSpellIndex()
        end
    end)
end
