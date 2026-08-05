-- Offline test: core/spellindex.lua's pure buildSpellIndex() and the
-- cache-backed WoW-API accessors it exposes (findSpellIndex,
-- findHighestRankSlot, highestKnownRank, scanSpellbook). Run from repo
-- root:
--   lua50.exe tools/luatests/test_spellindex.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/spellindex.lua")

-- ===== Pure: buildSpellIndex(entries) =====

H.run("buildSpellIndex: bookIndex is the FIRST matching slot", function()
    local entries = {
        { name = "Lightning Bolt", rank = "Rank 1" },
        { name = "Lightning Bolt", rank = "Rank 2" },
    }
    local idx = TotemBar.buildSpellIndex(entries)
    H.assert_eq(idx["Lightning Bolt"].bookIndex, 1, "first slot, not last")
end)

H.run("buildSpellIndex: maxRankIndex/maxRank pick the HIGHEST parsed rank, not first match", function()
    local entries = {
        { name = "Stoneskin Totem", rank = "Rank 1" },   -- 1
        { name = "Searing Totem", rank = "Rank 1" },     -- 2
        { name = "Searing Totem", rank = "Rank 2" },     -- 3
        { name = "Searing Totem", rank = "Rank 3" },     -- 4
    }
    local idx = TotemBar.buildSpellIndex(entries)
    H.assert_eq(idx["Searing Totem"].bookIndex, 2, "first Searing slot")
    H.assert_eq(idx["Searing Totem"].maxRankIndex, 4, "highest rank (3) is slot 4, not first hit")
    H.assert_eq(idx["Searing Totem"].maxRank, 3, "highest rank number is 3")
    H.assert_eq(idx["Stoneskin Totem"].bookIndex, 1, "single-rank -> its own slot")
    H.assert_eq(idx["Stoneskin Totem"].maxRankIndex, 1, "single-rank -> maxRankIndex == bookIndex")
    H.assert_eq(idx["Stoneskin Totem"].maxRank, 1, "single-rank -> maxRank == 1")
end)

H.run("buildSpellIndex: out-of-order ranks still resolve the true max (not scan order)", function()
    local entries = {
        { name = "Windfury Totem", rank = "Rank 2" },   -- 1
        { name = "Windfury Totem", rank = "Rank 1" },   -- 2 (lower rank listed AFTER a higher one)
    }
    local idx = TotemBar.buildSpellIndex(entries)
    H.assert_eq(idx["Windfury Totem"].maxRankIndex, 1, "rank 2 (slot 1) still wins over a later rank 1")
    H.assert_eq(idx["Windfury Totem"].maxRank, 2, "max rank stays 2")
end)

H.run("buildSpellIndex: unparseable rank strings fall back to the LAST matching slot", function()
    local entries = {
        { name = "Mystery Totem", rank = "" },
        { name = "Mystery Totem", rank = "" },
        { name = "Mystery Totem", rank = "Special" },  -- still no digit
    }
    local idx = TotemBar.buildSpellIndex(entries)
    H.assert_eq(idx["Mystery Totem"].bookIndex, 1, "bookIndex is still the first slot")
    H.assert_eq(idx["Mystery Totem"].maxRankIndex, 3, "no rank ever parsed -> fallback slides to the LAST slot")
    H.assert_eq(idx["Mystery Totem"].maxRank, nil, "no rank number ever parsed -> nil")
end)

H.run("buildSpellIndex: unranked single-occurrence spell -> bookIndex==maxRankIndex, maxRank nil", function()
    local entries = { { name = "Totemic Recall", rank = "" } }
    local idx = TotemBar.buildSpellIndex(entries)
    H.assert_eq(idx["Totemic Recall"].bookIndex, 1, "its own slot")
    H.assert_eq(idx["Totemic Recall"].maxRankIndex, 1, "trivially its own slot too")
    H.assert_eq(idx["Totemic Recall"].maxRank, nil, "no rank string -> nil")
end)

H.run("buildSpellIndex: unknown name is simply absent from the index", function()
    local idx = TotemBar.buildSpellIndex({ { name = "Searing Totem", rank = "Rank 1" } })
    H.assert_eq(idx["Nope"], nil, "not present -> nil")
end)

H.run("buildSpellIndex: nil-name entries are skipped without error", function()
    local idx = TotemBar.buildSpellIndex({
        { name = nil, rank = "Rank 1" },
        { name = "Real Totem", rank = "Rank 1" },
    })
    H.assert_eq(idx["Real Totem"].bookIndex, 2, "the real entry still indexes correctly")
end)

