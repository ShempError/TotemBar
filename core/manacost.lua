-- TotemBar - core/manacost.lua
-- Mana-cost reading + refund/duration helpers. The PURE functions here are
-- offline-tested; the WoW-API pieces (hidden-tooltip scan, talent scan, refund
-- learner) are appended in a later task and are guarded so this file loads
-- fine under plain Lua for the tests.

TotemBar = TotemBar or {}

-- Pure: mana cost from a tooltip line like "155 Mana" -> 155, else nil.
function TotemBar.parseManaCost(text)
    if not text then
        return nil
    end
    -- Anchor to the "Mana" keyword so a numeric line like "30 sec cooldown"
    -- can't be mistaken for the cost (don't rely on tooltip line ordering).
    local _, _, n = string.find(text, "^(%d+) [Mm]ana")
    if n then
        return tonumber(n)
    end
    return nil
end

-- Pure: sum costFn(chosen[element]) over the elements that have a chosen totem.
function TotemBar.sumChosenCost(chosen, elements, costFn)
    local total = 0
    if not chosen then
        return 0
    end
    for i = 1, table.getn(elements) do
        local name = chosen[elements[i]]
        if name then
            local c = costFn(name)
            if c then
                total = total + c
            end
        end
    end
    return total
end

-- Pure: sum cost of active totems that are still out (remaining > 0).
function TotemBar.sumActiveCost(activeTotems, elements, now, costFn, remainingFn)
    local total = 0
    if not activeTotems then
        return 0
    end
    for i = 1, table.getn(elements) do
        local rec = activeTotems[elements[i]]
        if rec then
            local rem = remainingFn(rec.start, rec.duration, now)
            if rem and rem > 0 then
                local c = costFn(rec.totemName)
                if c then
                    total = total + c
                end
            end
        end
    end
    return total
end

-- Pure: is a KNOWN mana shortfall in front of us? Both halves must be known
-- numbers -- an unresolved cost (the normal state until the tooltip scan runs,
-- and permanently for a totem that isn't in this character's book) is "I don't
-- know", never "too expensive". Greying a bar on "I don't know" would grey the
-- whole bar at login; refusing to record a timer on it would silently drop the
-- countdown of a totem that is standing. Both callers therefore fail OPEN here,
-- the same policy as confidentNoneOut/recallReady in core/cast.lua.
function TotemBar.notEnoughMana(cost, mana)
    if not cost or not mana then
        return false
    end
    return mana < cost
end

-- Clearcasting (Elemental Focus) used to exempt every mana verdict here. That was
-- WRONG and is gone (2026-08-28, player-reported): Elemental Focus zeroes the next
-- DAMAGE spell, not a totem summon, so a totem costs full price while Clearcasting
-- is up. Because totems are the only thing this addon casts, the exemption
-- disabled the mana gate and the out-of-mana dim outright whenever the buff was
-- up. TotemBar.hasClearcasting/CLEARCAST_ICON were removed with it -- the icon was
-- never verified in-game and now has no consumer. TotemBar.hasBuffWithIcon stays:
-- the out-of-range tint still uses it.

-- Live mana verdict for one totem by name: true only when its cost is known,
-- the player's mana is below it, and no Clearcasting is up. Reads the cached
-- tooltip cost (see getTotemManaCost), so this is a table lookup plus one
-- UnitMana call -- cheap enough for the 5Hz display tick that calls it.
function TotemBar.totemOutOfMana(name)
    if not name or type(UnitMana) ~= "function" then
        return false
    end
    return TotemBar.notEnoughMana(TotemBar.getTotemManaCost(name), UnitMana("player"))
end

-- Pure: floored refund.
function TotemBar.refundAmount(pct, activeCost)
    if not pct or not activeCost then
        return 0
    end
    return math.floor(pct * activeCost)
end

-- Pure: learn refund pct from an observed mana gain; nil if out of sane range.
function TotemBar.learnRefundPct(manaGained, activeCost)
    if not manaGained or not activeCost or activeCost <= 0 then
        return nil
    end
    local pct = manaGained / activeCost
    if pct < 0.05 or pct > 1.0 then
        return nil
    end
    return pct
end

