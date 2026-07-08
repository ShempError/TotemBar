-- TotemBar - ui.lua
-- The totem bar frame: 4 element buttons plus a small custom dropdown
-- list (not UIDropDownMenu, to stay dependency-free and avoid its
-- global-name plumbing) for picking which known totem fills each
-- element's slot. WoW-API-only file; not offline-tested, only
-- syntax-checked (see tools/luatests notes in the repo).

TotemBar = TotemBar or {}

-- Defensive fallback in case DEFAULT_CHAT_FRAME is ever unset this early
-- in the loading sequence (guards against a later/leaner client build).
local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

local BUTTON_SIZE = 36
local BUTTON_GAP = 4
local MAX_DROPDOWN_ROWS = 8

-- Fallback icon for an empty / unresolved slot.
local EMPTY_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local elementButtons = {}      -- element -> button frame
local dropdownRows = {}        -- pooled dropdown row buttons (created once)
local dropdownFrame = nil      -- lazily created custom dropdown frame
local dropdownElement = nil    -- element currently shown in the dropdown

-- Forward declarations so functions defined later can be referenced by
-- closures created earlier in the file (standard Lua forward-decl idiom:
-- `local foo` then later `foo = function() ... end` / `function foo()`).
local RefreshButton
local EnsureDropdownFrame
local ShowDropdown
local CreateElementButton
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
            dropdownFrame:Hide()
        end)

        row:Hide()
        dropdownRows[i] = row
    end

    dropdownFrame = f
    return f
end

ShowDropdown = function(button, element)
    local f = EnsureDropdownFrame()
    dropdownElement = element

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

CreateElementButton = function(element, index)
    local name = "TotemBarButton" .. element
    local btn = CreateFrame("Button", name, TotemBarFrame)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", TotemBarFrame, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP, 0)

    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexture(GetElementIcon(element))
    btn.icon = icon

    local label = btn:CreateFontString(name .. "Label", "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("BOTTOM", btn, "TOP", 0, 2)
    label:SetText(element)
    btn.label = label

    btn:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
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
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    elementButtons[element] = btn
    return btn
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
    local width = numElements * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP
    local height = BUTTON_SIZE + BUTTON_GAP * 2 + 12

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
