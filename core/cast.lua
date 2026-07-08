-- TotemBar - core/cast.lua
-- Cast-cycle logic. The decision-making is split into two PURE,
-- offline-tested functions (nextIndex, findFilledSlot); castNext() is
-- the thin wrapper that touches CastSpellByName / GetTime / TotemBarDB.

TotemBar = TotemBar or {}

TotemBar.DEFAULT_GAP_SECONDS = 2

-- Cycle state: which slot was cast last, and when.
TotemBar.castState = TotemBar.castState or {
    index = 0,      -- 0 = no cast yet (or state was reset)
    lastTime = 0,
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

-- Records that `totemName` was just cast into `element`'s slot, into
-- TotemBar's own tracking table (see activeTotems above). Touches
-- GetTime() and (for Searing Totem) a spellbook rank scan, so it isn't
-- pure; called from both the bar's left-click path (ui.lua) and
-- castNext() below.
function TotemBar.recordCast(element, totemName)
    if not element or not totemName then
        return
    end
    local highestRank = nil
    if totemName == "Searing Totem" and TotemBar.highestKnownRank then
        highestRank = TotemBar.highestKnownRank(totemName)
    end
    TotemBar.activeTotems[element] = {
        start = GetTime(),
        duration = TotemBar.totemDuration(totemName, highestRank),
    }
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
