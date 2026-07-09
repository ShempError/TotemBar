-- TotemBar - core/assign.lua
-- Assignment receiver seam: the contract + pure logic by which an external
-- assigner (future "ShamiPower") hands TotemBar a proposed totem set.
-- WoW-API-light so the logic below is offline-testable under real Lua 5.0.
-- The pending-suggestion UI lives in ui.lua and is reached through the
-- optional hook slots (ShowAssignPanel/HideAssignPanel/isTotemKnown/
-- RefreshAll) that ui.lua fills in at load time.
--
-- An "assignment set" is a table keyed by element -> totem spell name:
--   { Fire = "Searing Totem", Air = "Windfury Totem", ... }
-- Any subset of elements; a missing element means "nothing for that slot".

TotemBar = TotemBar or {}

-- True if `key` is one of the four totem elements.
function TotemBar.isElement(key)
    if not key then
        return false
    end
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        if elements[i] == key then
            return true
        end
    end
    return false
end

-- Validates an assignment set. Returns true, or false plus a reason string.
function TotemBar.validateAssignment(set)
    if type(set) ~= "table" then
        return false, "set must be a table"
    end
    local count = 0
    for k, v in pairs(set) do
        if not TotemBar.isElement(k) then
            return false, "unknown element key: " .. tostring(k)
        end
        if type(v) ~= "string" or v == "" then
            return false, "totem name for " .. tostring(k) .. " must be a non-empty string"
        end
        count = count + 1
    end
    if count == 0 then
        return false, "set is empty"
    end
    return true
end

-- Shallow copy of a set, keeping only valid element keys.
function TotemBar.copySet(set)
    local out = {}
    if type(set) == "table" then
        for k, v in pairs(set) do
            if TotemBar.isElement(k) then
                out[k] = v
            end
        end
    end
    return out
end

-- Fresh copy (element -> name) of the currently chosen totems.
function TotemBar.GetChosenSet()
    local out = {}
    local chosen = TotemBarDB and TotemBarDB.chosen
    if chosen then
        local elements = TotemBar.TOTEM_ELEMENTS
        for i = 1, table.getn(elements) do
            local e = elements[i]
            if chosen[e] then
                out[e] = chosen[e]
            end
        end
    end
    return out
end

-- Splits a set into applied (isKnown(name) true) and skipped (false).
function TotemBar.filterKnown(set, isKnown)
    local applied, skipped = {}, {}
    for k, v in pairs(set) do
        if isKnown(v) then
            applied[k] = v
        else
            skipped[k] = v
        end
    end
    return applied, skipped
end

-- Current pending assignment: { set = {element=name,...}, label = string } or nil.
-- In-memory only (not a SavedVariable) - an assignment is ephemeral coordination.
TotemBar.pending = nil

-- Optional hook, filled by an external assigner: called with the applied
-- set table after the player accepts. Nil by default.
TotemBar.onAssignmentApplied = nil

-- THE SEAM. An external assigner calls this to propose a set. Validates,
-- stores it as the pending suggestion (replacing any prior), and asks the
-- UI to show the panel. Does NOT apply. Returns true, or false + reason.
function TotemBar.ReceiveAssignment(set, label)
    local ok, reason = TotemBar.validateAssignment(set)
    if not ok then
        return false, reason
    end
    TotemBar.pending = { set = TotemBar.copySet(set), label = label }
    if TotemBar.ShowAssignPanel then
        TotemBar.ShowAssignPanel()
    end
    return true
end

-- Drops any pending suggestion and hides the panel (decline / post-apply).
function TotemBar.ClearAssignment()
    TotemBar.pending = nil
    if TotemBar.HideAssignPanel then
        TotemBar.HideAssignPanel()
    end
end

-- Applies the pending suggestion: sets each KNOWN totem as the chosen
-- default for its element (unknown totems are skipped), refreshes the bar,
-- clears pending, hides the panel, and fires onAssignmentApplied. No cast.
function TotemBar.ApplyPending()
    local p = TotemBar.pending
    if not p then
        return
    end
    local isKnown = TotemBar.isTotemKnown or function() return true end
    local applied = TotemBar.filterKnown(p.set, isKnown)
    TotemBarDB.chosen = TotemBarDB.chosen or {}
    for element, name in pairs(applied) do
        TotemBarDB.chosen[element] = name
    end
    if TotemBar.RefreshAll then
        TotemBar.RefreshAll()
    end
    TotemBar.pending = nil
    if TotemBar.HideAssignPanel then
        TotemBar.HideAssignPanel()
    end
    if TotemBar.onAssignmentApplied then
        TotemBar.onAssignmentApplied(applied)
    end
end