-- Pure: helpful totems get Totemic Mastery's +20% duration.
function TotemBar.durationWithMastery(baseDuration, isHelpful, hasMastery)
    if hasMastery and isHelpful then
        return baseDuration * 1.2
    end
    return baseDuration
end

-- The pure fire-DAMAGE totems do NOT get the +20% helpful-totem duration.
-- Everything else is treated as helpful. VERIFY in-game and adjust.
TotemBar.NON_HELPFUL_TOTEMS = {
    ["Searing Totem"] = true,
    ["Magma Totem"] = true,
    ["Fire Nova Totem"] = true,
}

function TotemBar.isHelpfulTotem(name)
    if not name then
        return false
    end
    if TotemBar.NON_HELPFUL_TOTEMS[name] then
        return false
    end
    return true
end

-- Pure: brings a pfUI-libtotem-reported duration onto the same scale as the
-- one recordCast stores. libtotem serves FLAT book durations; own tracking
-- applies Totemic Mastery's +20% to helpful totems. ui.lua's timer prefers
-- libtotem while it reports the slot active and falls back to own tracking
-- once libtotem evicts it -- so at the book duration the display flipped
-- source and the countdown jumped back UP (...3, 2, 1, 24) with the duration
-- ring re-filling, instead of running out. Scaling both sides by the same
-- factor makes them agree on the endpoint.
function TotemBar.gtiDurationWithMastery(gtiDuration, gtiName, hasMastery)
    if not gtiDuration then
        return nil
    end
    return TotemBar.durationWithMastery(gtiDuration, TotemBar.isHelpfulTotem(gtiName), hasMastery)
end

-- ===== WoW-API layer (not offline-executed) =====

-- TotemBar.findHighestRankSlot(name) used to be defined here as its own
-- fresh linear GetSpellName() scan per call. It's now a cache-backed
-- accessor provided by core/spellindex.lua (loaded earlier in the TOC) --
-- same name, same signature, same resolved slot (the HIGHEST known rank,
-- which is the one CastSpellByName actually casts; a first-match scan
-- would return rank 1 -> cost far too low, the bug behind "the mana
-- values are wrong"). Shared: ui.lua's tooltips resolve through this too -
-- SetSpell with a first-name-match slot shows the RANK 1 tooltip (wrong
-- mana/duration).

local scanTip = nil
local manaCache = {}   -- name -> cost (only positive results cached)

-- Reads a totem's mana cost via a hidden tooltip scan (no GetSpellManaCost on
-- 1.12). Reflects cost talents (Tidal Focus, Restorative Totems) automatically.
-- Cached by name; cache cleared on SPELLS_CHANGED (talent/rank changes).
function TotemBar.getTotemManaCost(name)
    if not name then return nil end
    if manaCache[name] then return manaCache[name] end
    local idx = TotemBar.findHighestRankSlot(name)
    if not idx then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TotemBarScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(idx, BOOKTYPE_SPELL)
    local cost = nil
    local lines = scanTip:NumLines() or 0
    for i = 1, lines do
        local fs = getglobal("TotemBarScanTooltipTextLeft" .. i)
        local text = fs and fs:GetText()
        local c = TotemBar.parseManaCost(text)
        if c then
            cost = c
            break
        end
    end
    if cost then manaCache[name] = cost end
    return cost
end

