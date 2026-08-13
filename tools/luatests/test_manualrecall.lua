-- Offline test: the shared MANUAL Totemic Recall path (core/cast.lua's
-- TotemBar.manualRecall + the two pure decisions behind it).
--
-- Covers the two defects that made the manual paths differ from the auto ones:
--
--  1. A manual recall the client CANNOT have cast (Totemic Recall's own 6s
--     cooldown, or a GCD) still ran clearActiveTotems(), wiping the tracking
--     while the totems stayed physically out. Combined with the sticky
--     castState.everCast session flag that means confidentNoneOut() reports
--     "confidently nothing out" and the Recall button/keybind then refuse to
--     cast at all -- the exact fail-CLOSED state core/cast.lua's own comment
--     forbids. A recall that cannot have gone out must not destroy evidence.
--
--  2. The manual paths issued a plain CastSpellByName, bypassing
--     castRecallNoQueue -- so under nampower the press could be QUEUED and pop
--     after the next set was placed, sweeping it away. All four recall sites
--     must go through the queue-safe cast.
--
-- Loads the real dependency chain (totemdata -> spellindex -> manacost ->
-- cast) and stubs only the WoW-API globals the path touches. Run from repo
-- root:
--   lua50.exe tools/luatests/test_manualrecall.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}

BOOKTYPE_SPELL = "spell"

-- Clock stub, shared by recordCast (rec.start) and the gate's remaining() math.
local nowValue = 1000
GetTime = function() return nowValue end

-- Cast spies. Defined BEFORE core/cast.lua loads so its universal
-- CastSpellByName hook wraps the spy exactly as it wraps the real global
-- in-game.
local plainCasts, noQueueCasts = 0, 0
local lastPlain, lastNoQueue = nil, nil
CastSpellByName = function(name)
    plainCasts = plainCasts + 1
    lastPlain = name
end

-- Spellbook stub: Searing Totem + Totemic Recall + Healing Stream Totem. The
-- third entry is a totem the auto paths do NOT re-place (TotemBarDB.chosen
-- below only fills Fire), so a surviving Water record proves the tracking was
-- kept rather than merely re-created by castAll().
--
-- Mutable on purpose: setBook() below rewrites it and drops the spellbook index
-- cache, so a case can model a character whose book does not contain Totemic
-- Recall at all (a shaman below level 30 -- Recall is learned at 30) and one
-- whose book has not been populated yet (login race).
local SEARING = { "Searing Totem", "Rank 4", "Spell_Fire_SearingTotem" }
local RECALL = { "Totemic Recall", nil, "Spell_Nature_TremorTotem" }
local HEALING_STREAM = { "Healing Stream Totem", "Rank 4", "Spell_Nature_HealingWaveLesser" }
local FULL_BOOK = { SEARING, RECALL, HEALING_STREAM }

local book = {}
local function setBook(entries)
    for i = 1, table.getn(FULL_BOOK) do
        book[i] = nil
    end
    for i = 1, table.getn(entries) do
        book[i] = entries[i]
    end
    if TotemBar.invalidateSpellIndex then
        TotemBar.invalidateSpellIndex()
    end
end
setBook(FULL_BOOK)

GetSpellName = function(i)
    local e = book[i]
    if not e then return nil end
    return e[1], e[2]
end
GetSpellTexture = function(i)
    local e = book[i]
    if not e then return nil end
    return "Interface\\Icons\\" .. (e[3] or "Unknown")
end

-- Cooldown stub. Only the Totemic Recall slot ever reports a cooldown; the
-- shape (start > 0 and duration > 0 == on cooldown) matches 1.12's
-- GetSpellCooldown, which also reports the GCD for a GCD-tied spell.
local recallCdStart, recallCdDuration = 0, 0
GetSpellCooldown = function(i)
    if book[i] and book[i][1] == "Totemic Recall" then
        return recallCdStart, recallCdDuration, 1
    end
    return 0, 0, 1
end

dofile("core/totemdata.lua")
dofile("core/spellindex.lua")
dofile("core/manacost.lua")
dofile("core/cast.lua")

-- nampower's queue-bypass cast. Installed AFTER cast.lua so it is not wrapped
-- by the universal hook (nampower's real export isn't either).
CastSpellByNameNoQueue = function(name)
    noQueueCasts = noQueueCasts + 1
    lastNoQueue = name
end

-- snapshotRecallCost does a live tooltip scan (CreateFrame), which does not
-- exist offline -- replace it with a spy that also records WHEN it ran, so the
-- documented ordering (cast -> snapshot -> clear, snapshot needs activeTotems
-- still populated) stays covered.
local snapshots, snapshotSawRecord = 0, nil
TotemBar.snapshotRecallCost = function()
    snapshots = snapshots + 1
    snapshotSawRecord = (TotemBar.activeTotems.Fire ~= nil)
