-- TotemBar - core/bindlogic.lua
-- PURE helpers for keybindings + hover-bind mode (no WoW API), offline-testable.

TotemBar = TotemBar or {}

-- Binding-name suffix for a totem: uppercase, non-alphanumeric runs -> "_",
-- trimmed. "Grace of Air Totem" -> "GRACE_OF_AIR_TOTEM". MUST match the
-- Bindings.xml generation and the BINDING_NAME_ globals.
function TotemBar.bindingSuffix(name)
    if not name then
        return ""
    end
    local up = string.upper(name)
    up = string.gsub(up, "[^A-Z0-9]+", "_")
    up = string.gsub(up, "^_+", "")
    up = string.gsub(up, "_+$", "")
    return up
end

-- Modifier prefix for a key string, order ALT-CTRL-SHIFT (each arg is 1/nil
-- as IsAltKeyDown()/IsControlKeyDown()/IsShiftKeyDown() return on 1.12).
function TotemBar.modifierPrefix(isAlt, isCtrl, isShift)
    local p = ""
    if isAlt then p = p .. "ALT-" end
    if isCtrl then p = p .. "CTRL-" end
    if isShift then p = p .. "SHIFT-" end
    return p
end

-- Binding COMMAND for a hovered thing, or nil. A flyout icon (totemName
-- given) -> the named per-totem binding (casts that specific totem, same
-- action as the Esc menu). A bar button (by global frame name) -> the
-- matching NAMED binding that already exists in Bindings.xml (NOT a
-- "CLICK ..." binding - those are unreliable on 1.12, see bind.lua).
function TotemBar.actionForButton(frameName, totemName)
    if totemName and totemName ~= "" then
        return "TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(totemName)
    end
    if not frameName then
        return nil
    end
    if frameName == "TotemBarButtonRecall" then
        return "TOTEMBAR_RECALL"
    end
    if frameName == "TotemBarButtonDropSet" then
        return "TOTEMBAR_DROPSET"
    end
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        if frameName == "TotemBarButton" .. elements[i] then
            return "TOTEMBAR_CAST_" .. string.upper(elements[i])
        end
    end
    return nil
end

-- Compact a binding key string for a small button overlay:
-- "SHIFT-NUMPAD7" -> "sN7", "BUTTON4" -> "M4", "MOUSEWHEELUP" -> "MwU".
function TotemBar.shortenKey(key)
    if not key or key == "" then
        return ""
    end
    local s = key
    s = string.gsub(s, "ALT%-", "a")
    s = string.gsub(s, "CTRL%-", "c")
    s = string.gsub(s, "SHIFT%-", "s")
    s = string.gsub(s, "MOUSEWHEELUP", "MwU")
    s = string.gsub(s, "MOUSEWHEELDOWN", "MwD")
    s = string.gsub(s, "NUMPAD", "N")
    s = string.gsub(s, "BUTTON", "M")
    s = string.gsub(s, "SPACE", "Sp")
    return s
end
