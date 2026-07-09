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
        lbl:SetFontObject(GameFontNormalSmall)
    end
    cb.tbGet = getter
    cb.tbSet = setter
    cb:SetScript("OnClick", function()
        this.tbSet(this:GetChecked() == 1)
    end)
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
    if low then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
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
    return sl
end

-- Factory: a labeled push button wired to an onClick. Returns the Button.
local function CreateButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(140)
    btn:SetHeight(22)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- All widgets, stored so OnShow can repopulate them from TotemBarDB.
local widgets = {}

local function BuildOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local f = CreateFrame("Frame", "TotemBarOptionsFrame", UIParent)
    f:SetWidth(280)
    f:SetHeight(360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)

    local title = f:CreateFontString("TotemBarOptionsTitle", "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("TotemBar Options")

    local close = CreateFrame("Button", "TotemBarOptionsClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

    -- Layout cursor.
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

    widgets.autoRecall = CreateCheckbox(f, "Auto-recall before setting",
        function() return TotemBarDB.autoRecall end,
        function(v)
            TotemBarDB.autoRecall = v
            if TotemBar.RefreshRecallIndicator then TotemBar.RefreshRecallIndicator() end
        end)
    place(widgets.autoRecall, -28)

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

    -- Sliders (leave headroom below each for its low/high/value text).
    widgets.guard = CreateSlider(f, "Recall guard (sec)", 0, 5, 0.5, "Recall guard: %.1fs",
        function() return TotemBarDB.recallGuardSeconds end,
        function(v) TotemBarDB.recallGuardSeconds = v end)
    place(widgets.guard, -44)

    widgets.gap = CreateSlider(f, "Cycle reset gap (sec)", 0.5, 5, 0.5, "Cycle gap: %.1fs",
        function() return TotemBarDB.gapSeconds end,
        function(v) TotemBarDB.gapSeconds = v end)
    place(widgets.gap, -44)

    widgets.scale = CreateSlider(f, "UI size", 0.5, 2.0, 0.05, "UI size: %.2f",
        function() return TotemBarDB.scale end,
        function(v)
            TotemBarDB.scale = v
            if TotemBarFrame then TotemBarFrame:SetScale(v) end
        end)
    place(widgets.scale, -44)

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
        widgets.guard:SetValue(TotemBar.clampValue(TotemBarDB.recallGuardSeconds, 0, 5))
        widgets.gap:SetValue(TotemBar.clampValue(TotemBarDB.gapSeconds, 0.5, 5))
        widgets.scale:SetValue(TotemBar.clampValue(TotemBarDB.scale, 0.5, 2.0))
    end)

    -- ESC closes it.
    tinsert(UISpecialFrames, "TotemBarOptionsFrame")

    f:Hide()
    return f
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
