-- Offline test: core/cast.lua's pure decision functions (nextIndex,
-- findFilledSlot). castNext() itself touches CastSpellByName/GetTime
-- and is NOT covered here (in-game verification only). Run from repo
-- root:
--   lua50.exe tools/luatests/test_cast.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/cast.lua")

H.run("nextIndex: advances through slots and wraps", function()
    local n = table.getn(TotemBar.TOTEM_ELEMENTS)
    H.assert_eq(TotemBar.nextIndex(0, 0, 100, 2, n), 1, "no previous cast -> slot 1")
    H.assert_eq(TotemBar.nextIndex(1, 100, 100.5, 2, n), 2, "1 -> 2 within gap")
    H.assert_eq(TotemBar.nextIndex(2, 100.5, 101, 2, n), 3, "2 -> 3 within gap")
    H.assert_eq(TotemBar.nextIndex(3, 101, 101.5, 2, n), 4, "3 -> 4 within gap")
    H.assert_eq(TotemBar.nextIndex(4, 101.5, 102, 2, n), 1, "4 -> 1 wraps within gap")
end)

H.run("nextIndex: resets to 1 after gap exceeded", function()
    local n = table.getn(TotemBar.TOTEM_ELEMENTS)
    H.assert_eq(TotemBar.nextIndex(2, 100, 103, 2, n), 1, "3s gap > 2s allowed -> reset to slot 1")
    H.assert_eq(TotemBar.nextIndex(2, 100, 102, 2, n), 3, "exactly 2s (not exceeded) still advances normally")
end)

H.run("nextIndex: single-slot case always returns 1", function()
    H.assert_eq(TotemBar.nextIndex(0, 0, 100, 2, 1), 1, "no previous cast, 1 slot -> 1")
    H.assert_eq(TotemBar.nextIndex(1, 100, 100.5, 2, 1), 1, "1 slot wraps back to itself")
end)

H.run("findFilledSlot: skips empty slots, preserves order", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    local chosen = { Earth = "Stoneclaw Totem", Air = "Windfury Totem" }
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 1), 2, "starting at 1, first filled is Earth (slot 2)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 3), 4, "starting at 3, first filled is Air (slot 4)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 4), 4, "starting exactly on a filled slot stays there")
end)

H.run("findFilledSlot: wraps around the end of the list", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    local chosen = { Water = "Healing Stream Totem" }
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 4), 3, "wraps from 4 around to 3 (Water)")
    H.assert_eq(TotemBar.findFilledSlot(chosen, elements, 3), 3, "starting exactly on the only filled slot")
end)

H.run("findFilledSlot: nothing filled returns nil", function()
    local elements = TotemBar.TOTEM_ELEMENTS
    H.assert_eq(TotemBar.findFilledSlot({}, elements, 1), nil, "no slots chosen -> nil")
end)

H.run("findFilledSlot: single-element list", function()
    local elements = { "Fire" }
    H.assert_eq(TotemBar.findFilledSlot({ Fire = "Searing Totem" }, elements, 1), 1, "single slot filled -> 1")
    H.assert_eq(TotemBar.findFilledSlot({}, elements, 1), nil, "single slot empty -> nil")
end)

H.run("shouldRecall: autoRecall off -> never recall", function()
    H.assert_eq(TotemBar.shouldRecall(false, 0, 100, 2), false, "off -> false even if never deployed")
    H.assert_eq(TotemBar.shouldRecall(false, 10, 100, 2), false, "off -> false regardless of timing")
end)

H.run("shouldRecall: never deployed -> recall", function()
    H.assert_eq(TotemBar.shouldRecall(true, 0, 100, 2), true, "lastDeploy 0 -> true")
    H.assert_eq(TotemBar.shouldRecall(true, nil, 100, 2), true, "lastDeploy nil -> true")
end)

H.run("shouldRecall: deployed long ago -> recall", function()
    H.assert_eq(TotemBar.shouldRecall(true, 100, 103, 2), true, "3s > 2s guard -> true")
end)

H.run("shouldRecall: just deployed -> suppress recall", function()
    H.assert_eq(TotemBar.shouldRecall(true, 100, 101, 2), false, "1s within 2s guard -> false")
    H.assert_eq(TotemBar.shouldRecall(true, 100, 102, 2), false, "exactly 2s (not > guard) -> false")
end)

