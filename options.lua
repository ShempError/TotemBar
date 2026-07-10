-- TotemBar - options.lua
-- Standalone options panel (no Blizzard InterfaceOptions integration). Built
-- once (lazy) on first ToggleOptions; repopulated from TotemBarDB on show.
-- Opened by the minimap button's left-click and by /tb options. WoW-API
-- file (parse-checked only). Widget wiring uses 1.12 templates:
-- UICheckButtonTemplate (GetChecked() -> 1/nil) and OptionsSliderTemplate
-- (SetMinMaxValues before SetValue; $parentLow/$parentHigh/$parentText).

TotemBar = TotemBar or {}

local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1
local optionsFrame = nil

-- Applies pfUI's font to a FontString (the main "matches pfUI" tweak) at the
-- given size, or falls back to a small game font when pfUI is absent.
local function ApplyFont(fontString, size)
    if not fontString then
        return
    end
    if pfUI and pfUI.font_default then
        local sz = size or (pfUI_config and pfUI_config.global and pfUI_config.global.font_size) or 12
        fontString:SetFont(pfUI.font_default, sz)
    else
        fontString:SetFontObject(GameFontNormalSmall)
    end
end

-- Adds a wrapped explanatory GameTooltip on hover. Chains any existing
-- OnEnter/OnLeave (e.g. pfUI's SkinButton hover-highlight) instead of
-- replacing it, so skinning still works. No HookScript on 1.12.
local function AddTooltip(widget, text)
    if not widget or not text then
        return
    end
    widget.tbTip = text
    local oldEnter = widget:GetScript("OnEnter")
    local oldLeave = widget:GetScript("OnLeave")
    widget:SetScript("OnEnter", function()
        if oldEnter then oldEnter() end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(this.tbTip, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function()
        if oldLeave then oldLeave() end
        GameTooltip:Hide()
    end)
end

-- Unique widget-name counters (template child labels resolve via getglobal,
-- so every widget needs a non-nil, unique frame name).
local cbIndex = 0
local slIndex = 0

-- Factory: a labeled checkbox wired to getter/setter. getter()->boolean,
-- setter(boolean). Returns the CheckButton.
local function CreateCheckbox(parent, label, getter, setter)
    cbIndex = cbIndex + 1
    local name = "TotemBarOptCheck" .. cbIndex
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    local lbl = getglobal(name .. "Text")
    if lbl then
        lbl:SetText(label)
        ApplyFont(lbl)
    end
    cb.tbGet = getter
    cb.tbSet = setter
    cb:SetScript("OnClick", function()
        this.tbSet(this:GetChecked() == 1)
    end)
    if pfUI and pfUI.api and pfUI.api.SkinCheckbox then
        pfUI.api.SkinCheckbox(cb)
    end
    return cb
end

-- Factory: a labeled slider wired to getter/setter over [minVal,maxVal] in
-- `step` increments. `fmt` is a printf pattern for the live value text
-- (e.g. "UI size: %.2f"). Returns the Slider.
local function CreateSlider(parent, label, minVal, maxVal, step, fmt, getter, setter)
    slIndex = slIndex + 1
    local name = "TotemBarOptSlider" .. slIndex
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetWidth(200)
    sl:SetHeight(16)
    sl:SetMinMaxValues(minVal, maxVal)   -- BEFORE SetValue, else clamps to 0
    sl:SetValueStep(step)
    local low, high, txt = getglobal(name .. "Low"), getglobal(name .. "High"), getglobal(name .. "Text")
    if low then low:SetText(tostring(minVal)); ApplyFont(low) end
    if high then high:SetText(tostring(maxVal)); ApplyFont(high) end
    if txt then
        -- Left-align the value label above the slider (the template centers it),
        -- so it lines up with the left-aligned checkbox labels. pfUI font.
        txt:ClearAllPoints()
        txt:SetPoint("BOTTOMLEFT", sl, "TOPLEFT", 0, 2)
        txt:SetJustifyH("LEFT")
        ApplyFont(txt)
    end
    sl.tbLabel = label
    sl.tbFmt = fmt
    sl.tbText = txt
    sl.tbSet = setter
    sl.tbGet = getter
    sl:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        if this.tbText then
            this.tbText:SetText(string.format(this.tbFmt, v))
        end
        this.tbSet(v)
    end)
    if pfUI and pfUI.api and pfUI.api.SkinSlider then
        pfUI.api.SkinSlider(sl)
    end
    return sl
end

-- Label text for the bar-layout cycle button, reflecting the current choice.
local function BarLayoutLabel()
    return "Layout: " .. (TotemBarDB.barLayout or "1x6")
end

-- Factory: a labeled push button wired to an onClick. Returns the Button.
-- Named (CLAUDE.md: name all frames) so the pfDebug profiler can attribute it.
local function CreateButton(parent, name, label, onClick)
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    btn:SetWidth(140)
    btn:SetHeight(22)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    if pfUI and pfUI.api and pfUI.api.SkinButton then
        pfUI.api.SkinButton(btn)
    end
    return btn
end

-- Factory: a static hairline divider spanning the panel's content width at
-- cursor position y (Rev 4 UI chrome, section-break decoration). Anonymous
-- texture - it's a static decoration, not an interactive/named widget.
local function CreateDivider(parent, y)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetTexture(TotemBar.UI_TEXTURE)
    local c = TotemBar.uiCoords[TotemBar.UI_DIVIDER_CELL]
    d:SetTexCoord(c.l, c.r, c.t, c.b)
    d:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -14, y)
    d:SetHeight(7)
    return d
