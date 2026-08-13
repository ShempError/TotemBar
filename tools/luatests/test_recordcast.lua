-- Offline test: the REAL TotemBar.recordCast (core/cast.lua) and the two
-- behaviours that hang off it -- the unknown-totem guard and the sticky
-- castState.everCast session flag the manual-recall gate reads.
--
-- Deliberately NOT a stubbed copy: test_cast.lua covers the pure decision
-- functions and had to set castState.everCast BY HAND, so the production line
-- that SETS it (and the guard that skips a totem this character cannot cast)
-- had no coverage at all -- deleting either left the suite green while the
-- recall gate silently reverted to permanently fail-open. This file loads the
-- real dependency chain (totemdata -> spellindex -> manacost -> cast) and
-- stubs only the four WoW-API globals recordCast itself touches:
-- GetTime, GetSpellName (spellbook scan), GetSpellTexture, BOOKTYPE_SPELL.
--
-- Run from repo root:
--   lua50.exe tools/luatests/test_recordcast.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/spellindex.lua")
dofile("core/manacost.lua")
dofile("core/cast.lua")

BOOKTYPE_SPELL = "spell"

-- Clock stub. recordCast stamps rec.start from GetTime(); confidentNoneOut/
-- anyTotemOut read it again to decide whether anything is still out.
local nowValue = 1000
GetTime = function() return nowValue end

-- Spellbook stub. `book` is swapped per test case; the cached scan in
-- core/spellindex.lua is dropped with invalidateSpellIndex() after each swap.
local book = {}
GetSpellName = function(i, bt)
    local e = book[i]
    if not e then
        return nil
    end
    return e[1], e[2]
end
GetSpellTexture = function(i, bt)
    local e = book[i]
    if not e then
        return nil
    end
    return "Interface\\Icons\\" .. (e[3] or "Unknown")
end

-- A two-totem book: Searing Totem up to rank 4, plus Stoneskin Totem.
local function setPopulatedBook()
    book = {
        [1] = { "Searing Totem", "Rank 1", "Spell_Fire_SearingTotem" },
        [2] = { "Searing Totem", "Rank 4", "Spell_Fire_SearingTotem" },
        [3] = { "Stoneskin Totem", "Rank 1", "Spell_Nature_StoneSkinTotem" },
    }
    TotemBar.invalidateSpellIndex()
end

-- The login/unpopulated case: GetSpellName returns nil at the very first slot.
local function setEmptyBook()
    book = {}
    TotemBar.invalidateSpellIndex()
end

-- Resets everything recordCast writes to, WITHOUT touching castState.everCast
-- by hand anywhere below -- the point of this file is that only the real
-- recordCast may ever set it.
local function resetState()
    TotemBar.activeTotems = {}
    TotemBar.castState.everCast = nil
end

H.run("recordCast: a known totem records start/duration/icon and sets the session flag", function()
    setPopulatedBook()
    resetState()
    nowValue = 1000

    TotemBar.recordCast("Fire", "Searing Totem")

    local rec = TotemBar.activeTotems.Fire
    H.assert_eq(type(rec), "table", "a record was created for Fire")
    H.assert_eq(rec.totemName, "Searing Totem", "record carries the totem name")
    H.assert_eq(rec.start, 1000, "record start is GetTime()")
    H.assert_eq(rec.duration, 45, "rank 4 Searing Totem lasts 45s (no Totemic Mastery offline)")
    H.assert_eq(rec.icon, "Interface\\Icons\\Spell_Fire_SearingTotem", "icon came from the spellbook slot")
    H.assert_eq(rec.everHadBuff, false, "buff-seen latch starts false")
    H.assert_eq(rec.gtiTracked, false, "libtotem latch starts false (see TotemBar.rangeTintActive)")
    H.assert_eq(TotemBar.castState.everCast, true, "recordCast set the sticky session flag")
end)