H.run("anyActiveTracked: true iff some element still remaining>0", function()
    local els = TotemBar.TOTEM_ELEMENTS
    local now = 100
    H.assert_eq(TotemBar.anyActiveTracked({}, els, now, TotemBar.remaining), false, "empty -> false")
    H.assert_eq(TotemBar.anyActiveTracked(nil, els, now, TotemBar.remaining), false, "nil -> false")
    local expired = { Fire = { start = 0, duration = 50 } }    -- 0+50-100 = -50
    H.assert_eq(TotemBar.anyActiveTracked(expired, els, now, TotemBar.remaining), false, "all expired -> false")
    local active = { Water = { start = 90, duration = 30 } }   -- 90+30-100 = 20
    H.assert_eq(TotemBar.anyActiveTracked(active, els, now, TotemBar.remaining), true, "one active -> true")
end)

-- 2026-07-16: universal CastSpellByName/CastSpell hooks (defense-in-depth
-- for totem casts outside any TotemBar function) need to resolve a possibly
-- rank-suffixed spell name down to element + base name.
H.run("stripRankSuffix: removes a trailing (Rank N) suffix, both spacing forms", function()
    H.assert_eq(TotemBar.stripRankSuffix("Searing Totem(Rank 4)"), "Searing Totem", "no space before paren")
    H.assert_eq(TotemBar.stripRankSuffix("Searing Totem (Rank 4)"), "Searing Totem", "space before paren")
    H.assert_eq(TotemBar.stripRankSuffix("Searing Totem"), "Searing Totem", "no suffix -> unchanged")
    H.assert_eq(TotemBar.stripRankSuffix("Totemic Recall(Rank 1)"), "Totemic Recall", "non-totem spell still strips fine")
    H.assert_eq(TotemBar.stripRankSuffix(nil), nil, "nil -> nil")
end)

H.run("stripRankSuffix: does not mangle names without a rank suffix", function()
    H.assert_eq(TotemBar.stripRankSuffix("Fire Nova Totem"), "Fire Nova Totem", "unranked totem name unchanged")
    H.assert_eq(TotemBar.stripRankSuffix(""), "", "empty string -> unchanged (no match)")
end)

H.run("elementFromCastName: resolves known totems (rank-suffixed or not)", function()
    local element, base = TotemBar.elementFromCastName("Searing Totem(Rank 4)")
    H.assert_eq(element, "Fire", "Searing Totem(Rank 4) -> Fire")
    H.assert_eq(base, "Searing Totem", "Searing Totem(Rank 4) -> base name stripped")

    element, base = TotemBar.elementFromCastName("Stoneclaw Totem")
    H.assert_eq(element, "Earth", "unranked known totem -> Earth")
    H.assert_eq(base, "Stoneclaw Totem", "unranked known totem -> base name unchanged")
end)

H.run("elementFromCastName: nil, non-totem and unknown spells resolve to nil, nil", function()
    local element, base = TotemBar.elementFromCastName(nil)
    H.assert_eq(element, nil, "nil name -> nil element")
    H.assert_eq(base, nil, "nil name -> nil base")

    element, base = TotemBar.elementFromCastName("Totemic Recall")
    H.assert_eq(element, nil, "Totemic Recall is not an element totem -> nil")

    element, base = TotemBar.elementFromCastName("Frostbolt(Rank 11)")
    H.assert_eq(element, nil, "unrelated ranked spell -> nil")

    element, base = TotemBar.elementFromCastName("Not A Real Spell")
    H.assert_eq(element, nil, "unknown spell name -> nil")
end)

-- recordCastFromHook's own decision logic (call recordCast, or skip a
-- same-frame duplicate) -- stubs TotemBar.recordCast itself rather than
-- exercising the real one (a thin WoW-API wrapper touching the spellbook,
-- already excluded from pure/offline coverage elsewhere in this suite; see
-- its own doc comment in core/cast.lua).
H.run("recordCastFromHook: calls recordCast when no matching same-frame record exists", function()
    local savedGetTime = GetTime
    local savedRecordCast = TotemBar.recordCast
    GetTime = function() return 500 end
    local calls = {}
    TotemBar.recordCast = function(element, totemName)
        table.insert(calls, { element = element, totemName = totemName })
    end
    TotemBar.activeTotems = {}
    TotemBar.recordCastFromHook("Fire", "Searing Totem")
    H.assert_eq(table.getn(calls), 1, "recordCast called once")
    H.assert_eq(calls[1].element, "Fire", "correct element")
    H.assert_eq(calls[1].totemName, "Searing Totem", "correct totem name")
    GetTime = savedGetTime
    TotemBar.recordCast = savedRecordCast
    TotemBar.activeTotems = {}
end)