end

-- All widgets, stored so OnShow can repopulate them from TotemBarDB.
local widgets = {}

local function BuildOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local f = CreateFrame("Frame", "TotemBarOptionsFrame", UIParent)
    f:SetWidth(280)
    -- 472 + 44 + 28 + 28 + 44: room for the header emblem (+16, taller than
    -- the old title-only header), two section dividers (+14 each), the
    -- "Show pulse waves" checkbox row (+28, the pulse ring's countdown
    -- readout sits alongside the ripple), the bar-layout cycle button row
    -- (+28), and the "Button spacing" slider row (+44, same slider-row
    -- height as guard/gap/scale above it) - see the layout-cursor deltas
    -- below (same mechanism as the Task-5 height bump).
    f:SetHeight(600)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    -- Rev 4 UI chrome: shared bespoke panel skin (see ui.lua's PANEL_BACKDROP)
    -- instead of the Blizzard dialog backdrop or pfUI's generic skin, so the
    -- options panel matches the bar's own art (emblem/dividers below pair
    -- with this border/bg specifically).
    f:SetBackdrop(TotemBar.PANEL_BACKDROP)
    f:SetBackdropColor(1, 1, 1, 0.97)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)

    -- Plain gold title, no emblem (the Rev-4 totem glyph was removed on
    -- user request - the silhouette read, well, unfortunate).
    local title = f:CreateFontString("TotemBarOptionsTitle", "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetText("TotemBar Options")
    ApplyFont(title, 14)
    title:SetTextColor(0.85, 0.66, 0.31)

    local close = CreateFrame("Button", "TotemBarOptionsClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    if pfUI and pfUI.api and pfUI.api.SkinCloseButton then
        pfUI.api.SkinCloseButton(close, f)
    end

    -- Layout cursor (back to the title-only header spacing).
    local x = 24
    local y = -44
    local function place(w, dy)
        w:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        y = y + dy
    end

    -- Checkboxes.
    widgets.lock = CreateCheckbox(f, "Lock bar",
        function() return TotemBarDB.locked end,
        function(v) TotemBarDB.locked = v end)
    place(widgets.lock, -28)
    AddTooltip(widgets.lock, "Locks the bar in place so you can't drag it by accident. Uncheck to reposition it.")

    widgets.autoRecall = CreateCheckbox(f, "Auto-recall before setting",
        function() return TotemBarDB.autoRecall end,
        function(v)
            TotemBarDB.autoRecall = v
            if TotemBar.RefreshRecallIndicator then TotemBar.RefreshRecallIndicator() end
        end)
    place(widgets.autoRecall, -28)
    AddTooltip(widgets.autoRecall, "When on, the Totems macro casts Totemic Recall before re-dropping your totems (refunds some mana when relocating).")

    widgets.show = CreateCheckbox(f, "Show bar",
        function() return not TotemBarDB.hidden end,
        function(v)
            if v then
                TotemBarDB.hidden = false
                if TotemBarFrame then TotemBarFrame:Show() end
            else
                TotemBarDB.hidden = true
                if TotemBarFrame then TotemBarFrame:Hide() end
            end
        end)
    place(widgets.show, -40)
    AddTooltip(widgets.show, "Shows or hides the totem bar. The choice is remembered between sessions.")

    widgets.ring = CreateCheckbox(f, "Show duration ring",
        function() return TotemBarDB.showDurationRing end,
        function(v)
            TotemBarDB.showDurationRing = v
            if TotemBar.RefreshPulseUI then TotemBar.RefreshPulseUI() end
        end)
    place(widgets.ring, -28)
    AddTooltip(widgets.ring, "Shows a colored arc on each button's ring that empties as the totem's remaining time runs out. The ring frame itself always stays visible.")

    widgets.pulse = CreateCheckbox(f, "Show pulse ring",
        function() return TotemBarDB.showPulseBars end,
        function(v)
            TotemBarDB.showPulseBars = v
            if TotemBar.RefreshPulseUI then TotemBar.RefreshPulseUI() end
        end)
    place(widgets.pulse, -28)
    AddTooltip(widgets.pulse, "Shows a thin inner ring around the icon that fills up toward the totem's next pulse, then resets.")

    widgets.pulseWaves = CreateCheckbox(f, "Show pulse waves",
        function() return TotemBarDB.showPulseWaves end,
        function(v)
            TotemBarDB.showPulseWaves = v
            if TotemBar.RefreshPulseUI then TotemBar.RefreshPulseUI() end
        end)
    place(widgets.pulseWaves, -28)
    AddTooltip(widgets.pulseWaves, "Shows an expanding ripple in the totem's color each time a pulsing totem fires.")

    widgets.timerText = CreateCheckbox(f, "Show countdown text",
        function() return TotemBarDB.showTimerText end,
        function(v)
            TotemBarDB.showTimerText = v
            if TotemBar.RefreshPulseUI then TotemBar.RefreshPulseUI() end
        end)
    place(widgets.timerText, -28)
    AddTooltip(widgets.timerText, "Shows the remaining-seconds text under each element button (the ring shows the same information graphically).")

    -- Bar-layout cycle button: click steps through TotemBar.BAR_LAYOUTS
    -- (wrapping), saves the choice, and re-lays out the live bar.
    widgets.layout = CreateButton(f, "TotemBarOptLayoutButton", BarLayoutLabel(), function()
        local layouts = TotemBar.BAR_LAYOUTS
        local n = table.getn(layouts)
        local current = TotemBarDB.barLayout or "1x6"
        local currentIdx = 1
        for i = 1, n do
            if layouts[i] == current then
                currentIdx = i
            end
        end
        local nextIdx = math.mod(currentIdx, n) + 1
        TotemBarDB.barLayout = layouts[nextIdx]
        this:SetText(BarLayoutLabel())
        if TotemBar.ApplyBarLayout then
            TotemBar.ApplyBarLayout()
        end
    end)
    place(widgets.layout, -28)
    AddTooltip(widgets.layout, "Cycles the bar arrangement: one row of six, two rows of three, or three rows of two.")

    -- Section divider (Rev 4 UI chrome): checkboxes above, sliders below.
    CreateDivider(f, y)
    y = y - 14

    -- Sliders (leave headroom below each for its low/high/value text).
    widgets.guard = CreateSlider(f, "Recall guard (sec)", 0, 5, 0.5, "Recall guard: %.1fs",
        function() return TotemBarDB.recallGuardSeconds end,
        function(v) TotemBarDB.recallGuardSeconds = v end)
    place(widgets.guard, -44)
    AddTooltip(widgets.guard, "A second press of the Totems macro within this many seconds skips Totemic Recall, so a double-press won't pull the totems you just dropped. 0 = no guard.")

    widgets.gap = CreateSlider(f, "Cycle reset gap (sec)", 0.5, 5, 0.5, "Cycle gap: %.1fs",
        function() return TotemBarDB.gapSeconds end,
        function(v) TotemBarDB.gapSeconds = v end)
    place(widgets.gap, -44)
    AddTooltip(widgets.gap, "How long a pause (in seconds) restarts the one-per-press cast cycle back at the first totem.")

    widgets.scale = CreateSlider(f, "UI size", 0.5, 2.0, 0.05, "UI size: %.2f",
        function() return TotemBarDB.scale end,
        function(v)
            if TotemBar.SetBarScale then
                TotemBar.SetBarScale(v)
            elseif TotemBarFrame then
                TotemBarDB.scale = v
                TotemBarFrame:SetScale(v)
            end
        end)
    place(widgets.scale, -44)
    AddTooltip(widgets.scale, "Scales the whole bar. It stays anchored at its top-left corner, and the flyout scales with it.")

    widgets.buttonGap = CreateSlider(f, "Button spacing", 10, 30, 1, "Spacing: %.0fpx",
        function() return TotemBarDB.buttonGap end,
        function(v)
            if TotemBar.SetButtonGap then
                TotemBar.SetButtonGap(v)
            else
                TotemBarDB.buttonGap = v
            end
        end)
    place(widgets.buttonGap, -44)
    AddTooltip(widgets.buttonGap, "Distance between the bar buttons. Applies immediately.")

    -- Section divider (Rev 4 UI chrome): sliders above, action buttons below.
    CreateDivider(f, y)
    y = y - 14

    optionsFrame = f
    -- Buttons (Reset position, Create macro) are added in Task 4.
    if TotemBar.BuildOptionsButtons then
        TotemBar.BuildOptionsButtons(f, x, y)
    end

    -- Repopulate every widget from TotemBarDB whenever the panel shows.
    f:SetScript("OnShow", function()
        widgets.lock:SetChecked(TotemBarDB.locked and 1 or nil)
        widgets.autoRecall:SetChecked(TotemBarDB.autoRecall and 1 or nil)
        widgets.show:SetChecked((not TotemBarDB.hidden) and 1 or nil)
        widgets.ring:SetChecked(TotemBarDB.showDurationRing and 1 or nil)
        widgets.pulse:SetChecked(TotemBarDB.showPulseBars and 1 or nil)
        widgets.pulseWaves:SetChecked(TotemBarDB.showPulseWaves and 1 or nil)
        widgets.timerText:SetChecked(TotemBarDB.showTimerText and 1 or nil)
        widgets.layout:SetText(BarLayoutLabel())
        widgets.guard:SetValue(TotemBar.clampValue(TotemBarDB.recallGuardSeconds, 0, 5))
        widgets.gap:SetValue(TotemBar.clampValue(TotemBarDB.gapSeconds, 0.5, 5))
        widgets.scale:SetValue(TotemBar.clampValue(TotemBarDB.scale, 0.5, 2.0))
        widgets.buttonGap:SetValue(TotemBar.clampValue(TotemBarDB.buttonGap, 10, 30))
    end)

    -- Version footer (bottom-centre), read from the .toc so it always matches
    -- the real addon version instead of a hardcoded duplicate.
    local ver = (GetAddOnMetadata and GetAddOnMetadata("TotemBar", "Version")) or "0.1.0"
    local verFS = f:CreateFontString("TotemBarOptionsVersion", "OVERLAY")
    ApplyFont(verFS, 10)
    verFS:SetPoint("BOTTOM", f, "BOTTOM", 0, 6)
    verFS:SetText("v" .. ver)
    verFS:SetTextColor(0.6, 0.6, 0.6)

    -- ESC closes it.
    tinsert(UISpecialFrames, "TotemBarOptionsFrame")

    f:Hide()
    return f
end

-- Creates or updates the "Totems" convenience macro from TotemBar.macroSpec.
-- General (account) macro, capped at 18 in 1.12; if the cap is full and no
-- "Totems" macro exists yet, reports and does nothing. Never auto-places it
-- on the action bar (no 1.12 API for that - the player drags it).
local function ApplyTotemsMacro()
    local name, body, icon = TotemBar.macroSpec()
    local existing = GetMacroIndexByName(name)
    if existing and existing > 0 then
        EditMacro(existing, name, icon, body, 1, nil)
        ChatOut:AddMessage("TotemBar: '" .. name .. "' macro updated - drag it to your action bar.")
        return
    end
    local numGlobal = GetNumMacros()   -- returns global, perChar in 1.12
    if numGlobal and numGlobal >= 18 then
        ChatOut:AddMessage("TotemBar: macro slots full (18) - free one and retry.")
        return
    end
    CreateMacro(name, icon, body, nil)
    ChatOut:AddMessage("TotemBar: '" .. name .. "' macro created - drag it to your action bar.")
end

-- Adds the Reset-position and Create-macro buttons to the options frame.
-- Called by BuildOptionsFrame (Task 3) after the sliders, at layout cursor
-- (x, yStart). Kept separate so the panel body and the action buttons are
-- two focused units.
function TotemBar.BuildOptionsButtons(f, x, yStart)
    -- Full content width (frame width minus the left/right margin x), so the
    -- buttons read as a balanced block instead of a narrow left-biased pair.
    local w = f:GetWidth() - (x * 2)

    local reset = CreateButton(f, "TotemBarOptResetButton", "Reset position", function()
        if TotemBar.ResetPosition then TotemBar.ResetPosition() end
    end)
    reset:SetWidth(w)
    reset:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart)
    AddTooltip(reset, "Moves the bar back to the center of the screen.")

    local macro = CreateButton(f, "TotemBarOptMacroButton", "Create 'Totems' macro", function()
        ApplyTotemsMacro()
    end)
    macro:SetWidth(w)
    macro:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart - 28)
    AddTooltip(macro, "Creates or updates a 'Totems' macro that drops all four chosen totems in one press. Drag it from the macro window to your action bar.")

    local bind = CreateButton(f, "TotemBarOptBindButton", "Key bind mode", function()
        if TotemBar.ToggleBindMode then TotemBar.ToggleBindMode() end
    end)
    bind:SetWidth(w)
    bind:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart - 56)
    AddTooltip(bind, "Toggle bind mode, then hover any bar button or a flyout totem and press a key to bind it. ESC clears. Bindings are saved automatically.")
end

-- Show/hide the options panel (builds it lazily). Left-click on the minimap
-- button and /tb options both call this.
function TotemBar.ToggleOptions()
    local f = BuildOptionsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
