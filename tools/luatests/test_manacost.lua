-- Offline test: core/manacost.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_manacost.lua
dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")   -- TOTEM_ELEMENTS
dofile("core/manacost.lua")

local EL = TotemBar.TOTEM_ELEMENTS

H.run("parseManaCost", function()
    H.assert_eq(TotemBar.parseManaCost("155 Mana"), 155, "155 Mana")
    H.assert_eq(TotemBar.parseManaCost("55 Mana"), 55, "55 Mana")
    H.assert_eq(TotemBar.parseManaCost("Instant"), nil, "no number")
    H.assert_eq(TotemBar.parseManaCost("30 sec cooldown"), nil, "numeric non-mana line")
    H.assert_eq(TotemBar.parseManaCost(nil), nil, "nil")
end)

H.run("sumChosenCost: sums chosen, skips nil", function()
    local chosen = { Fire = "A", Water = "C" }
    local costs = { A = 100, C = 50 }
    local fn = function(n) return costs[n] end
    H.assert_eq(TotemBar.sumChosenCost(chosen, EL, fn), 150, "100+50")
    H.assert_eq(TotemBar.sumChosenCost({}, EL, fn), 0, "empty")
end)

H.run("sumActiveCost: excludes expired (remaining<=0)", function()
    local active = {
        Fire  = { totemName = "A", start = 0, duration = 100 },
        Earth = { totemName = "B", start = 0, duration = 100 },
    }
    local costs = { A = 100, B = 40 }
    local costFn = function(n) return costs[n] end
    -- remainingFn stub: A still up (10), B expired (-5)
    local rem = { A = 10, B = -5 }
    local remFn = function(start, dur, now) return nil end
    -- use totemName via closure: map by duration is awkward; use a name-aware stub
    local remByName = { A = 10, B = -5 }
    local activeByName = {}
    -- rebuild remainingFn to look up by the rec passed; simpler: encode remaining in start
    active.Fire.start = 0;  active.Fire.duration = 10   -- remaining(0,10,0)=10 >0
    active.Earth.start = 0; active.Earth.duration = 0   -- remaining(0,0,5)=-5 <=0
    local realRem = function(s, d, now) if not s or not d then return nil end return s + d - now end
    H.assert_eq(TotemBar.sumActiveCost(active, EL, 5, costFn, realRem), 100, "only A (100), B expired")
end)

H.run("refundAmount: floor(pct*cost)", function()
    H.assert_eq(TotemBar.refundAmount(0.25, 400), 100, "25% of 400")
    H.assert_eq(TotemBar.refundAmount(0.25, 401), 100, "floored")
    H.assert_eq(TotemBar.refundAmount(nil, 400), 0, "nil pct")
end)

H.run("learnRefundPct: in-range else nil", function()
    H.assert_eq(TotemBar.learnRefundPct(100, 400), 0.25, "100/400")
    H.assert_eq(TotemBar.learnRefundPct(100, 0), nil, "zero cost")
    H.assert_eq(TotemBar.learnRefundPct(1, 400), nil, "too small (<0.05)")
    H.assert_eq(TotemBar.learnRefundPct(500, 400), nil, "too big (>1.0)")
end)

H.run("durationWithMastery", function()
    H.assert_eq(TotemBar.durationWithMastery(100, true, true), 120, "helpful+mastery")
    H.assert_eq(TotemBar.durationWithMastery(100, false, true), 100, "not helpful")
    H.assert_eq(TotemBar.durationWithMastery(100, true, false), 100, "no mastery")
end)

H.run("isHelpfulTotem: damage totems excluded", function()
    H.assert_eq(TotemBar.isHelpfulTotem("Searing Totem"), false, "searing")
    H.assert_eq(TotemBar.isHelpfulTotem("Magma Totem"), false, "magma")
    H.assert_eq(TotemBar.isHelpfulTotem("Fire Nova Totem"), false, "fire nova")
    H.assert_eq(TotemBar.isHelpfulTotem("Grace of Air Totem"), true, "buff totem")
    H.assert_eq(TotemBar.isHelpfulTotem(nil), false, "nil")
end)



H.run("findHighestRankSlot: exported + picks highest rank, not first match", function()
    H.assert_eq(type(TotemBar.findHighestRankSlot), "function", "export exists (tooltips reuse it)")
    -- Stub spellbook: Searing ranks 1/2/6 at slots 3/4/9, first match = slot 3.
    local book = {
        [1] = { "Healing Wave", "Rank 1" },
        [2] = { "Stoneskin Totem", "Rank 1" },
        [3] = { "Searing Totem", "Rank 1" },
        [4] = { "Searing Totem", "Rank 2" },
        [5] = { "Healing Wave", "Rank 3" },
        [9] = { "Searing Totem", "Rank 6" },
    }
    GetSpellName = function(i, bt)
        local e = book[i]
        if not e then
            if i <= 9 then return "Filler", "" end
            return nil
        end
        return e[1], e[2]
    end
    BOOKTYPE_SPELL = "spell"
    H.assert_eq(TotemBar.findHighestRankSlot("Searing Totem"), 9, "highest rank slot 9, not first hit 3")
    H.assert_eq(TotemBar.findHighestRankSlot("Stoneskin Totem"), 2, "single rank -> its slot")
    H.assert_eq(TotemBar.findHighestRankSlot("Nope"), nil, "unknown -> nil")
    GetSpellName = nil
    BOOKTYPE_SPELL = nil
end)

H.summary()
