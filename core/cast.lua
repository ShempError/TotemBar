-- TotemBar - core/cast.lua
-- Cast-cycle logic. The decision-making is split into two PURE,
-- offline-tested functions (nextIndex, findFilledSlot); castNext() is
-- the thin wrapper that touches CastSpellByName / GetTime / TotemBarDB.

TotemBar = TotemBar or {}

TotemBar.DEFAULT_GAP_SECONDS = 2

-- Anti double-press guard for recallAndCastAll: if a deploy happened within
-- this many seconds, a rapid second press SKIPS the recall (so it doesn't
-- pull the just-placed totems, which are still on their ~1.5s element
-- cooldown and couldn't be re-placed).
TotemBar.DEFAULT_RECALL_GUARD = 2

-- Cycle state: which slot was cast last, and when.
TotemBar.castState = TotemBar.castState or {
    index = 0,      -- 0 = no cast yet (or state was reset)
    lastTime = 0,
    lastDeployTime = 0,
}

-- Own-tracking table for the OmniCC-style remaining-duration display in
-- ui.lua: fallback source for when pfUI's libtotem (GetTotemInfo) isn't
-- present, or reports a given slot inactive. element -> {start=,
-- duration=}, both in TotemBar.recordCast() below.
TotemBar.activeTotems = TotemBar.activeTotems or {}

-- Pure: given the previously cast slot index, the time of that previous
-- cast, the current time, the allowed gap (seconds) and the number of
-- slots, returns the next slot index (1-based) to advance to.
--
-- - prevIndex <= 0 (never cast yet)      -> 1
-- - now - lastTime > gapSeconds          -> 1 (fresh spam, start over)
-- - otherwise                            -> prevIndex + 1, wrapping from
--                                            numSlots back to 1
function TotemBar.nextIndex(prevIndex, lastTime, now, gapSeconds, numSlots)
    if not prevIndex or prevIndex <= 0 then
        return 1
    end
    if not lastTime or (now - lastTime) > gapSeconds then
        return 1
    end
    local nxt = prevIndex + 1
    if nxt > numSlots then
        nxt = 1
    end
    return nxt
end

-- Pure: starting at startIndex, walk forward through `elements`
-- (wrapping past the end back to 1) and return the index of the first
-- element for which chosen[element] is truthy (a totem name). Returns
-- nil if none of the slots are filled.
function TotemBar.findFilledSlot(chosen, elements, startIndex)
    local numSlots = table.getn(elements)
    if numSlots == 0 or not startIndex then
        return nil
    end
    for tries = 0, numSlots - 1 do
        local slot = startIndex + tries
        if slot > numSlots then
            slot = slot - numSlots
        end
        if chosen[elements[slot]] then
            return slot
        end
    end
    return nil
end

-- Pure: seconds remaining given a start time, a duration and the
-- current time. May return <= 0 (already expired); callers decide how
-- to treat that. Returns nil if either start or duration is missing.
function TotemBar.remaining(start, duration, now)
    if not start or not duration then
        return nil
    end
    return start + duration - now
end

-- Pure: decides which of two already-computed remaining-seconds values
-- to show for one element's timer text. GetTotemInfo (pfUI's
-- libtotem), when it reports the slot active, is authoritative;
-- otherwise (absent, or reporting the slot inactive) falls back to
-- TotemBar's own cast-tracking. Returns nil when neither source has
-- time left.
function TotemBar.resolveRemaining(gtiActive, gtiRemaining, ownRemaining)
    if gtiActive then
        if gtiRemaining and gtiRemaining > 0 then
            return gtiRemaining
        end
        return nil
    end
    if ownRemaining and ownRemaining > 0 then
        return ownRemaining
    end
    return nil
end

-- Pure: OmniCC-style text for an already-known-positive remaining
-- seconds value: whole minutes rounded up from 60s on, plain rounded-up
-- integer seconds below that.
function TotemBar.formatRemaining(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.ceil(remaining / 60))
    end
    return string.format("%d", math.ceil(remaining))
end

-- Finds the spellbook index of a known spell by exact name, or nil.
-- Thin WoW-API wrapper; mirrors ui.lua's own file-local
-- FindSpellIndexByName (kept separate rather than shared, since there's
-- no common "api" module to hang a single copy off yet).
local function findSpellIndexByName(name)
    if not name then
        return nil
    end
    local i = 1
    while true do
        local spellName = GetSpellName(i, BOOKTYPE_SPELL)
        if not spellName then
            return nil
        end
        if spellName == name then
            return i
        end
        i = i + 1
    end