H.run("recordCastFromHook: skips a redundant same-frame, same-totem record", function()
    local savedGetTime = GetTime
    local savedRecordCast = TotemBar.recordCast
    GetTime = function() return 700 end
    local calls = {}
    TotemBar.recordCast = function(element, totemName)
        table.insert(calls, { element = element, totemName = totemName })
    end
    TotemBar.activeTotems = { Fire = { start = 700, duration = 55, totemName = "Searing Totem" } }
    TotemBar.recordCastFromHook("Fire", "Searing Totem")
    H.assert_eq(table.getn(calls), 0, "recordCast NOT called -- a native path already recorded this exact cast this tick")
    GetTime = savedGetTime
    TotemBar.recordCast = savedRecordCast
    TotemBar.activeTotems = {}
end)

H.run("recordCastFromHook: still records when the existing record is a DIFFERENT totem this same tick", function()
    local savedGetTime = GetTime
    local savedRecordCast = TotemBar.recordCast
    GetTime = function() return 900 end
    local calls = {}
    TotemBar.recordCast = function(element, totemName)
        table.insert(calls, { element = element, totemName = totemName })
    end
    TotemBar.activeTotems = { Fire = { start = 900, duration = 20, totemName = "Magma Totem" } }
    TotemBar.recordCastFromHook("Fire", "Searing Totem")
    H.assert_eq(table.getn(calls), 1, "recordCast called -- different totem is not a duplicate")
    GetTime = savedGetTime
    TotemBar.recordCast = savedRecordCast
    TotemBar.activeTotems = {}
end)

H.run("recordCastFromHook: still records when the existing record is from an earlier tick", function()
    local savedGetTime = GetTime
    local savedRecordCast = TotemBar.recordCast
    GetTime = function() return 1000 end
    local calls = {}
    TotemBar.recordCast = function(element, totemName)
        table.insert(calls, { element = element, totemName = totemName })
    end
    TotemBar.activeTotems = { Fire = { start = 995, duration = 55, totemName = "Searing Totem" } }
    TotemBar.recordCastFromHook("Fire", "Searing Totem")
    H.assert_eq(table.getn(calls), 1, "recordCast called -- existing record is stale (earlier tick), not a same-frame duplicate")
    GetTime = savedGetTime
    TotemBar.recordCast = savedRecordCast
    TotemBar.activeTotems = {}
end)

H.summary()

-- Fail-open recall gate (2026-07-14 fix): a /reload wipes the in-memory activeTotems
-- tracking, and 1.12 has no GetTotemInfo/totemN UnitID to re-detect a pre-reload totem, so
-- the "no totems out" recall gate must NOT block when tracking is empty (unknown), only when
-- it CONFIDENTLY knows nothing is out (tracked this session, all expired).
H.run("hasTrackedTotems: nil/empty -> false, any record -> true", function()
    local el = TotemBar.TOTEM_ELEMENTS
    H.assert_eq(TotemBar.hasTrackedTotems(nil, el), false, "nil activeTotems -> false")
    H.assert_eq(TotemBar.hasTrackedTotems({}, el), false, "empty table -> false")
    H.assert_eq(TotemBar.hasTrackedTotems({ Fire = { start = 1, duration = 2 } }, el), true, "one record -> true")
    H.assert_eq(TotemBar.hasTrackedTotems({ Air = { start = 1, duration = 2 } }, el), true, "record on any element -> true")
end)

H.run("confidentNoneOut: fail-open when tracking empty; blocks only tracked+expired", function()
    local savedGetTime = GetTime
    GetTime = function() return 1000 end

    TotemBar.activeTotems = {}
    H.assert_eq(TotemBar.confidentNoneOut(), false, "empty tracking (post-/reload) -> fail-open, don't block")

    TotemBar.activeTotems = { Fire = { start = 999, duration = 60 } }   -- rem = 59 > 0
    H.assert_eq(TotemBar.confidentNoneOut(), false, "tracked + still active -> don't block")

    TotemBar.activeTotems = { Fire = { start = 900, duration = 60 } }   -- rem = -40 <= 0
    H.assert_eq(TotemBar.confidentNoneOut(), true, "tracked + all expired -> confidently none out -> block")

    GetTime = savedGetTime
    TotemBar.activeTotems = {}
end)