end

-- SavedVariables stub for the two AUTO paths (recallAndCastAll / dropSetKey).
-- Only Fire is filled, so castAll() re-places Fire and nothing else.
TotemBarDB = {}

local function reset()
    TotemBar.activeTotems = {}
    TotemBar.castState.everCast = nil
    TotemBar.castState.recallBlockedAt = nil
    TotemBar.castState.lastDeployTime = 0
    plainCasts, noQueueCasts = 0, 0
    lastPlain, lastNoQueue = nil, nil
    snapshots, snapshotSawRecord = 0, nil
    recallCdStart, recallCdDuration = 0, 0
    nowValue = 1000
    setBook(FULL_BOOK)
    TotemBarDB.autoRecall = true
    TotemBarDB.chosen = { Fire = "Searing Totem" }
end

-- ===== pure: cooldownActive =====

H.run("cooldownActive: only start>0 AND duration>0 counts as on cooldown", function()
    H.assert_eq(TotemBar.cooldownActive(1000, 6), true, "6s recall cooldown running")
    H.assert_eq(TotemBar.cooldownActive(1000, 1.5), true, "GCD reported on the spell counts too")
    H.assert_eq(TotemBar.cooldownActive(0, 0), false, "ready")
    H.assert_eq(TotemBar.cooldownActive(0, 1.5), false, "start 0 -> not running")
    H.assert_eq(TotemBar.cooldownActive(1000, 0), false, "duration 0 -> not running")
end)

H.run("cooldownActive: unknown input falls open (never invents a cooldown)", function()
    H.assert_eq(TotemBar.cooldownActive(nil, nil), false, "no data -> treat as ready")
    H.assert_eq(TotemBar.cooldownActive(nil, 6), false, "half data -> treat as ready")
    H.assert_eq(TotemBar.cooldownActive(1000, nil), false, "half data -> treat as ready")
end)

-- ===== pure: manualRecallAction =====

H.run("manualRecallAction: normal cases", function()
    local mn, mx = TotemBar.RECALL_OVERRIDE_MIN, TotemBar.RECALL_OVERRIDE_MAX
    H.assert_eq(TotemBar.manualRecallAction(false, true, nil, 100, mn, mx), "cast",
        "something out + ready -> cast")
    H.assert_eq(TotemBar.manualRecallAction(true, true, nil, 100, mn, mx), "none-out",
        "confidently nothing out -> skip, save the 6s cooldown")
    H.assert_eq(TotemBar.manualRecallAction(false, false, nil, 100, mn, mx), "cooldown",
        "not castable -> skip the cast AND keep the tracking")
end)

H.run("manualRecallAction: a deliberate re-press overrides the none-out gate", function()
    local mn, mx = TotemBar.RECALL_OVERRIDE_MIN, TotemBar.RECALL_OVERRIDE_MAX
    H.assert_eq(TotemBar.manualRecallAction(true, true, 100, 101, mn, mx), "cast",
        "re-press 1s after a blocked press -> let it through")
    H.assert_eq(TotemBar.manualRecallAction(true, true, 100, 100.2, mn, mx), "none-out",
        "accidental double-click (0.2s) must NOT burn the cooldown")
    H.assert_eq(TotemBar.manualRecallAction(true, true, 100, 109, mn, mx), "none-out",
        "stale blocked press (9s) -> gate applies again")
end)

H.run("manualRecallAction: the override never wipes tracking on a dead cast", function()
    local mn, mx = TotemBar.RECALL_OVERRIDE_MIN, TotemBar.RECALL_OVERRIDE_MAX
    H.assert_eq(TotemBar.manualRecallAction(true, false, 100, 101, mn, mx), "cooldown",
        "override + not castable -> still 'cooldown', never 'cast'")
end)

-- ===== integration: the real TotemBar.manualRecall =====

H.run("manualRecall: a ready press casts queue-safe, snapshots, then clears", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")

    local action = TotemBar.manualRecall()

    H.assert_eq(action, "cast", "totem out + recall ready -> cast")
    H.assert_eq(noQueueCasts, 1, "used nampower's queue-bypass cast")
    H.assert_eq(lastNoQueue, "Totemic Recall", "cast the right spell")
    H.assert_eq(plainCasts, 0, "did NOT use the queueable plain cast")
    H.assert_eq(snapshots, 1, "refund snapshot taken")
    H.assert_eq(snapshotSawRecord, true, "snapshot ran BEFORE the tracking was cleared")
    H.assert_eq(TotemBar.activeTotems.Fire, nil, "a real recall clears own-tracking")
end)

