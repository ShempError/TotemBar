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
-- action as the Esc menu). A bar button (by global frame name) -> a CLICK
-- binding on it.
function TotemBar.actionForButton(frameName, totemName)
    if totemName and totemName ~= "" then
        return "TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(totemName)
    end
    if not frameName then
        return nil
    end
    if frameName == "TotemBarButtonRecall" or frameName == "TotemBarButtonDropSet" then
        return "CLICK " .. frameName .. ":LeftButton"
    end
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        if frameName == "TotemBarButton" .. elements[i] then
            return "CLICK " .. frameName .. ":LeftButton"
        end
    end
    return nil
end
