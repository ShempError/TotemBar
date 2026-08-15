-- Offline test: the "can this totem be cast right now" layer -- the mana
-- readout that greys an icon out, and the gate that keeps a REFUSED cast from
-- starting a phantom countdown.
--
-- Two separate questions share one source of truth here:
--   1. DISPLAY  -- not enough mana for the chosen totem -> dim its icon.
--   2. TRACKING -- a cast the client cannot have sent must not record a timer.
--
-- Both are pure functions so the decision is provable offline; the WoW-API
-- wiring (pre-cast snapshot in the CastSpellByName hook, the fail-event
-- revoke) is in core/cast.lua and exercised through the real recordCast at the
-- bottom of this file.
--
-- Run from repo root:
--   lua50.exe tools/luatests/test_usable.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/spellindex.lua")
dofile("core/manacost.lua")
dofile("core/cast.lua")

BOOKTYPE_SPELL = "spell"

local nowValue = 1000
GetTime = function() return nowValue end

local book = {
    [1] = { "Searing Totem", "Rank 1", "Spell_Fire_SearingTotem" },
    [2] = { "Searing Totem", "Rank 4", "Spell_Fire_SearingTotem" },
    [3] = { "Stoneskin Totem", "Rank 1", "Spell_Nature_StoneSkinTotem" },
}
GetSpellName = function(i, bt)
    local e = book[i]
    if not e then return nil end
    return e[1], e[2]
end
GetSpellTexture = function(i, bt)
    local e = book[i]
    if not e then return nil end
    return "Interface\\Icons\\" .. (e[3] or "Unknown")
end
TotemBar.invalidateSpellIndex()

-- ===== 1. mana readout =====