H.run("recordCast: a totem NOT in a populated spellbook is not recorded at all", function()
    setPopulatedBook()
    resetState()
    nowValue = 2000

    -- Reachable in the field: TotemBarDB is account-wide, so a chosen set from
    -- another shaman lands on an alt that never learned these totems. The cast
    -- is a guaranteed no-op, so a full-length phantom countdown would also make
    -- anyTotemOut() true and burn Totemic Recall's cooldown on an empty board.
    TotemBar.recordCast("Air", "Grace of Air Totem")

    H.assert_eq(TotemBar.activeTotems.Air, nil, "unknown totem + populated book -> no record")
    H.assert_eq(TotemBar.castState.everCast, nil, "and the session flag stays untouched")
end)

H.run("recordCast: an UNPOPULATED spellbook fails OPEN and still records", function()
    setEmptyBook()
    resetState()
    nowValue = 3000

    -- The index cache is built lazily and the book is not reliably populated at
    -- login, so an empty scan means "no data", not "not known". Suppressing here
    -- would silently kill a legitimate totem's timer -- the worse failure.
    TotemBar.recordCast("Earth", "Stoneskin Totem")

    local rec = TotemBar.activeTotems.Earth
    H.assert_eq(type(rec), "table", "empty book -> record created anyway (fail open)")
    H.assert_eq(rec.duration, 120, "Stoneskin Totem's book duration")
    H.assert_eq(rec.icon, nil, "no spellbook slot -> no icon, but the timer still runs")
    H.assert_eq(TotemBar.castState.everCast, true, "session flag set on the fail-open path too")
end)

-- The recall gate, driven ONLY through the real recordCast: no test line below
-- assigns castState.everCast. If recordCast stops setting it, confidentNoneOut
-- can never block and these assertions fail.
H.run("confidentNoneOut: fail-open until a real recordCast, then blocks once everything expired", function()
    setPopulatedBook()
    resetState()
    nowValue = 1000

    H.assert_eq(TotemBar.confidentNoneOut(), false, "nothing cast this session (post-/reload) -> fail open")

    TotemBar.recordCast("Fire", "Searing Totem")     -- 45s from t=1000
    nowValue = 1010
    H.assert_eq(TotemBar.confidentNoneOut(), false, "totem still out -> don't block the recall")

    nowValue = 1100
    H.assert_eq(TotemBar.confidentNoneOut(), true, "cast this session + all expired -> block the no-op recall")
end)

H.run("confidentNoneOut: survives ui.lua's expiry eviction of the record", function()
    setPopulatedBook()
    resetState()
    nowValue = 1000

    TotemBar.recordCast("Fire", "Searing Totem")
    nowValue = 1100
    TotemBar.activeTotems.Fire = nil   -- what UpdateTimerDisplays does on expiry
    H.assert_eq(TotemBar.confidentNoneOut(), true, "STILL blocks after the 0.1s tick evicted the record")
end)

H.run("confidentNoneOut: survives clearActiveTotems (post-recall wipe)", function()
    setPopulatedBook()
    resetState()
    nowValue = 1000

    TotemBar.recordCast("Fire", "Searing Totem")
    H.assert_eq(TotemBar.confidentNoneOut(), false, "fresh totem out -> a second press must go through")

    TotemBar.clearActiveTotems()
    H.assert_eq(TotemBar.confidentNoneOut(), true, "after the recall wiped tracking -> block the no-op repeat")
end)

H.run("confidentNoneOut: a suppressed unknown-totem cast is NOT session evidence", function()
    setPopulatedBook()
    resetState()
    nowValue = 1000

    TotemBar.recordCast("Air", "Grace of Air Totem")   -- guarded away, records nothing
    nowValue = 1100
    H.assert_eq(TotemBar.confidentNoneOut(), false,
        "a cast that never happened must leave the gate fail-open, not claim 'nothing out'")
end)

H.run("recordCast: nil element or nil totem name records nothing", function()
    setPopulatedBook()
    resetState()

    TotemBar.recordCast(nil, "Searing Totem")
    TotemBar.recordCast("Fire", nil)
    H.assert_eq(TotemBar.activeTotems.Fire, nil, "no record from an incomplete call")
    H.assert_eq(TotemBar.castState.everCast, nil, "and no session flag either")
end)

H.summary()