-- Regression, defect 2: without nampower the helper must still work, via the
-- plain cast.
H.run("manualRecall: falls back to the plain cast when nampower is absent", function()
    reset()
    local saved = CastSpellByNameNoQueue
    CastSpellByNameNoQueue = nil
    TotemBar.recordCast("Fire", "Searing Totem")

    local action = TotemBar.manualRecall()

    CastSpellByNameNoQueue = saved
    H.assert_eq(action, "cast", "still casts")
    H.assert_eq(plainCasts, 1, "fell back to CastSpellByName")
    H.assert_eq(TotemBar.activeTotems.Fire, nil, "and cleared tracking")
end)

-- Regression, defect 1 (the core one): a press the client cannot honour must
-- leave the evidence alone.
H.run("manualRecall: a cooldown-blocked press casts nothing and KEEPS the tracking", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")
    recallCdStart, recallCdDuration = nowValue, 6   -- Recall on its own cooldown

    local action = TotemBar.manualRecall()

    H.assert_eq(action, "cooldown", "reported as not-castable")
    H.assert_eq(noQueueCasts + plainCasts, 0, "nothing was cast")
    H.assert_eq(snapshots, 0, "no refund snapshot for a cast that never went out")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "own-tracking survived")
    H.assert_eq(TotemBar.confidentNoneOut(), false,
        "gate stays OPEN -- the totem is still out")
end)

-- The full round-2 scenario: recall, re-drop, refused recall, then press again.
-- Before the fix the third press onwards was refused forever with a full set
-- standing.
H.run("manualRecall: refused recall does not lock the player out of recalling", function()
    reset()

    nowValue = 1000
    TotemBar.recordCast("Fire", "Searing Totem")   -- set goes out
    H.assert_eq(TotemBar.manualRecall(), "cast", "t+0: recall succeeds")
    recallCdStart, recallCdDuration = 1000, 6      -- ...and starts its 6s cooldown

    nowValue = 1001
    TotemBar.recordCast("Fire", "Searing Totem")   -- set dropped again

    nowValue = 1002                                -- inside the 6s cooldown
    H.assert_eq(TotemBar.manualRecall(), "cooldown", "t+2: client cannot cast it")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "tracking NOT wiped")

    nowValue = 1003
    H.assert_eq(TotemBar.manualRecall(), "cooldown", "t+3: still on cooldown, still no wipe")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "tracking still intact")

    nowValue = 1007                                -- cooldown over
    recallCdStart, recallCdDuration = 0, 0
    H.assert_eq(TotemBar.manualRecall(), "cast", "t+7: the standing set CAN be recalled")
    H.assert_eq(TotemBar.activeTotems.Fire, nil, "and now the tracking is cleared")
end)

-- Regression guard for commit 2be6f70: a real recall must still block the
-- pointless immediate repeat.
H.run("manualRecall: after a real recall the no-op repeat is still blocked", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")
    H.assert_eq(TotemBar.manualRecall(), "cast", "first press recalls")

    nowValue = nowValue + 0.2
    H.assert_eq(TotemBar.manualRecall(), "none-out",
        "immediate repeat blocked -- this is what saves the 6s cooldown")
    H.assert_eq(noQueueCasts, 1, "no second cast went out")
end)

-- Safety valve: the gate must never be a dead end. A totem the addon cannot
-- see (dropped from the action bar on a vanilla client) leaves everCast true
-- and anyTotemOut false -- a deliberate re-press has to get through.
H.run("manualRecall: a deliberate re-press gets through an untracked standing set", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")
    TotemBar.manualRecall()                        -- everCast sticks, tracking cleared
    H.assert_eq(noQueueCasts, 1, "the first recall went out")

    nowValue = nowValue + 30                       -- totem dropped from the action bar here:
                                                   -- invisible to own tracking
    H.assert_eq(TotemBar.manualRecall(), "none-out", "first press: gate blocks (as designed)")
    nowValue = nowValue + 1
    H.assert_eq(TotemBar.manualRecall(), "cast", "re-press: fails OPEN, the recall goes out")
    H.assert_eq(noQueueCasts, 2, "and it was the queue-safe cast again")
end)

-- An override the player already expressed must not be thrown away by a
-- transient cooldown/GCD in between.
H.run("manualRecall: the override survives a cooldown that lands between presses", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")
    TotemBar.manualRecall()                        -- everCast sticks, tracking cleared
    nowValue = nowValue + 30                       -- untracked totem standing here

    H.assert_eq(TotemBar.manualRecall(), "none-out", "press 1: gate blocks")
    nowValue = nowValue + 1
    recallCdStart, recallCdDuration = nowValue, 1.5 -- a GCD lands on press 2
    H.assert_eq(TotemBar.manualRecall(), "cooldown", "press 2: client refuses it")
    nowValue = nowValue + 1
    recallCdStart, recallCdDuration = 0, 0          -- GCD over
    H.assert_eq(TotemBar.manualRecall(), "cast",
        "press 3: the override is still live -- no second paired press needed")
end)

