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
    state.index = slot
    state.lastTime = now
    return totemName, element
end
