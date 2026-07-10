-- TotemBar - bind.lua
-- Key-binding labels (for the Esc > Key Bindings menu) + the cast entry
-- points the Bindings.xml bodies call. Hover-bind mode is added below in a
-- later step. Loaded AFTER Bindings.xml (see the .toc).

TotemBar = TotemBar or {}

local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

-- Section + fixed-action labels.
BINDING_HEADER_TOTEMBAR = "TotemBar"
BINDING_NAME_TOTEMBAR_DROPSET = "Drop all totems"
BINDING_NAME_TOTEMBAR_RECALL = "Totemic Recall"
BINDING_NAME_TOTEMBAR_TOGGLEBAR = "Toggle bar"
BINDING_NAME_TOTEMBAR_TOGGLEOPTIONS = "Toggle options"
BINDING_NAME_TOTEMBAR_TOGGLEBIND = "Toggle key-bind mode"

-- Per-element "cast the chosen totem" labels + per-element sub-headers.
do
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        local e = elements[i]
        setglobal("BINDING_NAME_TOTEMBAR_CAST_" .. string.upper(e), "Cast " .. e .. " totem (chosen)")
        setglobal("BINDING_HEADER_TOTEMBAR_" .. string.upper(e), "TotemBar: " .. e .. " Totems")
    end
    -- Per-totem labels (must match Bindings.xml names via bindingSuffix).
    for i = 1, table.getn(elements) do
        local e = elements[i]
        local list = TotemBar.TOTEMS_BY_ELEMENT[e]
        for j = 1, table.getn(list) do
            local totem = list[j]
            setglobal("BINDING_NAME_TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(totem), "Cast " .. totem)
        end
    end
end

-- Cast a specific totem by name (no-op in-game if not known).
function TotemBar.CastTotem(name)
    if name then
        CastSpellByName(name)
    end
end

-- Cast the currently-chosen totem for an element.
function TotemBar.CastElement(element)
    local n = TotemBarDB and TotemBarDB.chosen and TotemBarDB.chosen[element]
    if n then
        CastSpellByName(n)
    else
        ChatOut:AddMessage("TotemBar: no totem chosen for " .. tostring(element) .. ".")
    end
end

-- Cast Totemic Recall and clear own-tracking (mirrors the Recall button).
function TotemBar.CastRecall()
    -- Don't waste Totemic Recall's 6s cooldown when nothing is out.
    if TotemBar.anyTotemOut and not TotemBar.anyTotemOut() then
        ChatOut:AddMessage("TotemBar: no totems out - not recalling (saves the 6s cooldown).")
        return
    end
    CastSpellByName("Totemic Recall")
    if TotemBar.snapshotRecallCost then TotemBar.snapshotRecallCost() end
    if TotemBar.clearActiveTotems then
        TotemBar.clearActiveTotems()
    end
end

-- Stub so the TOTEMBAR_TOGGLEBIND binding never calls nil before Task 4
-- fills it in. Replaced (same name) by the real implementation below.
if not TotemBar.ToggleBindMode then
    function TotemBar.ToggleBindMode()
        ChatOut:AddMessage("TotemBar: key-bind mode not available.")
    end
end

-- ===== Hover-bind mode =====
-- Toggle a mode where hovering a bar button / flyout totem and pressing a
-- key binds that key to the thing's action (buttons -> CLICK binding, flyout
-- totems -> the named per-totem binding). ESC clears the hovered thing's
-- binding. Bindings persist via the client (SaveBindings), no addon SV.

local bindMode = false
local captureFrame = nil
local infoBox = nil

-- Base keys that are pure modifiers - never bind these alone.
local BARE_MODIFIERS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

function TotemBar.isBindMode()
    return bindMode
end

-- Resolves the mouse-focused frame to a binding action. Uses the pure
-- TotemBar.actionForButton with the frame's global name and, for a flyout
-- icon, its current .totemName.
local function actionForFocus(focus)
    if not focus then
        return nil
    end
    local totemName = focus.totemName   -- set on flyout icon buttons when shown
    local fname = focus.GetName and focus:GetName() or nil
    return TotemBar.actionForButton(fname, totemName)
