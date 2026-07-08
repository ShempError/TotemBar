-- TotemBar - ui.lua
-- The totem bar frame: 4 element buttons plus a Totemic Recall button,
-- and a small custom dropdown list (not UIDropDownMenu, to stay
-- dependency-free and avoid its global-name plumbing) for picking
-- which known totem fills each element's slot. Each element button
-- also carries an OmniCC-style remaining-duration timer text (hybrid
-- source: pfUI libtotem's GetTotemInfo when present, else TotemBar's
-- own cast-tracking - see core/cast.lua). No per-button text labels;
-- hover the button for a tooltip naming the element/totem. WoW-API-only
-- file; not offline-tested, only syntax-checked (see tools/luatests
-- notes in the repo).

TotemBar = TotemBar or {}

-- Defensive fallback in case DEFAULT_CHAT_FRAME is ever unset this early
-- in the loading sequence (guards against a later/leaner client build).
local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local MAX_DROPDOWN_ROWS = 8

-- Timer-text OnUpdate throttle: refresh at most this often (seconds),
-- not every frame, to keep the shared/guild-addon perf budget sane.
local TIMER_UPDATE_INTERVAL = 0.2
local timerElapsed = 0

-- Fallback icon for an empty / unresolved slot.
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Totemic Recall: exact icon is verified at button-creation time via a
-- spellbook scan (GetSpellTexture); this is only the last-resort
-- fallback if that scan fails to resolve a texture.
local RECALL_SPELL_NAME = "Totemic Recall"
local RECALL_ICON_FALLBACK = "Interface\\Icons\\Spell_Nature_AstralRecal"

local DROPDOWN_HIDE_INTERVAL = 0.1  -- throttle for the mouse-leave hide check

local elementButtons = {}         -- element -> button frame
local dropdownRows = {}           -- pooled dropdown row buttons (created once)
local dropdownFrame = nil         -- lazily created custom dropdown frame
local dropdownElement = nil       -- element currently shown in the dropdown
local dropdownOwnerButton = nil   -- button that opened the dropdown
local dropdownElapsed = 0         -- throttle accumulator for the hide check

-- Hover flyout: hovering an element button pops a column of icon
-- buttons UPWARD for the OTHER known totems of that element (all known
-- for the element minus the currently-chosen default). Clicking one
-- casts it ONCE without changing the slot's default. Shares one frame +
-- a pool of icon buttons, mirroring the dropdown pattern above.
local MAX_FLYOUT_ICONS = 6         -- most totems any single element has
local FLYOUT_PAD = 4               -- inner padding inside the flyout frame
local FLYOUT_GAP = 2               -- gap between element button top and flyout bottom
local FLYOUT_HIDE_INTERVAL = 0.1   -- throttle for the mouse-leave hide check

local flyoutIcons = {}         -- pooled flyout icon buttons (created once)
local flyoutFrame = nil        -- lazily created shared flyout frame
local flyoutElement = nil      -- element currently shown in the flyout
local flyoutOwnerButton = nil  -- element button the flyout is anchored to
local flyoutElapsed = 0        -- throttle accumulator for the hide check

-- Forward declarations so functions defined later can be referenced by
-- closures created earlier in the file (standard Lua forward-decl idiom:
-- `local foo` then later `foo = function() ... end` / `function foo()`).
local RefreshButton
local EnsureDropdownFrame
local ShowDropdown
local HideDropdown
local OnDropdownUpdate
local EnsureFlyoutFrame
local ShowFlyout
local HideFlyout
local OnFlyoutUpdate
local CreateElementButton
local CreateRecallButton
local UpdateTimerDisplays
local OnBarUpdate
local OnDragStart
local OnDragStop

-- Finds the spellbook index of a known spell by exact name, or nil.
local function FindSpellIndexByName(name)
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

-- Resolves the icon texture path for whatever totem is currently chosen
-- for `element`, or the empty-slot placeholder.
local function GetElementIcon(element)
    local db = TotemBarDB
    local name = db and db.chosen and db.chosen[element]
    if not name then
        return EMPTY_ICON
    end
    local idx = FindSpellIndexByName(name)
    if not idx then
        return EMPTY_ICON
    end
    local texture = GetSpellTexture(idx, BOOKTYPE_SPELL)
    return texture or EMPTY_ICON
