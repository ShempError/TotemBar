-- TotemBar - ui.lua
-- The totem bar frame: 4 element buttons plus a Totemic Recall button.
-- Left-click an element button to cast its chosen totem; right-click
-- clears the slot. Hovering an element button pops an upward flyout of
-- the element's other known totems: left-click one to cast it once,
-- right-click one to set it as the slot's new default. Each element
-- button also carries an OmniCC-style remaining-duration timer text (hybrid
-- source: pfUI libtotem's GetTotemInfo when present, else TotemBar's
-- own cast-tracking - see core/cast.lua). No per-button text labels;
-- hover the button for a tooltip naming the element/totem. Each element
-- button also carries a native action-button-style radial cooldown
-- swipe (CooldownFrameTemplate) reflecting the chosen totem's spellbook
-- cooldown, IN ADDITION to the duration timer text. The Recall button's
-- icon pulses whenever any element totem is currently out of range.
-- WoW-API-only file; not offline-tested, only syntax-checked (see
-- tools/luatests notes in the repo).

TotemBar = TotemBar or {}

-- Defensive fallback in case DEFAULT_CHAT_FRAME is ever unset this early
-- in the loading sequence (guards against a later/leaner client build).
local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

local BUTTON_SIZE = 36
local BUTTON_GAP = 4

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

local elementButtons = {}         -- element -> button frame
local recallButton = nil          -- Totemic Recall button frame (for the auto-recall indicator refresh)

-- True when ANY element's totem is currently out-of-range (the
-- buff-presence red tint, see UpdateTimerDisplays). Recomputed once per
-- UpdateTimerDisplays pass; drives the Recall button's icon pulse
-- (OnRecallUpdate below) as a "go recall + redeploy" visual prompt.
local anyOutOfRange = false

-- Hover flyout: hovering an element button pops a column of icon
-- buttons UPWARD for the OTHER known totems of that element (all known
-- for the element minus the currently-chosen default). Left-click one to
-- cast it ONCE without changing the slot's default; right-click one to
-- make it the slot's new default. Shares one frame + a pool of icon
-- buttons.
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
local RefreshCooldown
local EnsureFlyoutFrame
local ShowFlyout
local RefreshFlyoutCooldowns
local HideFlyout
local OnFlyoutUpdate
local CreateElementButton
local CreateRecallButton
local CreateDropSetButton
local RefreshRecallIndicator
local OnRecallUpdate
local UpdateTimerDisplays
local OnBarUpdate
local OnDragStart
local OnDragStop
local EnsureAssignFrame
local assignFrame        -- lazily created pending-suggestion panel

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

-- Resolves (iconTexture, known) for an arbitrary totem name: the spellbook
-- texture when the player knows it, else the empty/question-mark icon and
-- known=false (the pending panel greys unknown totems).
local function ResolveTotemIcon(name)
    if not name then
        return EMPTY_ICON, false
    end
    local idx = FindSpellIndexByName(name)
    if not idx then
        return EMPTY_ICON, false
    end
    local texture = GetSpellTexture(idx, BOOKTYPE_SPELL)
    return texture or EMPTY_ICON, true
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
    RefreshCooldown(element)
end

-- Refreshes element `element`'s native cooldown swipe (the same radial
-- CooldownFrameTemplate widget standard action buttons use) to match its
-- currently-chosen totem's spellbook cooldown. Clears the swipe (start=0)
-- when the slot is empty or unresolved. Called from RefreshButton (i.e.
-- on selection changes and once at bar-build time) and from the
-- SPELL_UPDATE_COOLDOWN event handler below - NEVER from the per-tick
-- timer OnUpdate, since re-calling CooldownFrame_SetTimer every tick
-- would restart the swipe's animation instead of letting it play.
RefreshCooldown = function(element)
    local btn = elementButtons[element]
    if not btn then
        return
    end
    local db = TotemBarDB
    local totemName = db and db.chosen and db.chosen[element]
    local idx = totemName and FindSpellIndexByName(totemName)
    if not idx then
        CooldownFrame_SetTimer(btn.cd, 0, 0, 0)
        return
    end
    local start, duration, enable = GetSpellCooldown(idx, BOOKTYPE_SPELL)
    CooldownFrame_SetTimer(btn.cd, start, duration, enable)
end

-- Glue for core/assign.lua's pending-assignment logic: it stays WoW-API-
-- light and reaches the spellbook / bar refresh through these slots.
-- isTotemKnown resolves a totem name against the live spellbook; RefreshAll
-- re-skins every element button (used after a pending assignment is applied).
TotemBar.isTotemKnown = function(name)
    return FindSpellIndexByName(name) ~= nil