end

local function ensureCaptureFrame()
    if captureFrame then
        return captureFrame
    end
    local f = CreateFrame("Frame", "TotemBarBindCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableKeyboard(false)
    f:Hide()
    f:SetScript("OnKeyUp", function()
        local key = arg1   -- NOTE: OnKeyUp arg1 = key name string (matches pfUI's hoverbind capture)
        if not key or BARE_MODIFIERS[key] then
            return
        end
        local focus = GetMouseFocus()
        local action = actionForFocus(focus)
        if key == "ESCAPE" and not action then
            -- Keyboard capture swallows all keys while bind mode is on, so
            -- ESC over nothing is the keyboard exit (the options button also
            -- toggles it off). ESC over a button clears that button below.
            TotemBar.ToggleBindMode()
            return
        end
        if not action then
            return
        end
        if key == "ESCAPE" then
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1) end
            if k2 then SetBinding(k2) end
        else
            local full = TotemBar.modifierPrefix(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()) .. key
            SetBinding(full)          -- clear whatever `full` was bound to
            SetBinding(full, action)  -- bind it to this action
        end
        SaveBindings(GetCurrentBindingSet())
        if TotemBar.refreshBindOverlays then
            TotemBar.refreshBindOverlays()
        end
    end)
    captureFrame = f
    return f
end

-- Lazily builds a visible on-screen info box shown while bind mode is
-- active, so the mode (which otherwise only shows via a chat message and
-- stays on until ESC) is hard to miss. Rev 4 UI chrome: shared bespoke
-- panel skin (ui.lua's PANEL_BACKDROP), matching the rest of the addon's
-- chrome, regardless of pfUI presence.
local function ensureBindInfoBox()
    if infoBox then
        return infoBox
    end
    local f = CreateFrame("Frame", "TotemBarBindInfo", UIParent)
    f:SetWidth(380)
    f:SetHeight(80)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Cheap guard: bind.lua loads LAST per the .toc (after ui.lua), so
    -- TotemBar.PANEL_BACKDROP is always set by the time this runs - the
    -- fallback only protects against a future load-order change.
    local backdrop = TotemBar.PANEL_BACKDROP or {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    }
    f:SetBackdrop(backdrop)
    f:SetBackdropColor(1, 1, 1, 0.97)
    local t = f:CreateFontString("TotemBarBindInfoText", "OVERLAY", "GameFontNormal")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)
    t:SetJustifyH("CENTER")
    t:SetText("|cff33ffccKey-Bind Mode ACTIVE|r\nHover a bar button or flyout totem and press a key to bind it.\nESC over a button clears its key.  ESC over empty space (or the options button) exits.")
    if pfUI and pfUI.font_default then
        t:SetFont(pfUI.font_default, 12)
    end
    f:Hide()
    infoBox = f
    return f
end

function TotemBar.ToggleBindMode()
    bindMode = not bindMode
    local f = ensureCaptureFrame()
    if bindMode then
        f:EnableKeyboard(true)
        f:Show()
        ensureBindInfoBox():Show()
        ChatOut:AddMessage("TotemBar: key-bind mode ON - hover a button or flyout totem and press a key to bind. ESC over a button clears its key; ESC over nothing (or the options button) exits.")
    else
        f:EnableKeyboard(false)
        f:Hide()
        if infoBox then
            infoBox:Hide()
        end
        ChatOut:AddMessage("TotemBar: key-bind mode OFF.")
    end
    if TotemBar.refreshBindOverlays then
        TotemBar.refreshBindOverlays()
    end
end

-- Refresh overlays whenever the client's bindings change.
local bindEvents = CreateFrame("Frame", "TotemBarBindEventFrame", UIParent)
bindEvents:RegisterEvent("UPDATE_BINDINGS")
bindEvents:SetScript("OnEvent", function()
    if TotemBar.refreshBindOverlays then
        TotemBar.refreshBindOverlays()
    end
end)
