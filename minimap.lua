-- TotemBar - minimap.lua
-- Hand-rolled minimap button (no LibDBIcon on 1.12). Orbits the minimap at a
-- saved angle, drag-repositions (angle persisted), left-click opens the
-- options panel, right-click toggles the bar. pfUI-safe: parent = Minimap,
-- name contains "Minimap", FrameStrata HIGH + level 9 (MEDIUM hides under
-- pfUI). /tb options is the guaranteed access path if pfUI collects/hides
-- the button. WoW-API file (parse-checked only).

TotemBar = TotemBar or {}

local button = nil

-- Repositions the button on its orbit for the given angle (degrees).
local function PlaceButton(angleDeg)
    if not button then
        return
    end
    local radius = (Minimap:GetWidth() / 2) + 5
    local x, y = TotemBar.angleToOffset(angleDeg, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function BuildMinimapButton()
    if button then
        return
    end

    local btn = CreateFrame("Button", "TotemBarMinimapButton", Minimap)
    btn:SetWidth(31)
    btn:SetHeight(31)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(9)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Nature_TremorTotem")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(53)
    border:SetHeight(53)
    -- Center the ring on the button/icon. TOPLEFT-offset anchoring was off
    -- (ring sat down-right of the icon in-game); CENTER is size-independent
    -- and keeps the ring concentric with the 20px icon.
    border:SetPoint("CENTER", btn, "CENTER", 0, 0)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn.angle = TotemBarDB.minimapAngle or 225

    -- Drag (repositions around the orbit). Drag needs the movement threshold,
    -- so a plain click still fires OnClick; the two coexist (verified 1.12
    -- pattern).
    btn:RegisterForDrag("LeftButton")
    btn.isDragging = false
    btn:SetScript("OnDragStart", function() this.isDragging = true end)
    btn:SetScript("OnDragStop", function()
        this.isDragging = false
        TotemBarDB.minimapAngle = this.angle
    end)
    btn:SetScript("OnUpdate", function()
        if not this.isDragging then
            return
        end
        local mx, my = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        mx = mx / scale
        my = my / scale
        local cx, cy = Minimap:GetCenter()
        this.angle = math.deg(math.atan2(my - cy, mx - cx))
        PlaceButton(this.angle)
    end)

    -- Clicks: left = options, right = toggle bar.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if TotemBar.ToggleBar then TotemBar.ToggleBar() end
        else
            if TotemBar.ToggleOptions then TotemBar.ToggleOptions() end
        end
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("TotemBar")
        GameTooltip:AddLine("Left-click: Options", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Toggle bar", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: reposition", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button = btn
    PlaceButton(btn.angle)
end

-- Build on ADDON_LOADED (SavedVariables are populated by then, same as the
-- bar). Guarded; never on PLAYER_ENTERING_WORLD (would re-run and leak
-- textures).
local ev = CreateFrame("Frame", "TotemBarMinimapEventFrame", UIParent)
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TotemBar" then
        BuildMinimapButton()
        ev:UnregisterEvent("ADDON_LOADED")
    end
end)