end

TotemBar.RefreshAll = function()
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        RefreshButton(elements[i])
    end
end

-- Bind-mode key overlays: a small top-right FontString on each bindable
-- button/flyout icon, ALWAYS shown (action-bar-hotkey style) whenever a key
-- is bound, hidden only when nothing is bound. Independent of bind mode.
-- Declared here, BEFORE EnsureFlyoutFrame/CreateElementButton/
-- CreateRecallButton/CreateDropSetButton (all of which call
-- registerBindOverlay from their function bodies): Lua resolves a `local`
-- as an upvalue only for code appearing lexically after its declaration, so
-- this block must sit above every factory that references it, not just
-- above CreateElementButton (EnsureFlyoutFrame is defined earlier in the
-- file than the element/recall/dropset button factories).
local bindOverlayTargets = {}   -- { frame = button, action = fn()->command }

local function ensureBindOverlay(frame)
    if frame.bindKeyText then
        return frame.bindKeyText
    end
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    fs:SetTextColor(1, 0.9, 0.2)
    fs:Hide()
    frame.bindKeyText = fs
    return fs
end

-- action is a function returning the binding command for this frame right now
-- (flyout icons change totem), or nil.
local function registerBindOverlay(frame, actionFn)
    ensureBindOverlay(frame)
    tinsert(bindOverlayTargets, { frame = frame, action = actionFn })
end