end

-- Records that `totemName` was just cast into `element`'s slot, into
-- TotemBar's own tracking table (see activeTotems above). Touches
-- GetTime(), a spellbook index/texture scan and (for Searing Totem) a
-- rank scan, so it isn't pure; called from both the bar's left-click
-- path (ui.lua) and castNext()/castAll() below.
--
-- Also stashes the totem spell's icon texture (rec.icon) and a
-- self-learning "did I ever see this totem's buff" flag
-- (rec.everHadBuff, starts false). ui.lua's out-of-range red-tint
-- feature is buff-presence based: a totem's party buff uses the SAME
-- icon texture as the totem spell itself (verified in-game), so
-- TotemBar.hasBuffWithIcon(rec.icon) tells whether the player is
-- currently benefiting from THIS cast totem.
function TotemBar.recordCast(element, totemName)
    if not element or not totemName then
        return
    end
    local highestRank = nil
    if totemName == "Searing Totem" and TotemBar.highestKnownRank then
        highestRank = TotemBar.highestKnownRank(totemName)
    end
    local icon = nil
    local idx = findSpellIndexByName(totemName)
    if idx then
        icon = GetSpellTexture(idx, BOOKTYPE_SPELL)
    end
    local rec = {
        start = GetTime(),
        duration = TotemBar.durationWithMastery(
            TotemBar.totemDuration(totemName, highestRank),
            TotemBar.isHelpfulTotem(totemName),
            TotemBar.hasTotemicMastery and TotemBar.hasTotemicMastery()),
        totemName = totemName,
        icon = icon,
        everHadBuff = false,
    }
    TotemBar.activeTotems[element] = rec
end

-- Module-scratch table for the buff-texture scan below, reused every
-- call (hasBuffWithIcon runs ~5x/sec, from ui.lua's throttled timer
-- tick) so it doesn't allocate a new table each time. buffScratchLen
-- tracks how far the previous scan filled it, so leftover entries past
-- the new scan's length get nilled out - keeping it a clean, hole-free
-- 1..n array (table.getn needs that to be reliable in Lua 5.0).
local buffScratch = {}
local buffScratchLen = 0

-- Pure: given a flat array of buff texture path strings (some entries
-- may be nil) and a totem spell's icon texture path, returns true if
-- any buff texture matches iconPath via a case-insensitive literal
-- substring search (tolerates path/casing differences between
-- GetSpellTexture's and UnitBuff's returned strings). Returns false if
-- iconPath or buffTexList is nil, or nothing matches.
function TotemBar.buffTexturesMatch(buffTexList, iconPath)
    if not iconPath or not buffTexList then
        return false
    end
    local needle = string.lower(iconPath)
    for i = 1, table.getn(buffTexList) do
        local tex = buffTexList[i]
        if tex and string.find(string.lower(tex), needle, 1, true) then
            return true
        end
    end
    return false
end

-- Thin WoW-API wrapper: scans the player's current buffs (UnitBuff
-- "player" 1..32, stopping at the first nil slot) into the reusable
-- buffScratch table, then hands it to the pure
-- TotemBar.buffTexturesMatch() above. This is the "am I in this totem's
-- range?" signal for ui.lua's red-tint feature: a totem's party buff
-- shares its spell's icon texture (verified in-game), so having a
-- matching buff means the totem is currently affecting the player.
function TotemBar.hasBuffWithIcon(iconPath)
    if not iconPath then
        return false
    end
    local n = 0
    for i = 1, 32 do
        local tex = UnitBuff("player", i)
        if not tex then
            break
        end
        n = n + 1
        buffScratch[n] = tex
    end
    for i = n + 1, buffScratchLen do
        buffScratch[i] = nil
    end
    buffScratchLen = n
    return TotemBar.buffTexturesMatch(buffScratch, iconPath)
end

-- Clears every own-tracked totem timer at once (e.g. after Totemic
-- Recall, which drops all active totems simultaneously).
function TotemBar.clearActiveTotems()
    for i = 1, table.getn(TotemBar.TOTEM_ELEMENTS) do
        TotemBar.activeTotems[TotemBar.TOTEM_ELEMENTS[i]] = nil
    end