H.run("buildSpellIndex: nil or empty entries -> empty table, no error", function()
    local idxNil = TotemBar.buildSpellIndex(nil)
    H.assert_eq(type(idxNil), "table", "nil entries -> still returns a table")
    local idxEmpty = TotemBar.buildSpellIndex({})
    H.assert_eq(type(idxEmpty), "table", "empty entries -> still returns a table")
end)

-- ===== WoW-API layer: cache-backed accessors =====

H.run("getSpellIndex/findSpellIndex/findHighestRankSlot/highestKnownRank: build once, cache, reuse", function()
    local book = {
        [1] = { "Stoneskin Totem", "Rank 1" },
        [2] = { "Searing Totem", "Rank 1" },
        [3] = { "Searing Totem", "Rank 2" },
        [4] = { "Searing Totem", "Rank 6" },
    }
    local scanCalls = 0
    GetSpellName = function(i, bt)
        local e = book[i]
        if not e then
            scanCalls = scanCalls + 1  -- one increment per full book WALK (the terminal nil hit)
            return nil
        end
        return e[1], e[2]
    end
    BOOKTYPE_SPELL = "spell"

    TotemBar.invalidateSpellIndex()

    H.assert_eq(TotemBar.findSpellIndex("Searing Totem"), 2, "first-match slot (rank 1)")
    H.assert_eq(TotemBar.findHighestRankSlot("Searing Totem"), 4, "highest-rank slot (rank 6)")
    H.assert_eq(TotemBar.highestKnownRank("Searing Totem"), 6, "highest rank number")
    H.assert_eq(TotemBar.findSpellIndex("Stoneskin Totem"), 1, "single-rank slot")
    H.assert_eq(TotemBar.findSpellIndex("Nope"), nil, "unknown -> nil")
    H.assert_eq(scanCalls, 1, "only ONE full-book walk across 5 accessor calls (cached)")

    -- Mutate the live book WITHOUT invalidating: the cache must keep
    -- serving the stale answer -- proves this is a real cache, not a
    -- coincidence of the stub.
    book[5] = { "Windfury Totem", "Rank 1" }
    H.assert_eq(TotemBar.findSpellIndex("Windfury Totem"), nil, "not yet visible -- cache still stale on purpose")
    H.assert_eq(scanCalls, 1, "still only one walk -- confirms caching, not luck")

    TotemBar.invalidateSpellIndex()
    H.assert_eq(TotemBar.findSpellIndex("Windfury Totem"), 5, "visible after invalidate -> rebuild picks up the new spell")
    H.assert_eq(scanCalls, 2, "invalidate forced exactly one more walk")

    GetSpellName = nil
    BOOKTYPE_SPELL = nil
end)

H.run("scanSpellbook: flat name list, ONE ENTRY PER SLOT (ranks not collapsed)", function()
    local book = {
        [1] = { "Searing Totem", "Rank 1" },
        [2] = { "Searing Totem", "Rank 2" },
        [3] = { "Stoneskin Totem", "Rank 1" },
    }
    GetSpellName = function(i, bt)
        local e = book[i]
        if not e then return nil end
        return e[1], e[2]
    end
    BOOKTYPE_SPELL = "spell"
    TotemBar.invalidateSpellIndex()

    local names = TotemBar.scanSpellbook()
    H.assert_eq(table.getn(names), 3, "one name per spellbook slot, duplicates included")
    H.assert_eq(names[1], "Searing Totem", "slot 1")
    H.assert_eq(names[2], "Searing Totem", "slot 2 (same name, different rank)")
    H.assert_eq(names[3], "Stoneskin Totem", "slot 3")

    GetSpellName = nil
    BOOKTYPE_SPELL = nil
end)

H.run("findSpellIndex/findHighestRankSlot/highestKnownRank: nil name -> nil, no scan", function()
    TotemBar.invalidateSpellIndex()
    local scanned = false
    GetSpellName = function() scanned = true return nil end
    BOOKTYPE_SPELL = "spell"
    H.assert_eq(TotemBar.findSpellIndex(nil), nil, "nil name -> nil")
    H.assert_eq(TotemBar.findHighestRankSlot(nil), nil, "nil name -> nil")
    H.assert_eq(TotemBar.highestKnownRank(nil), nil, "nil name -> nil")
    H.assert_eq(scanned, false, "nil short-circuits before touching the spellbook at all")
    GetSpellName = nil
    BOOKTYPE_SPELL = nil
end)

H.summary()