H.run("notEnoughMana: only a KNOWN shortfall counts", function()
    H.assert_eq(TotemBar.notEnoughMana(155, 100), true, "cost 155, mana 100 -> short")
    H.assert_eq(TotemBar.notEnoughMana(155, 155), false, "exactly enough is enough")
    H.assert_eq(TotemBar.notEnoughMana(155, 400), false, "plenty")
    -- Unknown cost is the normal state until the tooltip scan resolves (and
    -- permanently for a totem that isn't in the book). Greying an icon on
    -- "I don't know" would grey the whole bar at login.
    H.assert_eq(TotemBar.notEnoughMana(nil, 100), false, "unknown cost -> not short")
    H.assert_eq(TotemBar.notEnoughMana(155, nil), false, "unknown mana -> not short")
    H.assert_eq(TotemBar.notEnoughMana(0, 0), false, "a free spell is never short")
end)

-- ===== 2. icon tint composition =====
-- The icon has TWO independent reasons to be tinted: out-of-range (red, the
-- existing feature) and out-of-mana (dimmed, new). They must compose instead of
-- fighting over SetVertexColor -- whichever ran last would otherwise win.

H.run("iconTintFor: the two tint reasons multiply instead of overwriting", function()
    local r, g, b = TotemBar.iconTintFor(false, false)
    H.assert_eq(r .. "/" .. g .. "/" .. b, "1/1/1", "normal: untinted")

    r, g, b = TotemBar.iconTintFor(true, false)
    H.assert_eq(r .. "/" .. g .. "/" .. b, "1/0.35/0.35", "out of range: the established red")

    r, g, b = TotemBar.iconTintFor(false, true)
    H.assert_eq(r, 0.4, "out of mana: dimmed to Blizzard's unusable grey level")
    H.assert_eq(g, 0.4, "out of mana: green channel dimmed")
    H.assert_eq(b, 0.4, "out of mana: blue channel dimmed")

    r, g, b = TotemBar.iconTintFor(true, true)
    H.assert_eq(r, 0.4, "both: red channel keeps the range hue at dimmed level")
    H.assert_eq(g < 0.15, true, "both: still visibly red, not plain grey")
end)

H.run("iconTintFor: the cache key distinguishes all four states", function()
    local seen = {}
    local states = { { false, false }, { true, false }, { false, true }, { true, true } }
    for i = 1, 4 do
        local _, _, _, key = TotemBar.iconTintFor(states[i][1], states[i][2])
        H.assert_eq(seen[key], nil, "state " .. i .. " has its own key")
        seen[key] = true
    end
end)

-- ===== 3. the pre-cast gate =====
-- Measured BEFORE the cast: afterwards the mana is already spent and the GCD
-- already running, so both readings would accuse a perfectly good cast.

H.run("castGateReason: a known mana shortfall blocks", function()
    H.assert_eq(TotemBar.castGateReason(155, 100, 0, 0, 1.6, false), "mana", "not enough mana -> blocked")
    H.assert_eq(TotemBar.castGateReason(155, 200, 0, 0, 1.6, false), nil, "enough mana -> through")
    H.assert_eq(TotemBar.castGateReason(nil, 100, 0, 0, 1.6, false), nil, "unknown cost -> fail open")
end)

H.run("castGateReason: Clearcasting makes the cost irrelevant", function()
    -- Elemental Focus zeroes the next damage spell's cost while the tooltip
    -- still shows the full price. Without this the gate would refuse a cast
    -- that goes out fine -- and silently drop its timer.
    H.assert_eq(TotemBar.castGateReason(155, 10, 0, 0, 1.6, true), nil, "clearcasting -> fail open")
end)

H.run("castGateReason: only a REAL cooldown blocks, never the GCD", function()
    -- A GCD-blocked instant is QUEUED by nampower (NP_QueueInstantSpells) and
    -- still goes out a moment later, so treating the GCD as a refusal would
    -- drop the timer of a totem that is actually standing.
    H.assert_eq(TotemBar.castGateReason(nil, 500, 900, 1.5, 1.6, false), nil, "GCD-sized cooldown -> fail open")
    H.assert_eq(TotemBar.castGateReason(nil, 500, 900, 15, 1.6, false), "cooldown", "15s spell cooldown -> blocked")
    H.assert_eq(TotemBar.castGateReason(nil, 500, 0, 0, 1.6, false), nil, "no cooldown -> through")
    H.assert_eq(TotemBar.castGateReason(nil, 500, nil, nil, 1.6, false), nil, "unreadable cooldown -> fail open")
end)

H.run("castGateReason: mana is reported before cooldown when both apply", function()
    H.assert_eq(TotemBar.castGateReason(155, 10, 900, 15, 1.6, false), "mana", "the player's own fix comes first")
end)

-- ===== 4. revoking a timer from a failure message =====

H.run("soleRecentElement: revokes only when exactly ONE cast is in the window", function()
    local els = TotemBar.TOTEM_ELEMENTS
    local recs = { Fire = { start = 999.9 }, Earth = { start = 100 } }
    H.assert_eq(TotemBar.soleRecentElement(recs, els, 1000, 0.4), "Fire", "one fresh record -> that one")

    -- A four-totem drop puts several records in the same window and the 1.12
    -- event carries no spell id, so ANY pick would be a guess. Guessing wrong
    -- deletes the timer of a totem that is standing.
    recs = { Fire = { start = 999.9 }, Earth = { start = 999.8 } }
    H.assert_eq(TotemBar.soleRecentElement(recs, els, 1000, 0.4), nil, "two fresh records -> refuse to guess")

    recs = { Fire = { start = 990 } }
    H.assert_eq(TotemBar.soleRecentElement(recs, els, 1000, 0.4), nil, "record too old -> unrelated error")
    H.assert_eq(TotemBar.soleRecentElement({}, els, 1000, 0.4), nil, "nothing tracked")
end)

-- ===== 5. end-to-end through the REAL recordCast =====

local function resetState()
    TotemBar.activeTotems = {}
    TotemBar.castState.everCast = nil
    TotemBar.castBlock = nil
end

H.run("recordCast: a blocked cast recorded in the same tick starts no timer", function()
    resetState()
    nowValue = 1000

    -- What the CastSpellByName hook leaves behind when it measured the player
    -- as out of mana just before the cast went (nowhere).
    TotemBar.castBlock = { element = "Fire", name = "Searing Totem", at = 1000, reason = "mana" }
    TotemBar.recordCast("Fire", "Searing Totem")

    H.assert_eq(TotemBar.activeTotems.Fire, nil, "no phantom countdown for a cast that never went out")
    H.assert_eq(TotemBar.castState.everCast, nil, "and it is not session evidence either")
end)

H.run("recordCast: a block for a DIFFERENT totem or an older tick is ignored", function()
    resetState()
    nowValue = 1000
    TotemBar.castBlock = { element = "Earth", name = "Stoneskin Totem", at = 1000, reason = "mana" }
    TotemBar.recordCast("Fire", "Searing Totem")
    H.assert_eq(type(TotemBar.activeTotems.Fire), "table", "another element's block must not suppress this one")

    resetState()
    nowValue = 1000
    TotemBar.castBlock = { element = "Fire", name = "Searing Totem", at = 999, reason = "mana" }
    TotemBar.recordCast("Fire", "Searing Totem")
    H.assert_eq(type(TotemBar.activeTotems.Fire), "table", "a stale block must not suppress a later real cast")
end)

H.run("revokeRecentCast: drops the timer the failure belongs to", function()
    resetState()
    nowValue = 1000
    TotemBar.recordCast("Fire", "Searing Totem")

    nowValue = 1000.2
    TotemBar.revokeRecentCast(nil)
    H.assert_eq(TotemBar.activeTotems.Fire, nil, "the refused cast's timer is gone")

    -- With a spell name (nampower's SPELL_FAILED_SELF carries an id we can
    -- resolve) the pick is exact even with several records in flight.
    resetState()
    nowValue = 1000
    TotemBar.recordCast("Fire", "Searing Totem")
    TotemBar.recordCast("Earth", "Stoneskin Totem")
    nowValue = 1000.2
    TotemBar.revokeRecentCast("Stoneskin Totem")
    H.assert_eq(TotemBar.activeTotems.Earth, nil, "named revoke hits the right element")
    H.assert_eq(type(TotemBar.activeTotems.Fire), "table", "and leaves the other totem's timer alone")
end)

H.run("revokeRecentCast: a REPEAT press restores the previous timer, it does not clear it", function()
    -- The spam case, and the reason revoke is an undo rather than a delete: the
    -- first press placed the totem (timer correct), the second press one second
    -- later is refused by the element's own recovery. recordCast has already
    -- overwritten the good record with a full-length one. Deleting it would
    -- lose the timer of a totem that is standing; the honest answer is the
    -- record as it was before the refused press.
    resetState()
    nowValue = 1000
    TotemBar.recordCast("Fire", "Searing Totem")

    nowValue = 1001
    TotemBar.recordCast("Fire", "Searing Totem")       -- the refused repeat
    H.assert_eq(TotemBar.activeTotems.Fire.start, 1001, "the repeat overwrote the record")

    nowValue = 1001.2
    TotemBar.revokeRecentCast("Searing Totem")
    H.assert_eq(TotemBar.activeTotems.Fire.start, 1000, "the ORIGINAL cast's timer is back")
end)

H.run("revokeRecentCast: an unrelated late error changes nothing", function()
    resetState()
    nowValue = 1000
    TotemBar.recordCast("Fire", "Searing Totem")

    nowValue = 1005          -- five seconds later: this error is not ours
    TotemBar.revokeRecentCast(nil)
    H.assert_eq(type(TotemBar.activeTotems.Fire), "table", "the standing totem keeps its timer")
end)

-- ===== 6. attributing a GLOBAL failure event (UI_ERROR_MESSAGE/SPELLCAST_*) =====
-- These events carry no spell identity, so the ONLY safe attribution is: the
-- last thing this addon's hooks saw the client attempt (ANY spell) must have
-- BEEN the totem, inside a narrow window -- and for UI_ERROR_MESSAGE, the
-- message text must be a recognised "spell cast refused" string.

H.run("messageSet: builds a lookup set from a hole-free array", function()
    -- NOTE: the input must be hole-free (built with table.insert, like
    -- buildCastFailureMessages does) -- table.getn over a Lua 5.0 table
    -- literal with a nil in the MIDDLE is undefined and would silently drop
    -- everything after the gap. A trailing nil is fine (well-defined: the
    -- constructor simply never stores that slot).
    local set = TotemBar.messageSet({ "Not enough mana", "Out of range." })
    H.assert_eq(set["Not enough mana"], true, "first entry present")
    H.assert_eq(set["Out of range."], true, "second entry present")
    H.assert_eq(set["Something else"], nil, "unlisted string absent")
    H.assert_eq(TotemBar.messageSet(nil)["x"], nil, "nil input -> empty set, no error")
end)

H.run("attributeCastFailure: revokes only the EXACT last-attempted totem, in window", function()
    local allow = TotemBar.messageSet({ "Not enough mana" })

    local attempt = { element = "Fire", name = "Searing Totem", at = 1000 }
    local el, name = TotemBar.attributeCastFailure(attempt, 1000.2, 0.4, nil, allow)
    H.assert_eq(el, "Fire", "SPELLCAST_FAILED (no message) attributes to the last totem attempt")
    H.assert_eq(name, "Searing Totem", "and carries its exact name")

    el = TotemBar.attributeCastFailure(nil, 1000.2, 0.4, nil, allow)
    H.assert_eq(el, nil, "no attempt on record -> nothing to attribute")

    el = TotemBar.attributeCastFailure({ element = nil, name = nil, at = 1000 }, 1000.2, 0.4, nil, allow)
    H.assert_eq(el, nil, "last attempt was NOT a totem -> never attribute")
end)

H.run("attributeCastFailure: a later, different spell attempt overrides the totem", function()
    -- The exact case UI_ERROR_MESSAGE/SPELLCAST_FAILED were refused for: key
    -- spam casts the totem, then a damage spell, and THAT one fails. lastCastAttempt
    -- now names the damage spell (element=nil), so the totem is never touched.
    local allow = TotemBar.messageSet({ "Not enough mana" })
    local attempt = { element = nil, name = nil, at = 1000.1 }  -- Lightning Bolt attempted after the totem
    local el = TotemBar.attributeCastFailure(attempt, 1000.2, 0.4, "Not enough mana", allow)
    H.assert_eq(el, nil, "the totem is not blamed for a later spell's failure")
end)

H.run("attributeCastFailure: outside the window does not attribute", function()
    local allow = TotemBar.messageSet({ "Not enough mana" })
    local attempt = { element = "Fire", name = "Searing Totem", at = 1000 }
    local el = TotemBar.attributeCastFailure(attempt, 1000.5, 0.4, nil, allow)
    H.assert_eq(el, nil, "0.5s > 0.4s window -> too late to attribute")
end)

H.run("attributeCastFailure: UI_ERROR_MESSAGE requires an allow-listed message", function()
    local allow = TotemBar.messageSet({ "Not enough mana" })
    local attempt = { element = "Fire", name = "Searing Totem", at = 1000 }

    local el = TotemBar.attributeCastFailure(attempt, 1000.1, 0.4, "Not enough mana", allow)
    H.assert_eq(el, "Fire", "a recognised cast-failure message attributes")

    el = TotemBar.attributeCastFailure(attempt, 1000.1, 0.4, "Your bags are full.", allow)
    H.assert_eq(el, nil,
        "an UNRELATED UI_ERROR_MESSAGE (loot/trade/etc.) inside the same window must NOT revoke -- " ..
        "this is exactly the over-firing risk this filter exists to prevent")

    el = TotemBar.attributeCastFailure(attempt, 1000.1, 0.4, "Not enough mana", nil)
    H.assert_eq(el, nil, "missing allowlist fails CLOSED (no revoke), never open")
end)

H.summary()