end

-- Casts exactly ONE totem per call: the next slot in Fire -> Earth ->
-- Water -> Air order, skipping empty (unassigned) slots. If more than
-- gapSeconds has passed since the previous call, the cycle restarts at
-- the first filled slot (so a fresh spam always begins with totem 1).
--
-- Intended for a macro: `/script TotemBar.castNext()`
function TotemBar.castNext()
    local db = TotemBarDB
    local chosen = (db and db.chosen) or {}
    local gap = (db and db.gapSeconds) or TotemBar.DEFAULT_GAP_SECONDS
    local elements = TotemBar.TOTEM_ELEMENTS
    local numSlots = table.getn(elements)
    local now = GetTime()

    local state = TotemBar.castState
    local startIdx = TotemBar.nextIndex(state.index, state.lastTime, now, gap, numSlots)
    local slot = TotemBar.findFilledSlot(chosen, elements, startIdx)

    if not slot then
        -- Nothing assigned to any element; nothing to cast.
        state.index = 0
        state.lastTime = now
        return nil, nil
    end

    local element = elements[slot]
    local totemName = chosen[element]
    CastSpellByName(totemName)
    TotemBar.recordCast(element, totemName)
    state.index = slot
    state.lastTime = now
    return totemName, element
end

-- Casts ALL filled slots in a single call (Fire -> Earth -> Water ->
-- Air). On TurtleWoW each totem element has its own cooldown, so this
-- MAY drop all four from one keypress. Whether 4 CastSpellByName calls
-- in one Lua frame all land (vs only the last "winning") is unverified
-- on this client -- offered as a one-press alternative to castNext() to
-- test in-game.
--
-- Intended for a macro: `/script TotemBar.castAll()`
function TotemBar.castAll()
    local db = TotemBarDB
    local chosen = (db and db.chosen) or {}
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        local element = elements[i]
        local totemName = chosen[element]
        if totemName then
            CastSpellByName(totemName)
            TotemBar.recordCast(element, totemName)
        end
    end
end

-- Pure: should recallAndCastAll fire Totemic Recall this call?
--   autoRecall off              -> false (never recall)
--   never deployed (nil / <=0)  -> true  (nothing fresh to protect)
--   last deploy > guard ago     -> true
--   last deploy within guard    -> false (protect just-placed totems from a
--                                  rapid accidental second press)
function TotemBar.shouldRecall(autoRecall, lastDeployTime, now, guardSeconds)
    if not autoRecall then
        return false
    end
    if not lastDeployTime or lastDeployTime <= 0 then
        return true
    end
    if not guardSeconds then
        return true
    end
    if (now - lastDeployTime) > guardSeconds then
        return true
    end
    return false
end

-- Recall-then-deploy: when TotemBarDB.autoRecall is on (the default -
-- toggleable via the Recall button's right-click, see ui.lua), casts
-- Totemic Recall FIRST (drops existing totems and refunds some mana)
-- and clears own-tracking, then always places all filled slots via
-- castAll(). One keypress = recall + redeploy (or just redeploy, with
-- the flag off). Like castAll, relies on TurtleWoW allowing several
-- CastSpellByName calls in one Lua frame -- verify in-game.
--
-- Guarded against rapid double-presses: shouldRecall() only fires Recall
-- if the last deploy was more than DEFAULT_RECALL_GUARD seconds ago. A
-- fast accidental second press then just re-attempts placement (a no-op,
-- since the totems are still up and each element is on its own ~1.5s
-- cooldown) instead of recalling the totems that were just placed.
--
-- Intended for a macro: `/script TotemBar.recallAndCastAll()`
function TotemBar.recallAndCastAll()
    local now = GetTime()
    local autoRecall = TotemBarDB and TotemBarDB.autoRecall
    local guard = (TotemBarDB and TotemBarDB.recallGuardSeconds) or TotemBar.DEFAULT_RECALL_GUARD
    if TotemBar.shouldRecall(autoRecall, TotemBar.castState.lastDeployTime, now, guard) then
        CastSpellByName("Totemic Recall")
        TotemBar.clearActiveTotems()
    end
    TotemBar.castAll()
    TotemBar.castState.lastDeployTime = now
end