-- Dev aid (/tb manadump): dump the RAW mana-cost scan for the chosen totems +
-- Totemic Recall to <WoW>\imports\totembar_manadump.txt, so the resolved
-- slot/rank, every tooltip line, and the parsed cost can be verified
-- off-client (ground truth for the mana-cost feature). Chat fallback if no
-- SuperWoW ExportFile.
function TotemBar.dumpManaScan()
    local els = TotemBar.TOTEM_ELEMENTS
    local chosen = (TotemBarDB and TotemBarDB.chosen) or {}
    local list = {}
    for i = 1, table.getn(els) do
        local nm = chosen[els[i]]
        if nm then list[table.getn(list) + 1] = nm end
    end
    list[table.getn(list) + 1] = "Totemic Recall"
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TotemBarScanTooltip", nil, "GameTooltipTemplate")
    end
    local out = "TotemBar mana scan dump\n"
    local total = 0
    for i = 1, table.getn(list) do
        local nm = list[i]
        local idx = TotemBar.findHighestRankSlot(nm)
        out = out .. "\n[" .. nm .. "] slot=" .. tostring(idx)
        if idx then
            local rn, rr = GetSpellName(idx, BOOKTYPE_SPELL)
            out = out .. " resolved='" .. tostring(rn) .. "' rank='" .. tostring(rr) .. "'\n"
            scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
            scanTip:ClearLines()
            scanTip:SetSpell(idx, BOOKTYPE_SPELL)
            local lines = scanTip:NumLines() or 0
            local cost = nil
            for L = 1, lines do
                local fs = getglobal("TotemBarScanTooltipTextLeft" .. L)
                local text = fs and fs:GetText()
                out = out .. "   L" .. L .. ": " .. tostring(text) .. "\n"
                if not cost then
                    local c = TotemBar.parseManaCost(text)
                    if c then cost = c end
                end
            end
            out = out .. "   parsedCost=" .. tostring(cost) .. "\n"
            if cost and nm ~= "Totemic Recall" then total = total + cost end
        else
            out = out .. " (not found in spellbook)\n"
        end
    end
    out = out .. "\nsumChosenCost(live)=" .. tostring(
        TotemBar.sumChosenCost(chosen, els, TotemBar.getTotemManaCost)) .. "\n"
    out = out .. "dumpTotal(chosen)=" .. total .. "\n"
    if ExportFile then
        ExportFile("totembar_manadump", out)
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "TotemBar: mana dump written (imports\\totembar_manadump.txt). chosen sum=" .. total)
    end
end

-- Totemic Mastery (TWoW: +20% helpful-totem duration): cached scan of the
-- talent trees by name.
local masteryCached = false
local function scanMastery()
    masteryCached = false
    local tabs = (GetNumTalentTabs and GetNumTalentTabs()) or 0
    for tab = 1, tabs do
        local num = GetNumTalents(tab)
        for i = 1, num do
            local tname, _, _, _, rank = GetTalentInfo(tab, i)
            if tname == "Totemic Mastery" and rank and rank > 0 then
                masteryCached = true
            end
        end
    end
end

function TotemBar.hasTotemicMastery()
    return masteryCached
end

-- Recall-refund auto-learn. Snapshot the summed cost of the totems currently
-- out just before a DELIBERATE Totemic Recall; when the mana-gain message
-- arrives shortly after, learn the real refund %.
TotemBar.recallPendingCost = 0
local recallExpectUntil = 0

function TotemBar.snapshotRecallCost()
    TotemBar.recallPendingCost = TotemBar.sumActiveCost(
        TotemBar.activeTotems, TotemBar.TOTEM_ELEMENTS, GetTime(),
        TotemBar.getTotemManaCost, TotemBar.remaining)
    recallExpectUntil = GetTime() + 2
end

-- Events: refresh mastery, clear the cost cache on spell changes, and learn
-- the refund % from the recall mana-gain message.
-- Guarded: CreateFrame is nil under plain offline Lua, so this whole block is
-- skipped there (loadfile/dofile must not error for the test suite).
if CreateFrame then
    local mcEvents = CreateFrame("Frame", "TotemBarManaCostEventFrame", UIParent)
    mcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    mcEvents:RegisterEvent("CHARACTER_POINTS_CHANGED")
    mcEvents:RegisterEvent("SPELLS_CHANGED")
    mcEvents:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
    mcEvents:SetScript("OnEvent", function()
        if event == "PLAYER_ENTERING_WORLD" or event == "CHARACTER_POINTS_CHANGED" then
            scanMastery()
        elseif event == "SPELLS_CHANGED" then
            manaCache = {}
            scanMastery()
        elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
            if GetTime() > recallExpectUntil then return end
            local msg = arg1
            if not msg then return end
            -- Learn only from a Totemic Recall mana-gain within the window.
            -- NOTE: exact message text is locale/format dependent - VERIFY in-game
            -- (adjust the "Totemic Recall" + number pattern if needed).
            if string.find(msg, "Totemic Recall") then
                local _, _, num = string.find(msg, "(%d+)")
                local gained = tonumber(num)
                local pct = TotemBar.learnRefundPct(gained, TotemBar.recallPendingCost)
                if pct and TotemBarDB then
                    TotemBarDB.recallRefundPct = pct
                end
            end
        end
    end)
end
