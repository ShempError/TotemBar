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
    local _, _, n = string.find(text, "^(%d+) ")
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