TotemBar.refreshBindOverlays = function()
    for i = 1, table.getn(bindOverlayTargets) do
        local t = bindOverlayTargets[i]
        local fs = t.frame.bindKeyText
        local cmd = t.action()
        local key = cmd and GetBindingKey(cmd) or nil
        if key then
            fs:SetText(TotemBar.shortenKey(key))
            fs:Show()
        else
            fs:Hide()
        end
    end
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

    -- Parent to the bar (not UIParent) so the flyout inherits the bar's
    -- scale (UI-size slider) and hides with it. Still DIALOG strata below,
    -- so it draws above the bar backdrop regardless of parent.
    local f = CreateFrame("Frame", "TotemBarFlyout", TotemBarFrame)
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

        -- Native cooldown swipe over the flyout icon, so the player can
        -- see which alternative totems are on cooldown while choosing.
        -- Same "Model" (NOT "Cooldown") frame-type caveat as the element
        -- buttons: vanilla 1.12 has no dedicated Cooldown widget type -
        -- CooldownFrameTemplate is a Model template here (see the element
        -- button's cd note above). Driven once at flyout-open by
        -- ShowFlyout (the widget animates itself from start+duration), so
        -- no per-frame refresh for this transient popup.
        local cd = CreateFrame("Model", "TotemBarFlyoutIcon" .. i .. "Cooldown", ico, "CooldownFrameTemplate")
        cd:SetAllPoints(ico.icon)
        cd:SetFrameLevel(ico:GetFrameLevel())
        ico.cd = cd

        ico:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        ico:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        -- Left-click: cast once for the element the flyout is currently
        -- showing. recordCast() drives THAT element's timer to the
        -- actually-cast totem, without touching the slot's chosen
        -- default. Right-click: make this totem the slot's new chosen
        -- default and re-populate the flyout in place (so the
        -- newly-chosen totem drops out of the "others" list and the
        -- previously-chosen one appears), keeping the flyout open.
        ico:SetScript("OnClick", function()
            if not (this.totemName and flyoutElement) then
                return
            end
            if arg1 == "RightButton" then
                local element = flyoutElement
                local owner = flyoutOwnerButton
                TotemBarDB.chosen[element] = this.totemName
                RefreshButton(element)
                if owner then
                    ShowFlyout(owner, element)
                end
            else
                CastSpellByName(this.totemName)
                TotemBar.recordCast(flyoutElement, this.totemName)
                -- Immediate cooldown feedback: don't wait for
                -- SPELL_UPDATE_COOLDOWN. Refreshes the bar button's swipe
                -- (in case the cast totem is also this element's chosen
                -- default) and the flyout icon's own swipe.
                RefreshCooldown(flyoutElement)
                RefreshFlyoutCooldowns()
            end
        end)

        ico:SetScript("OnEnter", function()
            if this.totemName then
                GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                local idx = FindSpellIndexByName(this.totemName)
                if idx then
                    GameTooltip:SetSpell(idx, BOOKTYPE_SPELL)
                else
                    GameTooltip:SetText(this.totemName)
                end
                GameTooltip:AddLine("Left-click: cast  /  Right-click: set default", 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        ico:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        ico:Hide()
        registerBindOverlay(ico, function()
            if ico.totemName then
                return "TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(ico.totemName)
            end
            return nil
        end)
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
            -- Drive the swipe once here at flyout-open so the player can
            -- see which alternative totems are on cooldown; the widget
            -- animates itself from start+duration, no per-tick refresh.
            if idx then
                local start, duration, enable = GetSpellCooldown(idx, BOOKTYPE_SPELL)
                CooldownFrame_SetTimer(ico.cd, start, duration, enable)
            else
                CooldownFrame_SetTimer(ico.cd, 0, 0, 0)
            end
            ico:Show()
        end
    end

    for j = count + 1, MAX_FLYOUT_ICONS do
        flyoutIcons[j]:Hide()
        flyoutIcons[j].totemName = nil
        -- Clear the swipe on unused pool icons so a stale cooldown from a
        -- previous open doesn't linger if this slot is reused later.
        CooldownFrame_SetTimer(flyoutIcons[j].cd, 0, 0, 0)
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
    -- Freshly-populated flyout icons need their overlays re-driven right
    -- away (rather than waiting for the next UPDATE_BINDINGS/toggle) so
    -- keys show immediately while bind mode is already on.
    if TotemBar.refreshBindOverlays then
        TotemBar.refreshBindOverlays()
    end
end

-- Re-drives the cooldown swipe on every CURRENTLY-SHOWN pooled flyout
-- icon, re-resolving each one's spellbook index fresh (so a just-cast
-- totem's swipe reflects the cooldown that cast just started). No-op if
-- the flyout isn't open. Doesn't touch icon texture/totemName/layout -
-- only the swipe - so it's safe to call from anywhere without disturbing
-- ShowFlyout's own population pass (which sets the initial swipe state
-- itself, including clearing unused pool icons; left as-is here).
RefreshFlyoutCooldowns = function()
    if not (flyoutFrame and flyoutFrame:IsShown()) then
        return
    end
    for i = 1, MAX_FLYOUT_ICONS do
        local ico = flyoutIcons[i]
        if ico:IsShown() and ico.totemName then
            local idx = FindSpellIndexByName(ico.totemName)
            if idx then
                local start, duration, enable = GetSpellCooldown(idx, BOOKTYPE_SPELL)
                CooldownFrame_SetTimer(ico.cd, start, duration, enable)
            else
                CooldownFrame_SetTimer(ico.cd, 0, 0, 0)
            end
        end
    end
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

    -- Native action-button-style radial cooldown swipe (the same
    -- CooldownFrameTemplate widget the default action bars use),
    -- covering the icon area. This is IN ADDITION to the OmniCC-style
    -- duration timer text below; RefreshCooldown() drives it from
    -- events, see there for why it's not driven off the per-tick timer.
    --
    -- Frame type is "Model", NOT "Cooldown": vanilla 1.12 has no
    -- dedicated Cooldown widget type (that was added in TBC/2.0) -
    -- CooldownFrameTemplate is a Model-type template in 1.12 FrameXML
    -- that renders Interface\Cooldown\UI-Cooldown-Indicator.mdx (same
    -- approach pfUI's own libtotem/action bars use). CreateFrame with
    -- type "Cooldown" would error on this client.
    local cd = CreateFrame("Model", name .. "Cooldown", btn, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    -- Match the button's own frame level instead of the default child
    -- bump (parent level + 1): WoW's cross-frame draw order is primarily
    -- (strata, level) - at the default +1 level the ENTIRE swipe frame
    -- would draw above ALL of btn's own regions regardless of draw
    -- layer, including the OVERLAY timer text below. At the SAME level,
    -- ordering falls back to per-region draw layer, letting the OVERLAY
    -- timer text render on top of the swipe as intended. Still flagged
    -- for an in-game visual check (see file header note).
    cd:SetFrameLevel(btn:GetFrameLevel())
    btn.cd = cd

    -- OmniCC-style remaining-duration text, anchored BELOW the button
    -- (centered under the icon) so it doesn't overlap the native
    -- cooldown swipe (btn.cd) rendered on top of the icon. Parented to
    -- btn (a Button, like the element buttons themselves), not to the
    -- bar's backdrop Frame - plain 1.12 Frames don't clip child regions
    -- (no SetClipsChildren in this client), so text hanging below the
    -- bar's backdrop still renders fully; flagged for an in-game visual
    -- check regardless (see file header note). Hidden by default;
    -- UpdateTimerDisplays() shows/updates it.
    local timerText = btn:CreateFontString(name .. "Timer", "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    timerText:SetPoint("TOP", btn, "BOTTOM", 0, -1)
    timerText:SetJustifyH("CENTER")
    timerText:SetText("")
    timerText:Hide()
    btn.timerText = timerText
    btn.timerVisible = false       -- cached shown-state, avoid redundant Show/Hide
    btn.timerLastText = nil        -- cached last string, avoid redundant SetText
    btn.timerLastLow = nil         -- cached last <=5s tint state, avoid redundant SetTextColor
    btn.tintRed = false            -- cached out-of-range tint state, avoid redundant SetVertexColor

    -- No normal texture: UI-Quickslot2's bevel bleeds through
    -- transparent icon art (see backdrop above). Pushed/highlight only
    -- appear on click/hover, so they don't bleed.
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.element = element

    -- Left-click casts the slot's chosen totem. Right-click clears the
    -- slot (sets no default); picking a new default happens via the
    -- hover flyout's right-click instead (see EnsureFlyoutFrame above).
    btn:SetScript("OnClick", function()
        local clickedElement = this.element
        if arg1 == "RightButton" then
            TotemBarDB.chosen[clickedElement] = nil
            RefreshButton(clickedElement)
        else
            local db = TotemBarDB
            local totemName = db and db.chosen and db.chosen[clickedElement]
            if totemName then
                CastSpellByName(totemName)
                TotemBar.recordCast(clickedElement, totemName)
            else
                ChatOut:AddMessage("TotemBar: no totem chosen for " .. clickedElement .. " (hover for known totems, right-click one to set it as default)")
            end
        end
    end)

    btn:SetScript("OnEnter", function()
        local db = TotemBarDB
        local totemName = db and db.chosen and db.chosen[this.element]
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        if totemName then
            local idx = FindSpellIndexByName(totemName)
            if idx then
                GameTooltip:SetSpell(idx, BOOKTYPE_SPELL)
            else
                GameTooltip:SetText(totemName)
            end
            GameTooltip:AddLine("Left-click: cast  /  Right-click: clear", 1, 1, 1)
        else
            GameTooltip:SetText(this.element .. " (empty)")
            GameTooltip:AddLine("Hover for known totems, right-click one to set default", 1, 1, 1)
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
    registerBindOverlay(btn, function() return "TOTEMBAR_CAST_" .. string.upper(element) end)
    return btn
end

-- Refreshes the Recall button's small "A" auto-recall indicator to
-- match TotemBarDB.autoRecall: shown (greenish) when on, hidden when
-- off. Called once at button creation and again after every right-click
-- toggle (see CreateRecallButton below).
RefreshRecallIndicator = function()
    if not recallButton or not recallButton.autoIndicator then
        return
    end
    if TotemBarDB and TotemBarDB.autoRecall then
        recallButton.autoIndicator:SetTextColor(0.3, 1, 0.3)
        recallButton.autoIndicator:Show()
    else
        recallButton.autoIndicator:Hide()
    end
end

-- Public alias so options.lua can refresh the "A" auto-recall indicator
-- after the auto-recall checkbox is toggled.
TotemBar.RefreshRecallIndicator = RefreshRecallIndicator

-- Pulses the Recall button's icon alpha while anyOutOfRange is true (set
-- by UpdateTimerDisplays) - a "go recall + redeploy" visual prompt.
-- Time-based (GetTime()), so the pulse stays smooth regardless of frame
-- rate; no table/string allocation, just float math + SetAlpha. Once
-- anyOutOfRange goes false, resets to full alpha exactly once (cached
-- via iconPulsing) instead of calling SetAlpha every single frame.
OnRecallUpdate = function()
    if anyOutOfRange then
        this.icon:SetAlpha(0.35 + 0.65 * math.abs(math.sin(GetTime() * 3)))
        this.iconPulsing = true
    elseif this.iconPulsing then
        this.icon:SetAlpha(1)
        this.iconPulsing = false
    end
end

-- Totemic Recall: left-click casts it immediately (no dropdown, no
-- per-element timer - recall has no duration of its own, it just clears
-- totems). Right-click instead toggles TotemBarDB.autoRecall, the flag
-- that decides whether TotemBar.recallAndCastAll() (the Totems macro's
-- entry point, core/cast.lua) prepends a recall before redeploying. A
-- small "A" FontString overlay reflects the current flag state.
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
    btn.iconPulsing = false   -- cached: whether the icon's alpha is currently != 1 (avoids redundant SetAlpha calls once the pulse stops)

    -- Auto-recall indicator: small "A" in the icon's top-left corner.
    -- RefreshRecallIndicator() (called below, and after every toggle)
    -- shows/hides and colors it based on TotemBarDB.autoRecall.
    local autoIndicator = btn:CreateFontString(name .. "Auto", "OVERLAY")
    autoIndicator:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    autoIndicator:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    autoIndicator:SetJustifyH("LEFT")
    autoIndicator:SetText("A")
    autoIndicator:Hide()
    btn.autoIndicator = autoIndicator

    -- No normal texture (UI-Quickslot2 bevel bleeds through transparent
    -- icon art). Pushed/highlight only show on click/hover, no bleed.
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- "Go recall + redeploy" visual prompt: pulses the icon's alpha
    -- while anyOutOfRange is true (set by UpdateTimerDisplays). Only
    -- touches btn.icon's alpha, never btn.autoIndicator, so the "A"
    -- auto-recall flag text stays steady/visible throughout.
    btn:SetScript("OnUpdate", OnRecallUpdate)

    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            TotemBarDB.autoRecall = not TotemBarDB.autoRecall
            if TotemBarDB.autoRecall then
                ChatOut:AddMessage("TotemBar: auto-recall before setting ON")
            else
                ChatOut:AddMessage("TotemBar: auto-recall before setting OFF")
            end
            RefreshRecallIndicator()
        elseif TotemBar.anyTotemOut and not TotemBar.anyTotemOut() then
            -- Nothing out: don't waste Totemic Recall's 6s cooldown on a no-op
            -- cast (otherwise a set placed right after can't be recalled for 6s).
            ChatOut:AddMessage("TotemBar: no totems out - not recalling (saves the 6s cooldown).")
        else
            -- Snapshot for the refund learner runs AFTER the cast: activeTotems
            -- is still populated here (clearActiveTotems runs last).
            CastSpellByName(RECALL_SPELL_NAME)
            if TotemBar.snapshotRecallCost then TotemBar.snapshotRecallCost() end
            -- Totemic Recall drops every active totem at once; clear our
            -- own-tracking timers so the icons' countdowns disappear too
            -- (GetTotemInfo, if present, will also reflect this).
            TotemBar.clearActiveTotems()
        end
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText(RECALL_SPELL_NAME)
        GameTooltip:AddLine("Left-click: recall now", 1, 1, 1)
        local state = "OFF"
        if TotemBarDB and TotemBarDB.autoRecall then
            state = "ON"
        end
        GameTooltip:AddLine("Auto Recall Toggle (right-click): " .. state, 1, 1, 1)
        local activeCost = TotemBar.sumActiveCost(TotemBar.activeTotems, TotemBar.TOTEM_ELEMENTS, GetTime(), TotemBar.getTotemManaCost, TotemBar.remaining)
        local pct = (TotemBarDB and TotemBarDB.recallRefundPct) or 0.25
        local refund = TotemBar.refundAmount(pct, activeCost)
        if refund > 0 then
            GameTooltip:AddLine("Refund: ~" .. refund .. " mana", 0.6, 0.6, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    recallButton = btn
    RefreshRecallIndicator()
    registerBindOverlay(btn, function() return "TOTEMBAR_RECALL" end)

    return btn
end

-- The "drop set" button: one click casts all four chosen totems
-- (TotemBar.recallAndCastAll, with its 2s double-press guard). Placed after
-- the Recall button.
CreateDropSetButton = function(index)
    local name = "TotemBarButtonDropSet"
    local btn = CreateFrame("Button", name, TotemBarFrame)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", TotemBarFrame, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP, 0)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0, 0, 0, 1)

    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\Icons\\Spell_Nature_TremorTotem")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        TotemBar.recallAndCastAll()
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Drop all totems")
        GameTooltip:AddLine("Left-click: cast your whole set", 1, 1, 1)
        local cost = TotemBar.sumChosenCost(TotemBarDB.chosen, TotemBar.TOTEM_ELEMENTS, TotemBar.getTotemManaCost)
        if cost and cost > 0 then
            GameTooltip:AddLine("Mana: " .. cost, 0.6, 0.6, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    registerBindOverlay(btn, function() return "TOTEMBAR_DROPSET" end)
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
    local outOfRangeFound = false     -- OR-accumulator across this pass; written to anyOutOfRange at the end

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
                    ownRecord = nil     -- expired: not "active" for the range-tint check below either
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

            -- Out-of-range tint: buff-presence based. A totem's party
            -- buff uses the SAME icon texture as the totem spell itself
            -- (verified in-game), so "am I in range?" == "do I have a
            -- buff whose texture matches this totem's icon?".
            --
            -- ACTIVE requires an own-tracking record (ownRecord, already
            -- nil'd above once its stored duration expires) AND, when
            -- pfUI's libtotem is present, GetTotemInfo(i) agreeing the
            -- slot is still active. That second check is what keeps a
            -- totem someone/something DESTROYED (burned, killed) before
            -- its timer ran out from flashing red - once GTI says the
            -- slot is gone, we just go back to normal, not red.
            local rangeActive = (ownRecord ~= nil)
            if rangeActive and hasGTI and not gtiActive then
                rangeActive = false
            end

            if not rangeActive then
                if btn.tintRed then
                    btn.icon:SetVertexColor(1, 1, 1)
                    btn.tintRed = false
                end
            else
                local hasBuff = TotemBar.hasBuffWithIcon(ownRecord.icon)
                if hasBuff then
                    -- In range: remember it (self-learning - marks this
                    -- as a buff totem so a later drop-off can be told
                    -- apart from a totem that simply never grants one).
                    ownRecord.everHadBuff = true
                    if btn.tintRed then
                        btn.icon:SetVertexColor(1, 1, 1)
                        btn.tintRed = false
                    end
                elseif ownRecord.everHadBuff then
                    -- Had the buff earlier from this cast, don't have it
                    -- now: wandered out of the totem's range.
                    if not btn.tintRed then
                        btn.icon:SetVertexColor(1, 0.35, 0.35)
                        btn.tintRed = true
                    end
                else
                    -- Either a non-buff totem (Searing/Magma/Grounding/
                    -- etc. never grant a matching buff, so everHadBuff
                    -- stays false forever -> never red) or we simply
                    -- haven't been in range yet since this cast.
                    if btn.tintRed then
                        btn.icon:SetVertexColor(1, 1, 1)
                        btn.tintRed = false
                    end
                end
            end

            if btn.tintRed then
                outOfRangeFound = true
            end
        end
    end

    anyOutOfRange = outOfRangeFound
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

-- Lazily builds the pending-suggestion panel: a heading label, a row of up
-- to 4 element-ordered totem icons, an Accept button, and a close "X".
-- Built once, reused; event-driven show/hide (no OnUpdate, no per-frame
-- allocation). Anchored above the bar.
EnsureAssignFrame = function()
    if assignFrame then
        return assignFrame
    end

    -- Parent to the bar so the pending panel inherits the bar's scale
    -- (UI-size slider), like the flyout. Still DIALOG strata below.
    local f = CreateFrame("Frame", "TotemBarAssignFrame", TotemBarFrame)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(4 * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP + 40)
    f:SetHeight(BUTTON_SIZE + 34)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetClampedToScreen(true)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", TotemBarFrame, "TOP", 0, 6)

    local heading = f:CreateFontString("TotemBarAssignHeading", "OVERLAY")
    heading:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    heading:SetPoint("TOP", f, "TOP", 0, -6)
    heading:SetText("Assigned set")
    f.heading = heading

    f.icons = {}
    for i = 1, 4 do
        local ico = f:CreateTexture("TotemBarAssignIcon" .. i, "ARTWORK")
        ico:SetWidth(BUTTON_SIZE)
        ico:SetHeight(BUTTON_SIZE)
        ico:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
            BUTTON_GAP + (i - 1) * (BUTTON_SIZE + BUTTON_GAP), 6)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icons[i] = ico
    end

    local accept = CreateFrame("Button", "TotemBarAssignAccept", f, "UIPanelButtonTemplate")
    accept:SetWidth(28)
    accept:SetHeight(BUTTON_SIZE)
    accept:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    accept:SetText("OK")
    accept:SetScript("OnClick", function()
        TotemBar.ApplyPending()
    end)
    accept:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Apply assigned set")
        GameTooltip:AddLine("Sets these as your chosen totems (no cast).", 1, 1, 1)
        GameTooltip:Show()
    end)
    accept:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.accept = accept

    local close = CreateFrame("Button", "TotemBarAssignClose", f, "UIPanelCloseButton")
    close:SetWidth(22)
    close:SetHeight(22)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        TotemBar.ClearAssignment()
    end)
    f.close = close

    f:Hide()
    assignFrame = f
    return f
end

-- Populates and shows the panel from TotemBar.pending. Unknown totems are
-- greyed (desaturated + dimmed). Called by ReceiveAssignment via the hook.
TotemBar.ShowAssignPanel = function()
    local p = TotemBar.pending
    if not p then
        return
    end
    local f = EnsureAssignFrame()
    f.heading:SetText(p.label or "Assigned set")

    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, 4 do
        local element = elements[i]
        local name = element and p.set[element]
        local ico = f.icons[i]
        if name then
            local tex, known = ResolveTotemIcon(name)
            ico:SetTexture(tex)
            if known then
                ico:SetVertexColor(1, 1, 1)
                ico:SetAlpha(1)
            else
                ico:SetVertexColor(0.5, 0.5, 0.5)
                ico:SetAlpha(0.5)
            end
            ico:Show()
        else
            ico:Hide()
        end
    end
    f:Show()
end

-- Hides the panel (called by ClearAssignment / ApplyPending via the hook).
TotemBar.HideAssignPanel = function()
    if assignFrame then
        assignFrame:Hide()
    end
end

function TotemBar.BuildUI()
    if TotemBarFrame then
        return
    end

    local numElements = table.getn(TotemBar.TOTEM_ELEMENTS)
    local totalButtons = numElements + 2 -- + Totemic Recall + Drop Set, to the right of Air
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
    frame:SetScale(TotemBarDB.scale or 1.0)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", OnDragStart)
    frame:SetScript("OnDragStop", OnDragStop)

    frame:ClearAllPoints()
    frame:SetPoint(TotemBarDB.point, UIParent, TotemBarDB.relPoint, TotemBarDB.x, TotemBarDB.y)

    for i = 1, numElements do
        local element = TotemBar.TOTEM_ELEMENTS[i]
        CreateElementButton(element, i)
        RefreshCooldown(element)   -- initial swipe state for whatever's already chosen
    end
    CreateRecallButton(numElements + 1)
    CreateDropSetButton(numElements + 2)

    frame:SetScript("OnUpdate", OnBarUpdate)

    frame:Show()
    if TotemBarDB.hidden then
        frame:Hide()
    end

    -- Show any already-bound key labels right after login (overlays are
    -- always visible now, not gated on bind mode - see refreshBindOverlays).
    TotemBar.refreshBindOverlays()
end

-- Scales the bar while keeping its TOP-LEFT corner visually fixed, so the
-- bar grows/shrinks toward the bottom-right instead of drifting away from
-- where the player put it. SetScale scales the anchor offset too, so a naive
-- SetScale moves the frame; here we capture the top-left's ABSOLUTE screen
-- position (local coord * effective scale = pixels), apply the new scale,
-- then re-anchor TOPLEFT so those pixels are preserved. Persists the new
-- scale + anchor so the next login reproduces it.
function TotemBar.SetBarScale(newScale)
    local f = TotemBarFrame
    if not f then
        return
    end
    if not newScale or newScale <= 0 then
        newScale = 1
    end
    local before = f:GetEffectiveScale()
    local left = f:GetLeft()
    local top = f:GetTop()
    f:SetScale(newScale)
    if left and top and before then
        local leftPx = left * before
        local topPx = top * before
        local after = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftPx / after, topPx / after)
    end
    if TotemBarDB then
        TotemBarDB.scale = newScale
        local p, _, rp, x, y = f:GetPoint()
        if p then
            TotemBarDB.point = p
            TotemBarDB.relPoint = rp
            TotemBarDB.x = x
            TotemBarDB.y = y
        end
    end
end

-- Shows/hides the bar and persists the choice (TotemBarDB.hidden). Driven
-- by the options panel's "Show bar" checkbox, the minimap right-click, and
-- the bare /tb command.
function TotemBar.ToggleBar()
    if not TotemBarFrame then
        return
    end
    if TotemBarFrame:IsShown() then
        TotemBarFrame:Hide()
        TotemBarDB.hidden = true
    else
        TotemBarFrame:Show()
        TotemBarDB.hidden = false
    end
end

-- Resets the bar's saved anchor to centered defaults and re-anchors it.
-- Does NOT change scale. Driven by the options panel's "Reset position".
function TotemBar.ResetPosition()
    TotemBarDB.point = "CENTER"
    TotemBarDB.relPoint = "CENTER"
    TotemBarDB.x = 0
    TotemBarDB.y = 0
    if TotemBarFrame then
        TotemBarFrame:ClearAllPoints()
        TotemBarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- "/tb scan" dev-aid: one-shot print of every spellbook entry that looks
-- like a totem, so the static element map in core/totemdata.lua can be
-- checked against the live TurtleWoW client. Also writes the list to
-- C:\turtle\imports\totembar_scan.txt via SuperWoW's ExportFile (when
-- present) so it can be read off-client without pasting from chat.
function TotemBar.PrintScan()
    local names = TotemBar.scanSpellbook()
    local count = 0
    local dump = ""
    ChatOut:AddMessage("TotemBar: scanning spellbook for totems...")
    for i = 1, table.getn(names) do
        if string.find(names[i], "Totem", 1, true) then
            ChatOut:AddMessage("  " .. names[i])
            dump = dump .. names[i] .. "\n"
            count = count + 1
        end
    end
    ChatOut:AddMessage("TotemBar: " .. count .. " totem spell(s) found.")
    -- ExportFile appends .txt itself; pass the name WITHOUT extension.
    if ExportFile then
        ExportFile("totembar_scan", "totems=" .. count .. "\n" .. dump)
    end
end

local function HandleSlashCommand(msg)
    local cmd = string.lower(msg or "")
    if cmd == "" then
        TotemBar.ToggleBar()
    elseif cmd == "lock" then
        TotemBarDB.locked = not TotemBarDB.locked
        if TotemBarDB.locked then
            ChatOut:AddMessage("TotemBar: bar locked.")
        else
            ChatOut:AddMessage("TotemBar: bar unlocked (drag to move).")
        end
    elseif cmd == "scan" then
        TotemBar.PrintScan()
    elseif cmd == "assign" then
        -- Dev aid: inject a sample assignment to exercise the pending panel
        -- + accept/decline flow end-to-end without any transport.
        local sample = {
            Fire  = "Searing Totem",
            Earth = "Strength of Earth Totem",
            Water = "Mana Spring Totem",
            Air   = "Grace of Air Totem",
        }
        local ok, reason = TotemBar.ReceiveAssignment(sample, "TEST assignment")
        if ok then
            ChatOut:AddMessage("TotemBar: injected TEST assignment (click OK on the panel to apply).")
        else
            ChatOut:AddMessage("TotemBar: assign failed - " .. tostring(reason))
        end
    elseif cmd == "options" or cmd == "opt" then
        TotemBar.ToggleOptions()
    elseif cmd == "bind" then
        if TotemBar.ToggleBindMode then TotemBar.ToggleBindMode() end
    elseif cmd == "manadump" then
        if TotemBar.dumpManaScan then TotemBar.dumpManaScan() end
    else
        ChatOut:AddMessage("TotemBar: unknown command '" .. msg .. "'. Usage: /tb, /tb lock, /tb scan, /tb assign, /tb options, /tb bind, /tb manadump")
    end
end

-- SPELL_UPDATE_COOLDOWN fires whenever any spell's cooldown starts or
-- ends (the standard signal the default action bars key off of) - this
-- is the event-driven trigger for RefreshCooldown, kept separate from
-- the throttled per-tick timer OnUpdate (see RefreshCooldown's comment
-- for why: SetTimer-on-every-tick would restart the swipe animation).
local eventFrame = CreateFrame("Frame", "TotemBarEventFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TotemBar" then
        TotemBar.ensureDefaults()
        TotemBar.BuildUI()
        eventFrame:UnregisterEvent("ADDON_LOADED")
    elseif event == "SPELLS_CHANGED" then
        -- BuildUI resolves each slot's icon off the live spellbook at
        -- ADDON_LOADED time, but the spellbook (GetSpellName/
        -- GetSpellTexture) isn't reliably populated that early after a
        -- login/reload - so a SAVED totem's icon lookup falls through to
        -- EMPTY_ICON (the question-mark texture) even though its name is
        -- stored fine. SPELLS_CHANGED fires once the spellbook is ready
        -- (and whenever it later changes), so re-resolve every icon here.
        local elements = TotemBar.TOTEM_ELEMENTS
        for i = 1, table.getn(elements) do
            RefreshButton(elements[i])
        end
        if recallButton and recallButton.icon then
            recallButton.icon:SetTexture(GetRecallIcon())
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local elements = TotemBar.TOTEM_ELEMENTS
        for i = 1, table.getn(elements) do
            RefreshCooldown(elements[i])
        end
        RefreshFlyoutCooldowns()
    end
end)

SLASH_TOTEMBAR1 = "/tb"
SlashCmdList = SlashCmdList or {}
SlashCmdList["TOTEMBAR"] = HandleSlashCommand