-- ===== recallReady: "not in the book" is KNOWN state, not unknown =====
--
-- A shaman below level 30 has not learned Totemic Recall. Failing OPEN there
-- made every press report "cast", so clearActiveTotems() ran on a set that was
-- still standing (the CastSpellByName is a guaranteed no-op) and the gate went
-- fail-CLOSED for the rest of the session -- the exact outcome the cooldown
-- check above exists to prevent, reached by a different route.

H.run("recallReady: provably not in a populated spellbook -> not castable", function()
    reset()
    setBook({ SEARING, HEALING_STREAM })
    H.assert_eq(TotemBar.spellbookEntryCount() > 0, true, "the cached scan is usable")
    H.assert_eq(TotemBar.findSpellIndex("Totemic Recall"), nil, "and Recall is provably absent")
    H.assert_eq(TotemBar.recallReady(), false, "known-unlearned -> cannot be cast")
end)

H.run("recallReady: an EMPTY spellbook scan still fails OPEN", function()
    reset()
    setBook({})
    H.assert_eq(TotemBar.spellbookEntryCount(), 0, "no usable scan (login race)")
    H.assert_eq(TotemBar.recallReady(), true,
        "unknown state must never block a legitimate recall")
end)

H.run("manualRecall: an unlearned Recall casts nothing and KEEPS the tracking", function()
    reset()
    TotemBar.recordCast("Fire", "Searing Totem")
    setBook({ SEARING, HEALING_STREAM })       -- character never learned Recall

    local action = TotemBar.manualRecall()

    H.assert_eq(action, "cooldown", "reported as not-castable")
    H.assert_eq(noQueueCasts + plainCasts, 0, "nothing was cast")
    H.assert_eq(snapshots, 0, "no refund snapshot for a cast that never went out")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "own-tracking survived")
    H.assert_eq(TotemBar.confidentNoneOut(), false,
        "gate stays OPEN -- the totem is still out")
end)

-- ===== the two AUTO paths carry the same guard =====
--
-- recallAndCastAll (the "Totems" macro) and dropSetKey (the DropSet keybind)
-- are the most-used paths in the addon. Water is tracked but NOT in
-- TotemBarDB.chosen, so castAll() cannot re-create its record: only the guard
-- can keep it alive.

H.run("recallAndCastAll: a cooldown-blocked recall keeps the timers and still deploys", function()
    reset()
    TotemBar.recordCast("Water", "Healing Stream Totem")
    recallCdStart, recallCdDuration = nowValue, 6

    TotemBar.recallAndCastAll()

    H.assert_eq(noQueueCasts, 0, "no recall went out")
    H.assert_eq((TotemBar.activeTotems.Water ~= nil), true,
        "the standing totem's timer survived the refused recall")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "castAll still placed the filled slot")
    H.assert_eq(plainCasts, 1, "exactly one totem cast, no recall")
end)

H.run("recallAndCastAll: with the cooldown clear the recall fires and clears tracking", function()
    reset()
    TotemBar.recordCast("Water", "Healing Stream Totem")

    TotemBar.recallAndCastAll()

    H.assert_eq(noQueueCasts, 1, "the recall went out, queue-safe")
    H.assert_eq(lastNoQueue, "Totemic Recall", "and it was the right spell")
    H.assert_eq(TotemBar.activeTotems.Water, nil, "clearActiveTotems ran")
    H.assert_eq((TotemBar.activeTotems.Fire ~= nil), true, "castAll re-placed the filled slot")
end)

H.run("dropSetKey: a cooldown-blocked recall on the down stroke keeps the timers", function()
    reset()
    TotemBar.recordCast("Water", "Healing Stream Totem")
    recallCdStart, recallCdDuration = nowValue, 6

    TotemBar.dropSetKey("down")

    H.assert_eq(noQueueCasts + plainCasts, 0, "nothing was cast at all")
    H.assert_eq((TotemBar.activeTotems.Water ~= nil), true, "the standing totem's timer survived")
end)

H.run("dropSetKey: with the cooldown clear the down stroke recalls and clears tracking", function()
    reset()
    TotemBar.recordCast("Water", "Healing Stream Totem")

    TotemBar.dropSetKey("down")

    H.assert_eq(noQueueCasts, 1, "the recall went out, queue-safe")
    H.assert_eq(TotemBar.activeTotems.Water, nil, "clearActiveTotems ran")
    H.assert_eq(plainCasts, 0, "the down stroke places nothing -- that is the release's job")
end)

H.summary()