end

-- Resolves the Totemic Recall icon by scanning the spellbook for the
-- real spell (so it matches whatever texture TWoW actually ships),
-- falling back to a hardcoded texture if the scan can't find it.
local function GetRecallIcon()
    local idx = FindSpellIndexByName(RECALL_SPELL_NAME)
    if idx then
        local texture = GetSpellTexture(idx, BOOKTYPE_SPELL)
        if texture then
            return texture
        end
    end
    return RECALL_ICON_FALLBACK
end

RefreshButton = function(element)
    local btn = elementButtons[element]
    if not btn then
        return
    end
    btn.icon:SetTexture(GetElementIcon(element))
end

EnsureDropdownFrame = function()
    if dropdownFrame then
        return dropdownFrame
    end

    local f = CreateFrame("Frame", "TotemBarDropdown", UIParent)
    f:SetWidth(160)
    f:SetHeight(10)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 1)
    f:EnableMouse(true)         -- so padding between rows still counts as "over the dropdown"
    f:SetClampedToScreen(true)
    f:Hide()

    for i = 1, MAX_DROPDOWN_ROWS do
        local row = CreateFrame("Button", "TotemBarDropdownRow" .. i, f)
        row:SetWidth(150)
        row:SetHeight(16)
        row:SetPoint("TOP", f, "TOP", 0, -6 - (i - 1) * 16)

        local text = row:CreateFontString("TotemBarDropdownRow" .. i .. "Text", "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", row, "LEFT", 4, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        local hi = row:CreateTexture(nil, "HIGHLIGHT")
        hi:SetAllPoints(row)
        hi:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        hi:SetBlendMode("ADD")

        row:SetScript("OnClick", function()
            if dropdownElement then
                if row.totemName == false then
                    TotemBarDB.chosen[dropdownElement] = nil
                elseif row.totemName then
                    TotemBarDB.chosen[dropdownElement] = row.totemName
                end
                RefreshButton(dropdownElement)
            end
            HideDropdown()
        end)

        row:Hide()
        dropdownRows[i] = row
    end

    -- OnUpdate only fires while the frame is shown, so this hide-check
    -- naturally stops running once the dropdown is hidden.
    f:SetScript("OnUpdate", OnDropdownUpdate)

    dropdownFrame = f
    return f
end

ShowDropdown = function(button, element)
    local f = EnsureDropdownFrame()
    dropdownElement = element
    dropdownOwnerButton = button
    dropdownElapsed = 0

    local db = TotemBarDB
    local spellNames = TotemBar.scanSpellbook()
    local known = TotemBar.knownTotems(spellNames, element)

    local rowIndex = 1

    if db.chosen[element] then
        local row = dropdownRows[rowIndex]
        row.text:SetText("(none)")
        row.totemName = false
        row:Show()
        rowIndex = rowIndex + 1
    end

    for i = 1, table.getn(known) do
        if rowIndex <= MAX_DROPDOWN_ROWS then
            local row = dropdownRows[rowIndex]
            row.text:SetText(known[i])
            row.totemName = known[i]
            row:Show()
            rowIndex = rowIndex + 1
        end
    end

    if rowIndex == 1 then
        local row = dropdownRows[1]
        row.text:SetText("No known totems")
        row.totemName = nil
        row:Show()
        rowIndex = 2
    end

    for j = rowIndex, MAX_DROPDOWN_ROWS do
        dropdownRows[j]:Hide()
    end

    f:SetHeight(10 + (rowIndex - 1) * 16)
    f:ClearAllPoints()
    f:SetPoint("TOP", button, "BOTTOM", 0, -2)
    f:Show()
end

HideDropdown = function()
    if dropdownFrame then
        dropdownFrame:Hide()
    end
    dropdownOwnerButton = nil
end

-- Throttled mouse-leave check for the right-click dropdown: hide it once
-- the cursor is over NEITHER the dropdown NOR the button that opened it
-- (mirrors OnFlyoutUpdate). Row clicks still hide it directly. No
-- per-frame allocation - just the accumulator and two MouseIsOver checks.
OnDropdownUpdate = function()
    dropdownElapsed = dropdownElapsed + arg1
    if dropdownElapsed < DROPDOWN_HIDE_INTERVAL then
        return
    end
    dropdownElapsed = 0
    if MouseIsOver(dropdownFrame) or (dropdownOwnerButton and MouseIsOver(dropdownOwnerButton)) then
        return
    end
    HideDropdown()
end

-- Lazily builds the single shared flyout frame plus its pool of icon
-- buttons (TotemBarFlyoutIcon1..MAX_FLYOUT_ICONS), stacked bottom-up so
-- ShowFlyout can just Show the first N. DIALOG strata so it draws above
-- the bar backdrop. Same anti-bevel icon treatment as the element
-- buttons (opaque black backdrop under an inset, cropped ARTWORK icon).
EnsureFlyoutFrame = function()
    if flyoutFrame then
        return flyoutFrame
    end

    local f = CreateFrame("Frame", "TotemBarFlyout", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(BUTTON_SIZE + FLYOUT_PAD * 2)
    f:SetHeight(BUTTON_SIZE + FLYOUT_PAD * 2)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:EnableMouse(true)         -- so gaps/padding still count as "over the flyout"
    f:SetClampedToScreen(true)
    f:Hide()

    for i = 1, MAX_FLYOUT_ICONS do
        local ico = CreateFrame("Button", "TotemBarFlyoutIcon" .. i, f)
        ico:SetWidth(BUTTON_SIZE)
        ico:SetHeight(BUTTON_SIZE)
        -- Bottom-up: icon 1 just inside the bottom padding, each next
        -- one a full button+gap higher (so nearest the element button
        -- is first).
        ico:SetPoint("BOTTOM", f, "BOTTOM", 0, FLYOUT_PAD + (i - 1) * (BUTTON_SIZE + BUTTON_GAP))

        ico:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        ico:SetBackdropColor(0, 0, 0, 1)

        local icon = ico:CreateTexture("TotemBarFlyoutIcon" .. i .. "Icon", "ARTWORK")
        icon:SetPoint("TOPLEFT", ico, "TOPLEFT", 3, -3)
        icon:SetPoint("BOTTOMRIGHT", ico, "BOTTOMRIGHT", -3, 3)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ico.icon = icon

        ico:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        ico:RegisterForClicks("LeftButtonUp")

        -- Cast once for the element the flyout is currently showing.
        -- recordCast() drives THAT element's timer to the actually-cast
        -- totem, without touching the slot's chosen default.
        ico:SetScript("OnClick", function()
            if this.totemName and flyoutElement then
                CastSpellByName(this.totemName)
                TotemBar.recordCast(flyoutElement, this.totemName)
            end
        end)

        ico:SetScript("OnEnter", function()
            if this.totemName then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                GameTooltip:SetText(this.totemName)
                GameTooltip:Show()
            end
        end)
        ico:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        ico:Hide()
        flyoutIcons[i] = ico
    end

    -- OnUpdate only fires while the frame is shown, so this hide-check
    -- naturally stops running once the flyout is hidden.
    f:SetScript("OnUpdate", OnFlyoutUpdate)

    flyoutFrame = f
    return f
end

-- Populates and shows the flyout above `button` for `element`, listing
-- every known totem of that element EXCEPT the currently-chosen default.
-- Shows nothing if there are no "others".
ShowFlyout = function(button, element)
    local f = EnsureFlyoutFrame()

    local db = TotemBarDB
    local spellNames = TotemBar.scanSpellbook()
    local known = TotemBar.knownTotems(spellNames, element)
    local chosen = db and db.chosen and db.chosen[element]

    local count = 0
    for i = 1, table.getn(known) do
        local totemName = known[i]
        if totemName ~= chosen and count < MAX_FLYOUT_ICONS then
            count = count + 1
            local ico = flyoutIcons[count]
            ico.totemName = totemName
            local idx = FindSpellIndexByName(totemName)
            local texture = idx and GetSpellTexture(idx, BOOKTYPE_SPELL)
            ico.icon:SetTexture(texture or EMPTY_ICON)
            ico:Show()
        end
    end

    for j = count + 1, MAX_FLYOUT_ICONS do
        flyoutIcons[j]:Hide()
        flyoutIcons[j].totemName = nil
    end

    if count == 0 then
        -- No other known totems for this element; don't show an empty box.
        flyoutElement = nil
        flyoutOwnerButton = nil
        f:Hide()
        return
    end

    flyoutElement = element
    flyoutOwnerButton = button
    flyoutElapsed = 0

    f:SetHeight(count * (BUTTON_SIZE + BUTTON_GAP) - BUTTON_GAP + FLYOUT_PAD * 2)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", button, "TOP", 0, FLYOUT_GAP)
    f:Show()
end

HideFlyout = function()
    if flyoutFrame then
        flyoutFrame:Hide()
    end
    flyoutElement = nil
    flyoutOwnerButton = nil
end

-- Throttled mouse-leave check: hide the flyout once the cursor is over
-- NEITHER the owning element button NOR the flyout itself. This keeps
-- it open while the mouse travels from the button up onto the flyout.
-- No per-frame allocation - just the accumulator and two MouseIsOver
-- geometry checks, gated to run ~every FLYOUT_HIDE_INTERVAL seconds.
OnFlyoutUpdate = function()
    flyoutElapsed = flyoutElapsed + arg1
    if flyoutElapsed < FLYOUT_HIDE_INTERVAL then
        return
    end
    flyoutElapsed = 0
    if flyoutOwnerButton and (MouseIsOver(flyoutFrame) or MouseIsOver(flyoutOwnerButton)) then
        return
    end
    HideFlyout()
end

CreateElementButton = function(element, index)
    local name = "TotemBarButton" .. element
    local btn = CreateFrame("Button", name, TotemBarFrame)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", TotemBarFrame, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP, 0)

    -- Opaque dark fill + thin border behind the icon. Replaces the old
    -- UI-Quickslot2 normal texture, whose beveled square bled THROUGH
    -- transparent regions of icon art (rendering a little empty box over
    -- the icon). A solid black backdrop under the ARTWORK-layer icon
    -- makes those transparent regions read as flat dark instead.
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0, 0, 0, 1)   -- opaque black fill behind the icon

    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    -- Inset so the icon sits just inside the backdrop border, letting
    -- the opaque black fill show through any transparent icon regions.
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture(GetElementIcon(element))
    -- Crop the icon's built-in ~8% border (standard action-button
    -- treatment). Without this, icons whose art carries a visible edge
    -- render a little empty frame over the button. SetTexCoord persists
    -- across later SetTexture calls (RefreshButton), so set it once here.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- OmniCC-style remaining-duration text, centered on the icon.
    -- Hidden by default; UpdateTimerDisplays() shows/updates it.
    local timerText = btn:CreateFontString(name .. "Timer", "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    timerText:SetPoint("CENTER", icon, "CENTER", 0, 1)
    timerText:SetJustifyH("CENTER")
    timerText:SetText("")
    timerText:Hide()
    btn.timerText = timerText
    btn.timerVisible = false       -- cached shown-state, avoid redundant Show/Hide
    btn.timerLastText = nil        -- cached last string, avoid redundant SetText
    btn.timerLastLow = nil         -- cached last <=5s tint state, avoid redundant SetTextColor

    -- No normal texture: UI-Quickslot2's bevel bleeds through
    -- transparent icon art (see backdrop above). Pushed/highlight only
    -- appear on click/hover, so they don't bleed.
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.element = element

    btn:SetScript("OnClick", function()
        local clickedElement = this.element
        if arg1 == "RightButton" then
            ShowDropdown(this, clickedElement)
        else
            local db = TotemBarDB
            local totemName = db and db.chosen and db.chosen[clickedElement]
            if totemName then
                CastSpellByName(totemName)
                TotemBar.recordCast(clickedElement, totemName)
            else
                ChatOut:AddMessage("TotemBar: no totem chosen for " .. clickedElement .. " (right-click to choose)")
            end
        end
    end)

    btn:SetScript("OnEnter", function()
        local db = TotemBarDB
        local totemName = db and db.chosen and db.chosen[this.element]
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        if totemName then
            GameTooltip:SetText(totemName)
        else
            GameTooltip:SetText(this.element .. " (empty - right-click to choose)")
        end
        GameTooltip:Show()
        -- Pop the "cast one of the others" flyout above this button.
        -- The flyout hides itself via its own throttled mouse-leave
        -- check (OnFlyoutUpdate), so no OnLeave handling is needed here.
        ShowFlyout(this, this.element)
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    elementButtons[element] = btn
    return btn
end

-- Totemic Recall: instant-cast button, no dropdown, no per-element
-- timer (recall has no duration of its own - it just clears totems).
CreateRecallButton = function(index)
    local name = "TotemBarButtonRecall"
    local btn = CreateFrame("Button", name, TotemBarFrame)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", TotemBarFrame, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP, 0)

    -- Opaque dark fill + thin border (same as element buttons); see the
    -- comment in CreateElementButton for why this replaces UI-Quickslot2.
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0, 0, 0, 1)   -- opaque black fill behind the icon

    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture(GetRecallIcon())
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- No normal texture (UI-Quickslot2 bevel bleeds through transparent
    -- icon art). Pushed/highlight only show on click/hover, no bleed.
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:RegisterForClicks("LeftButtonUp")

    btn:SetScript("OnClick", function()
        CastSpellByName(RECALL_SPELL_NAME)
        -- Totemic Recall drops every active totem at once; clear our
        -- own-tracking timers so the icons' countdowns disappear too
        -- (GetTotemInfo, if present, will also reflect this).
        TotemBar.clearActiveTotems()
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(RECALL_SPELL_NAME)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

-- Refreshes every element button's remaining-duration timer text.
-- HYBRID source: prefers pfUI libtotem's GetTotemInfo(slot) when
-- present and reporting the slot active (also catches totems cast
-- outside TotemBar); otherwise falls back to TotemBar's own
-- cast-tracking (TotemBar.activeTotems). Called at most ~5x/sec by
-- OnBarUpdate below, never per-frame.
UpdateTimerDisplays = function()
    local now = GetTime()
    local hasGTI = (type(GetTotemInfo) == "function")
    local elements = TotemBar.TOTEM_ELEMENTS
    local activeTotems = TotemBar.activeTotems

    for i = 1, table.getn(elements) do
        local element = elements[i]
        local btn = elementButtons[element]
        if btn then
            -- Own-tracking: compute remaining, evicting the record the
            -- moment it expires (per-element table, no growth).
            local ownRecord = activeTotems[element]
            local ownRemaining = nil
            if ownRecord then
                ownRemaining = TotemBar.remaining(ownRecord.start, ownRecord.duration, now)
                if not ownRemaining or ownRemaining <= 0 then
                    activeTotems[element] = nil
                    ownRemaining = nil
                end
            end

            -- pfUI libtotem, when present: Fire=1, Earth=2, Water=3,
            -- Air=4 - i.e. exactly TotemBar.TOTEM_ELEMENTS' own order.
            local gtiActive, gtiRemaining
            if hasGTI then
                local active, _, start, duration = GetTotemInfo(i)
                gtiActive = active
                if start and duration then
                    gtiRemaining = TotemBar.remaining(start, duration, now)
                end
            end

            local remainingVal = TotemBar.resolveRemaining(gtiActive, gtiRemaining, ownRemaining)

            if remainingVal then
                if not btn.timerVisible then
                    btn.timerText:Show()
                    btn.timerVisible = true
                end
                local text = TotemBar.formatRemaining(remainingVal)
                if text ~= btn.timerLastText then
                    btn.timerText:SetText(text)
                    btn.timerLastText = text
                end
                local isLow = remainingVal <= 5
                if isLow ~= btn.timerLastLow then
                    if isLow then
                        btn.timerText:SetTextColor(1, 0.15, 0.15, 1)
                    else
                        btn.timerText:SetTextColor(1, 1, 1, 1)
                    end
                    btn.timerLastLow = isLow
                end
            elseif btn.timerVisible then
                btn.timerText:Hide()
                btn.timerVisible = false
                btn.timerLastText = nil
                btn.timerLastLow = nil
            end
        end
    end
end

OnBarUpdate = function()
    timerElapsed = timerElapsed + arg1
    if timerElapsed < TIMER_UPDATE_INTERVAL then
        return
    end
    timerElapsed = 0
    UpdateTimerDisplays()
end

OnDragStart = function()
    if not TotemBarDB.locked then
        this:StartMoving()
    end
end

OnDragStop = function()
    this:StopMovingOrSizing()
    local point, _, relPoint, x, y = this:GetPoint()
    TotemBarDB.point = point
    TotemBarDB.relPoint = relPoint
    TotemBarDB.x = x
    TotemBarDB.y = y
end

function TotemBar.BuildUI()
    if TotemBarFrame then
        return
    end

    local numElements = table.getn(TotemBar.TOTEM_ELEMENTS)
    local totalButtons = numElements + 1 -- + Totemic Recall, to the right of Air
    -- No per-button labels anymore (hover tooltip names the element/
    -- totem instead), so the bar is just the button row plus a
    -- symmetric BUTTON_GAP margin on every side.
    local width = totalButtons * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP
    local height = BUTTON_SIZE + BUTTON_GAP * 2

    local frame = CreateFrame("Frame", "TotemBarFrame", UIParent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.5)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)

    frame:ClearAllPoints()
    frame:SetPoint(TotemBarDB.point, UIParent, TotemBarDB.relPoint, TotemBarDB.x, TotemBarDB.y)

    for i = 1, numElements do
        CreateElementButton(TotemBar.TOTEM_ELEMENTS[i], i)
    end
    CreateRecallButton(totalButtons)

    frame:SetScript("OnUpdate", OnBarUpdate)

    frame:Show()
end

-- "/tb scan" dev-aid: one-shot print of every spellbook entry that looks
-- like a totem, so the static element map in core/totemdata.lua can be
-- checked against the live TurtleWoW client. No file I/O, no telemetry.
function TotemBar.PrintScan()
    local names = TotemBar.scanSpellbook()
    local count = 0
    ChatOut:AddMessage("TotemBar: scanning spellbook for totems...")
    for i = 1, table.getn(names) do
        if string.find(names[i], "Totem", 1, true) then
            ChatOut:AddMessage("  " .. names[i])
            count = count + 1
        end
    end
    ChatOut:AddMessage("TotemBar: " .. count .. " totem spell(s) found.")
end

local function HandleSlashCommand(msg)
    local cmd = string.lower(msg or "")
    if cmd == "" then
        if TotemBarFrame:IsShown() then
            TotemBarFrame:Hide()
        else
            TotemBarFrame:Show()
        end
    elseif cmd == "lock" then
        TotemBarDB.locked = not TotemBarDB.locked
        if TotemBarDB.locked then
            ChatOut:AddMessage("TotemBar: bar locked.")
        else
            ChatOut:AddMessage("TotemBar: bar unlocked (drag to move).")
        end
    elseif cmd == "scan" then
        TotemBar.PrintScan()
    else
        ChatOut:AddMessage("TotemBar: unknown command '" .. msg .. "'. Usage: /tb, /tb lock, /tb scan")
    end
end

local eventFrame = CreateFrame("Frame", "TotemBarEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TotemBar" then
        TotemBar.ensureDefaults()
        TotemBar.BuildUI()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    end
end)

SLASH_TOTEMBAR1 = "/tb"
SlashCmdList = SlashCmdList or {}
SlashCmdList["TOTEMBAR"] = HandleSlashCommand
