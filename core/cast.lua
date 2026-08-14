-- TotemBar - core/cast.lua
-- Cast-cycle logic. The decision-making is split into two PURE,
-- offline-tested functions (nextIndex, findFilledSlot); castNext() is
-- the thin wrapper that touches CastSpellByName / GetTime / TotemBarDB.

TotemBar = TotemBar or {}

TotemBar.DEFAULT_GAP_SECONDS = 2

-- Anti double-press guard for recallAndCastAll: if a deploy happened within
-- this many seconds, a rapid second press SKIPS the recall (so it doesn't
-- pull the just-placed totems, which are still on their ~1.5s element
-- cooldown and couldn't be re-placed).
TotemBar.DEFAULT_RECALL_GUARD = 2

-- The spell the recall paths cast. One source for the name so the guard, the
-- cooldown lookup and the cast itself can never disagree.
local RECALL_SPELL_NAME = "Totemic Recall"

-- How long a manual Recall press that the "nothing is out" gate BLOCKED stays
-- remembered, so a deliberate re-press can override the gate (see
-- TotemBar.manualRecallAction). The lower bound exists so an accidental
-- double-click cannot burn the very 6s cooldown the gate is there to save; the
-- upper bound expires the override again.
TotemBar.RECALL_OVERRIDE_MIN = 0.5
TotemBar.RECALL_OVERRIDE_MAX = 5

-- Default gap (px) between bar buttons. Matches ui.lua's file-scope
-- BUTTON_GAP default; the options panel's "Button spacing" slider (range
-- 10-30px) live-applies changes via TotemBar.SetButtonGap (ui.lua) and
-- persists them to TotemBarDB.buttonGap (core/config.lua).
TotemBar.DEFAULT_BUTTON_GAP = 10

-- Cycle state: which slot was cast last, and when.
TotemBar.castState = TotemBar.castState or {
    index = 0,      -- 0 = no cast yet (or state was reset)
    lastTime = 0,
    lastDeployTime = 0,
}

-- Own-tracking table for the OmniCC-style remaining-duration display in
-- ui.lua: fallback source for when pfUI's libtotem (GetTotemInfo) isn't
-- present, or reports a given slot inactive. element -> {start=,
-- duration=}, both in TotemBar.recordCast() below.
TotemBar.activeTotems = TotemBar.activeTotems or {}

-- Pure: given the previously cast slot index, the time of that previous
-- cast, the current time, the allowed gap (seconds) and the number of
-- slots, returns the next slot index (1-based) to advance to.
--
-- - prevIndex <= 0 (never cast yet)      -> 1
-- - now - lastTime > gapSeconds          -> 1 (fresh spam, start over)
-- - otherwise                            -> prevIndex + 1, wrapping from
--                                            numSlots back to 1
function TotemBar.nextIndex(prevIndex, lastTime, now, gapSeconds, numSlots)
    if not prevIndex or prevIndex <= 0 then
        return 1
    end
    if not lastTime or (now - lastTime) > gapSeconds then
        return 1
    end
    local nxt = prevIndex + 1
    if nxt > numSlots then
        nxt = 1
    end
    return nxt
end

-- Pure: starting at startIndex, walk forward through `elements`
-- (wrapping past the end back to 1) and return the index of the first
-- element for which chosen[element] is truthy (a totem name). Returns
-- nil if none of the slots are filled.
function TotemBar.findFilledSlot(chosen, elements, startIndex)
    local numSlots = table.getn(elements)
    if numSlots == 0 or not startIndex then
        return nil
    end
    for tries = 0, numSlots - 1 do
        local slot = startIndex + tries
        if slot > numSlots then
            slot = slot - numSlots
        end
        if chosen[elements[slot]] then
            return slot
        end
    end
    return nil
end

-- Pure: seconds remaining given a start time, a duration and the
-- current time. May return <= 0 (already expired); callers decide how
-- to treat that. Returns nil if either start or duration is missing.
function TotemBar.remaining(start, duration, now)
    if not start or not duration then
        return nil
    end
    return start + duration - now
end

-- Pure: is any element's own-tracked totem still out (remaining > 0)?
function TotemBar.anyActiveTracked(activeTotems, elements, now, remainingFn)
    if not activeTotems then
        return false
    end
    for i = 1, table.getn(elements) do
        local rec = activeTotems[elements[i]]
        if rec then
            local rem = remainingFn(rec.start, rec.duration, now)
            if rem and rem > 0 then
                return true
            end
        end
    end
    return false
end

-- Pure: decides which of two already-computed remaining-seconds values
-- to show for one element's timer text. GetTotemInfo (pfUI's
-- libtotem), when it reports the slot active, is authoritative;
-- otherwise (absent, or reporting the slot inactive) falls back to
-- TotemBar's own cast-tracking. Returns nil when neither source has
-- time left.
function TotemBar.resolveRemaining(gtiActive, gtiRemaining, ownRemaining)
    -- FIX 2026-07-15: trust GTI (pfUI libtotem) ONLY when it reports the slot active
    -- AND with positive time left. Previously a stale-active GTI slot (active but
    -- gtiRemaining<=0 -- libtotem evicts lazily on read) hit the bare `return nil` and
    -- BLOCKED the timer even when own-tracking had a valid time. That produced the
    -- Fire/Earth-dead, Air-flickering, Water-ok pattern (pfUI's single non-slot-indexed
    -- cast queue loses the race for the slots cast later in a multi-drop).
    if gtiActive and gtiRemaining and gtiRemaining > 0 then
        return gtiRemaining
    end
    if ownRemaining and ownRemaining > 0 then
        return ownRemaining
    end
    return nil
end

-- Pure: should the out-of-range red tint treat this element as ACTIVE?
--
-- Own tracking is the base signal. When pfUI's libtotem is present its
-- GetTotemInfo may VETO it, so a totem DESTROYED before its timer ran out
-- stops flashing red -- but only for a slot libtotem demonstrably tracked
-- (gtiTracked, latched in ui.lua when GTI reported the slot active under this
-- record's totem name). "GTI has no record for this slot" is no information,
-- not a contradiction: libtotem keeps a single non-slot-indexed cast queue
-- committed on ONE SPELLCAST_STOP, so a four-totem drop leaves three slots
-- with no GTI record at all. Vetoing on those silenced both the red tint and
-- the Recall button's out-of-range pulse for most of the set -- the same
-- missing-GTI race resolveRemaining above already fixed for the timer path.
function TotemBar.rangeTintActive(hasOwnRecord, hasGTI, gtiTracked, gtiActive)
    if not hasOwnRecord then
        return false
    end
    if hasGTI and gtiTracked and not gtiActive then
        return false
    end
    return true
end

-- Out-of-mana dim level. Blizzard's own "unusable" grey from FrameXML
-- ActionButton.lua:280 (ActionButton_UpdateUsable). Blizzard reserves a BLUE
-- tint (0.5,0.5,1.0) for the not-enough-mana case specifically and grey for
-- every other reason; TotemBar dims instead, because its icons already carry a
-- red state and a second HUE would compete with it, while a brightness step
-- reads on top of any hue.
TotemBar.OOM_DIM = 0.4

-- Pure: the icon's vertex colour, composed from the two independent reasons a
-- totem button can be tinted -- out of range (red, buff-presence based, see
-- rangeTintActive above) and out of mana (dimmed, new). They MULTIPLY rather
-- than override, so an out-of-range totem the player also cannot afford stays
-- recognisably red while reading as unavailable; two separate SetVertexColor
-- call sites would instead have raced, and whichever ran last would have won.
--
-- The fourth return is a cache key: the caller stores it on the button and only
-- touches the texture when it changes (0 allocations, no redundant API calls on
-- the 5Hz tick).
function TotemBar.iconTintFor(rangeRed, oom)
    local r, g, b = 1, 1, 1
    if rangeRed then
        r, g, b = 1, 0.35, 0.35
    end
    local key = 0
    if rangeRed then
        key = key + 1
    end
    if oom then
        key = key + 2
        r = r * TotemBar.OOM_DIM
        g = g * TotemBar.OOM_DIM
        b = b * TotemBar.OOM_DIM
    end
    return r, g, b, key
end

-- Pure: OmniCC-style text for an already-known-positive remaining
-- seconds value: whole minutes rounded up from 60s on, plain rounded-up
-- integer seconds below that.
function TotemBar.formatRemaining(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.ceil(remaining / 60))
    end
    return string.format("%d", math.ceil(remaining))
end

-- Pure: strips a trailing rank suffix from a spell name as CastSpellByName
-- would receive it -- both "Searing Totem(Rank 4)" (no space, what the
-- client itself produces) and "Searing Totem (Rank 4)" (a space, common in
-- hand-typed macros) are accepted forms. Returns the input unchanged if it
-- carries no such suffix, or nil if name is nil.
function TotemBar.stripRankSuffix(name)
    if not name then
        return nil
    end
    local _, _, base = string.find(name, "^(.-)%s*%(.-%)%s*$")
    if base and base ~= "" then
        return base
    end
    return name
end

-- Pure: given a spell name as CastSpellByName/GetSpellName would produce it
-- (optionally rank-suffixed, see stripRankSuffix above), returns the
-- element it belongs to and its rank-stripped base name -- or nil, nil if
-- rawName is nil or isn't one of TotemBar's known totems (core/totemdata.lua).
-- Used by the universal CastSpellByName/CastSpell hooks below to decide
-- whether a cast caught outside TotemBar's own paths is a totem at all.
function TotemBar.elementFromCastName(rawName)
    if not rawName then
        return nil, nil
    end
    local baseName = TotemBar.stripRankSuffix(rawName)
    local element = TotemBar.elementOf(baseName)
    if not element then
        return nil, nil
    end
    return element, baseName
end

-- Finds the spellbook index of a known spell by exact name, or nil.
-- Used to duplicate ui.lua's own file-local FindSpellIndexByName as its
-- own fresh linear scan (no common "api" module to hang a single copy
-- off). Both now route through core/spellindex.lua's cached
-- TotemBar.findSpellIndex (loaded earlier in the TOC) instead.

-- ===== Cast gate: don't start a countdown for a cast that never went out =====
--
-- The symptom this fixes: the timer starts even when the totem could not be
-- placed. recordCast runs right after CastSpellByName, and 1.12 gives Lua no
-- return value saying whether the cast was accepted -- so every refused press
-- used to start a full-length phantom countdown (and made anyTotemOut() true,
-- which then burned Totemic Recall's 6s cooldown on an empty board).
--
-- The verdict is taken BEFORE the cast, by the CastSpellByName/CastSpell hooks
-- below. Measuring afterwards cannot work: by then the mana is already spent
-- (so every successful cast looks unaffordable) and the GCD is already running
-- (so every successful cast looks cooldown-blocked).

-- A cooldown at or below this is treated as the global cooldown and never
-- blocks. Two reasons: GetSpellCooldown reports the GCD in the same fields as a
-- real cooldown, and nampower QUEUES a GCD-blocked instant
-- (NP_QueueInstantSpells, default on) so it still goes out a moment later --
-- refusing to record it would drop the timer of a totem that IS standing.
TotemBar.GCD_MAX = 1.6

-- Pure: why can this cast not have gone out? Returns nil (fail open), "mana" or
-- "cooldown". Every input may be nil -- an unknown never blocks, exactly like
-- notEnoughMana/confidentNoneOut. Mana is reported first because it is the one
-- the player can act on.
function TotemBar.castGateReason(cost, mana, cdStart, cdDuration, gcdMax, clearcasting)
    if not clearcasting and TotemBar.notEnoughMana(cost, mana) then
        return "mana"
    end
    if cdStart and cdDuration and cdStart > 0 and cdDuration > (gcdMax or TotemBar.GCD_MAX) then
        return "cooldown"
    end
    return nil
end

-- The pre-cast verdict, stamped with the tick it was taken in. recordCast below
-- honours it only for the SAME element, the SAME totem and the SAME GetTime()
-- tick, so a stale verdict can never suppress a later, legitimate cast.
TotemBar.castBlock = nil

-- WoW-side snapshot taken immediately before the cast leaves. Reads the cached
-- tooltip mana cost, live mana, and the spell's own cooldown.
local function computeCastBlock(element, totemName)
    local cost = TotemBar.getTotemManaCost and TotemBar.getTotemManaCost(totemName)
    local mana = (type(UnitMana) == "function") and UnitMana("player") or nil
    local cdStart, cdDuration = nil, nil
    if type(GetSpellCooldown) == "function" and TotemBar.findSpellIndex then
        local idx = TotemBar.findSpellIndex(totemName)
        if idx then
            cdStart, cdDuration = GetSpellCooldown(idx, BOOKTYPE_SPELL)
        end
    end
    return TotemBar.castGateReason(cost, mana, cdStart, cdDuration,
        TotemBar.GCD_MAX, TotemBar.hasClearcasting and TotemBar.hasClearcasting())
end

-- This runs INSIDE the CastSpellByName hook, i.e. in front of every totem cast
-- the client makes -- including the first one for a totem, where the cost is
-- still unknown and getTotemManaCost scans a hidden tooltip. Wrapped so that
-- nothing in that chain (tooltip, spellbook scan, buff walk) can abort the cast
-- itself. A failure yields no verdict, which is the fail-open state this gate
-- has anyway whenever an input is unknown -- the cast proceeds and is tracked
-- exactly as it was before this feature existed.
function TotemBar.measureCastBlock(element, totemName)
    if not element or not totemName then
        return nil
    end
    local ok, reason = pcall(computeCastBlock, element, totemName)
    if not ok then
        reason = nil
    end
    if reason then
        TotemBar.castBlock = {
            element = element,
            name = totemName,
            at = GetTime(),
            reason = reason,
        }
    else
        -- Clear rather than leave: a verdict from an earlier cast in this same
        -- tick must not outlive the cast it belongs to.
        TotemBar.castBlock = nil
    end
    return reason
end

-- Records that `totemName` was just cast into `element`'s slot, into
-- TotemBar's own tracking table (see activeTotems above). Touches
-- GetTime(), a spellbook index/texture scan and (for Searing Totem) a
-- rank scan, so it isn't pure; called from both the bar's left-click
-- path (ui.lua) and castNext()/castAll() below.
--
-- Also stashes the totem spell's icon texture (rec.icon) and a
-- self-learning "did I ever see this totem's buff" flag
-- (rec.everHadBuff, starts false). ui.lua's out-of-range red-tint
-- feature is buff-presence based: a totem's party buff uses the SAME
-- icon texture as the totem spell itself (verified in-game), so
-- TotemBar.hasBuffWithIcon(rec.icon) tells whether the player is
-- currently benefiting from THIS cast totem.
function TotemBar.recordCast(element, totemName)
    if not element or not totemName then
        return
    end
    -- Refused before it left (see measureCastBlock): no timer, and -- like the
    -- unknown-totem guard below -- no castState.everCast either, since a cast
    -- that never happened is not evidence that anything is out.
    local blk = TotemBar.castBlock
    if blk and blk.reason and blk.element == element and blk.name == totemName
       and blk.at == GetTime() then
        return
    end
    local highestRank = nil
    if totemName == "Searing Totem" and TotemBar.highestKnownRank then
        highestRank = TotemBar.highestKnownRank(totemName)
    end
    local icon = nil
    local idx = TotemBar.findSpellIndex(totemName)
    if idx then
        icon = GetSpellTexture(idx, BOOKTYPE_SPELL)
    elseif TotemBar.spellbookEntryCount and TotemBar.spellbookEntryCount() > 0 then
        -- The spell is provably NOT in this character's spellbook, so the cast
        -- that just went out was a guaranteed no-op -- don't start a full-length
        -- phantom countdown (and a true anyTotemOut(), which then burns Totemic
        -- Recall's 6s cooldown on an empty board). Reachable because
        -- TotemBarDB is account-wide: a chosen set carried over from another
        -- shaman lands on an alt that hasn't learned those totems.
        -- Guarded on a NON-EMPTY spellbook scan on purpose: the index cache is
        -- built lazily and the book isn't reliably populated at login, so an
        -- empty scan means "no data", not "not known" -- fail OPEN there,
        -- exactly like confidentNoneOut's unknown-state policy below.
        return
    end
    local rec = {
        start = GetTime(),
        duration = TotemBar.durationWithMastery(
            TotemBar.totemDuration(totemName, highestRank),
            TotemBar.isHelpfulTotem(totemName),
            TotemBar.hasTotemicMastery and TotemBar.hasTotemicMastery()),
        totemName = totemName,
        icon = icon,
        everHadBuff = false,
        -- Latched by ui.lua once GetTotemInfo reports this slot active under
        -- this record's totem name; see TotemBar.rangeTintActive below.
        gtiTracked = false,
    }
    -- Kept for revokeRecentCast below: if this cast turns out to have been
    -- refused, the honest correction is the record as it was BEFORE the press,
    -- not an empty slot (a refused REPEAT press must not lose the still-running
    -- timer of the totem the first press placed).
    TotemBar.lastOverwritten = {
        element = element,
        rec = TotemBar.activeTotems[element],
        at = rec.start,
    }
    TotemBar.activeTotems[element] = rec
    -- Sticky session evidence for confidentNoneOut() below. Deliberately NOT
    -- derived from activeTotems' occupancy: ui.lua's timer tick evicts each
    -- record the moment it expires, and clearActiveTotems() wipes the table
    -- after every recall.
    TotemBar.castState.everCast = true
end

-- Records a totem cast caught by the universal CastSpellByName/CastSpell
-- hooks below, UNLESS TotemBar's own code already recorded this EXACT cast
-- this same GetTime() tick. Every TotemBar-exposed cast entry point
-- (bind.lua's CastTotem/CastElement, castNext/castAll/dropSetKey/
-- recallAndCastAll above, ui.lua's bar/flyout click handlers) already calls
-- TotemBar.recordCast() itself right after casting -- verified by a full
-- inventory of every Bindings.xml binding, the "Totems" macro, and every
-- click handler (2026-07-16): none of them skip it. So a hook firing for a
-- cast that ALSO went through one of those paths would otherwise
-- double-record in the same frame (harmless -- recordCast just overwrites
-- with a near-identical timestamp -- but trivially avoidable with this one
-- check, so it is).
function TotemBar.recordCastFromHook(element, totemName)
    local existing = TotemBar.activeTotems[element]
    if existing and existing.totemName == totemName and existing.start == GetTime() then
        return
    end
    TotemBar.recordCast(element, totemName)
end

-- ===== Revoking a timer a failure event proves wrong =====
--
-- Second line after the pre-cast gate, for refusals it cannot predict (the
-- server's own "no", or an element recovery too short to tell apart from the
-- GCD). The only source used is nampower's SPELL_FAILED_SELF, which carries the
-- SPELL ID -- so the failure can be tied to a specific totem.
--
-- Vanilla's SPELLCAST_FAILED and UI_ERROR_MESSAGE are deliberately NOT used:
-- both are global and carry no hint of which action failed (UI_ERROR_MESSAGE's
-- single arg is just the message text). During key spam a refused Lightning
-- Bolt would then delete the timer of a totem that is standing -- the classic
-- mis-attribution that hits every addon inferring its own outcome from those
-- two events. A missing timer is a worse failure than a phantom one, so
-- unattributable failures are ignored.

-- How long after a cast a failure can still belong to it.
TotemBar.CAST_FAIL_WINDOW = 0.4

-- Pure: the one element whose record was created inside the window, or nil if
-- that is ambiguous. A four-totem drop puts several records in the same window;
-- with no spell id to disambiguate, ANY pick would be a guess, and a wrong
-- guess deletes a standing totem's timer.
function TotemBar.soleRecentElement(activeTotems, elements, now, window)
    if not activeTotems then
        return nil
    end
    local found = nil
    for i = 1, table.getn(elements) do
        local element = elements[i]
        local rec = activeTotems[element]
        if rec and rec.start and (now - rec.start) <= window then
            if found then
                return nil          -- ambiguous: refuse to guess
            end
            found = element
        end
    end
    return found
end

-- Undoes the tracking of a cast that the client/server refused. `spellName` is
-- the failed totem's name when it could be resolved (exact pick, even with
-- several casts in flight); nil falls back to the sole-recent rule above.
--
-- Restores the record the refused press overwrote instead of clearing the slot
-- -- see TotemBar.lastOverwritten in recordCast.
function TotemBar.revokeRecentCast(spellName)
    local now = GetTime()
    local element = nil
    if spellName then
        for i = 1, table.getn(TotemBar.TOTEM_ELEMENTS) do
            local el = TotemBar.TOTEM_ELEMENTS[i]
            local rec = TotemBar.activeTotems[el]
            if rec and rec.totemName == spellName and rec.start
               and (now - rec.start) <= TotemBar.CAST_FAIL_WINDOW then
                element = el
            end
        end
    end
    if not element then
        element = TotemBar.soleRecentElement(TotemBar.activeTotems,
            TotemBar.TOTEM_ELEMENTS, now, TotemBar.CAST_FAIL_WINDOW)
    end
    if not element then
        return nil
    end
    local prev = TotemBar.lastOverwritten
    local restore = nil
    if prev and prev.element == element and prev.at == TotemBar.activeTotems[element].start then
        restore = prev.rec
    end
    TotemBar.activeTotems[element] = restore
    TotemBar.lastOverwritten = nil
    return element
end

-- ===== Universal cast hooks: catch totem casts from ANY path =====
-- Defense-in-depth for totems cast WITHOUT going through any TotemBar
-- function at all -- e.g. a hand-written macro's own `/cast Searing Totem`,
-- or another addon. Every path TotemBar itself exposes already calls
-- recordCast() (see recordCastFromHook's comment above) so this is a
-- safety net, not the primary fix for a "no countdown" report.
--
-- Fixed arity on purpose (project rule: no vararg closures) -- both globals
-- have a stable, known 1.12 signature: CastSpellByName(name, onSelf),
-- CastSpell(spellId, bookType).
--
-- Plain global reassignment, not hooksecurefunc -- pfUI provides
-- hooksecurefunc as its own polyfill (compat/vanilla.lua; native 1.12 has
-- no such function), and TotemBar must not hard-depend on pfUI being
-- loaded. Saving whatever function is CURRENTLY bound to the global and
-- calling it first (before doing our own extra work) composes correctly
-- with pfUI's own libtotem hook on CastSpellByName/CastSpell regardless of
-- addon load order: whichever wraps last just adds a layer on top of
-- whatever was already there.
--
-- UseAction is intentionally NOT hooked. 1.12 has no GetActionInfo /
-- GetActionSpellId to read a spell off an action-bar slot directly; pfUI's
-- own UseAction coverage (libtotem.lua) only works by scanning a hidden
-- GameTooltip:SetAction(slot) via its private libtipscan library, wired up
-- through hooksecurefunc -- both the tooltip-scan trick and hooksecurefunc
-- are pfUI-internal, not something TotemBar can reimplement without either
-- a hard pfUI dependency or a whole new action-slot tooltip scanner (this
-- file already has a spellbook-index tooltip scanner for mana costs, see
-- core/manacost.lua, but nothing that scans by action slot). Given every
-- TotemBar-native path already records, and pfUI's GetTotemInfo already
-- covers action-bar-dragged totem casts as the resolveRemaining/
-- resolveDuration fallback source when pfUI is present, this gap was
-- judged not worth the added dependency/complexity.
-- Both hooks measure the cast gate BEFORE calling through (see
-- measureCastBlock: afterwards the mana is spent and the GCD is running, so the
-- reading would accuse every successful cast). This placement also covers the
-- paths that record for themselves -- ui.lua's click handlers, castNext/castAll,
-- bind.lua -- because they all reach the client through these same globals, so
-- their own recordCast call sees the verdict too.
if type(CastSpellByName) == "function" then
    local origCastSpellByName = CastSpellByName
    CastSpellByName = function(name, onSelf)
        local element, baseName = TotemBar.elementFromCastName(name)
        if element then
            TotemBar.measureCastBlock(element, baseName)
        end
        origCastSpellByName(name, onSelf)
        if element then
            TotemBar.recordCastFromHook(element, baseName)
        end
    end
end

if type(CastSpell) == "function" then
    local origCastSpell = CastSpell
    CastSpell = function(spellId, bookType)
        local element, baseName = nil, nil
        if type(GetSpellName) == "function" then
            element, baseName = TotemBar.elementFromCastName(GetSpellName(spellId, bookType))
            if element then
                TotemBar.measureCastBlock(element, baseName)
            end
        end
        origCastSpell(spellId, bookType)
        if element then
            TotemBar.recordCastFromHook(element, baseName)
        end
    end
end

-- nampower's per-cast failure event (arg1 = spell id, arg2 = result, arg3 = 1
-- when the SERVER rejected it). It only fires with NP_EnableSpellFailedEvents
-- on, and nampower silently RETRIES some results (NP_RetryServerRejectedSpells,
-- default on: NOT_READY / ITEM_NOT_READY / SPELL_IN_PROGRESS), so those may
-- never arrive at all -- which is correct for us, since a retried cast that
-- lands really did place the totem.
--
-- Registering it costs nothing when nampower is absent (the event simply never
-- fires). The CVar is NOT set here: flipping a client-wide nampower switch is a
-- side effect on every other addon, and this is a safety net, not the primary
-- fix.
--
-- Guarded on CreateFrame so the file still loads under plain Lua for the tests.
if CreateFrame then
    local failFrame = CreateFrame("Frame", "TotemBarCastFailFrame", UIParent)
    failFrame:RegisterEvent("SPELL_FAILED_SELF")
    failFrame:SetScript("OnEvent", function()
        if event ~= "SPELL_FAILED_SELF" then
            return
        end
        -- Resolve the id to a name. SuperWoW's SpellInfo reads the client DBC;
        -- nampower ships its own lookup (and is what fired this event, so one
        -- of the two is normally there).
        local name = nil
        local id = arg1
        if id then
            if type(SpellInfo) == "function" then
                name = SpellInfo(id)
            elseif type(GetSpellNameAndRankForId) == "function" then
                name = GetSpellNameAndRankForId(id)
            end
            if name then
                name = TotemBar.stripRankSuffix(name)
            end
        end
        -- No name, no revoke. An unnamed failure could just as well be the
        -- Lightning Bolt the player pressed a moment after the totem, and
        -- acting on it would delete the timer of a totem that IS standing --
        -- the same mis-attribution UI_ERROR_MESSAGE is refused for above.
        if not name or not TotemBar.elementOf(name) then
            return
        end
        TotemBar.revokeRecentCast(name)
    end)
end

-- Module-scratch table for the buff-texture scan below, reused every
-- call (hasBuffWithIcon runs ~5x/sec, from ui.lua's throttled timer
-- tick) so it doesn't allocate a new table each time. buffScratchLen
-- tracks how far the previous scan filled it, so leftover entries past
-- the new scan's length get nilled out - keeping it a clean, hole-free
-- 1..n array (table.getn needs that to be reliable in Lua 5.0).
local buffScratch = {}
local buffScratchLen = 0

-- Pure: the final path component of a texture path, lowercased -- i.e. the
-- bare icon name. Keeps the case/prefix tolerance the comparison below needs
-- (GetSpellTexture and UnitBuff don't have to return identically-spelled
-- paths) without the false positives of a substring search.
local function textureTail(path)
    local s = string.lower(path)
    local _, sep = string.find(s, ".*[\\/]")
    if sep then
        return string.sub(s, sep + 1)
    end
    return s
end

-- Pure: given a flat array of buff texture path strings (some entries
-- may be nil) and a totem spell's icon texture path, returns true if
-- any buff's ICON NAME equals iconPath's, case-insensitively and
-- independent of the leading path. Returns false if iconPath or
-- buffTexList is nil, or nothing matches.
--
-- Compares the trailing path component for EQUALITY, not containment: a
-- substring search let any icon name that merely starts with the totem's
-- count as a match, and 1.12 ships exactly such a pair -- Windwall Totem is
-- Spell_Nature_EarthBind, Strength of Earth Totem is
-- Spell_Nature_EarthBindTotem. Carrying the Strength of Earth buff therefore
-- made Windwall look permanently in range, so its slot never turned red.
function TotemBar.buffTexturesMatch(buffTexList, iconPath)
    if not iconPath or not buffTexList then
        return false
    end
    local needle = textureTail(iconPath)
    for i = 1, table.getn(buffTexList) do
        local tex = buffTexList[i]
        if tex and textureTail(tex) == needle then
            return true
        end
    end
    return false
end

-- Thin WoW-API wrapper: scans the player's current buffs (UnitBuff
-- "player" 1..32, stopping at the first nil slot) into the reusable
-- buffScratch table, then hands it to the pure
-- TotemBar.buffTexturesMatch() above. This is the "am I in this totem's
-- range?" signal for ui.lua's red-tint feature: a totem's party buff
-- shares its spell's icon texture (verified in-game), so having a
-- matching buff means the totem is currently affecting the player.
function TotemBar.hasBuffWithIcon(iconPath)
    if not iconPath then
        return false
    end
    local n = 0
    for i = 1, 32 do
        local tex = UnitBuff("player", i)
        if not tex then
            break
        end
        n = n + 1
        buffScratch[n] = tex
    end
    for i = n + 1, buffScratchLen do
        buffScratch[i] = nil
    end
    buffScratchLen = n
    return TotemBar.buffTexturesMatch(buffScratch, iconPath)
end

-- Clears every own-tracked totem timer at once (e.g. after Totemic
-- Recall, which drops all active totems simultaneously).
function TotemBar.clearActiveTotems()
    for i = 1, table.getn(TotemBar.TOTEM_ELEMENTS) do
        TotemBar.activeTotems[TotemBar.TOTEM_ELEMENTS[i]] = nil
    end
end

-- Is at least one totem currently out? Used to avoid wasting Totemic Recall's
-- own 6-second cooldown on a no-op cast: recalling with nothing out still puts
-- Recall on cooldown, so a fresh set placed right after can't be recalled for
-- 6s. Permissive on purpose - returns true if EITHER our own cast-tracking OR
-- GetTotemInfo (pfUI libtotem / SuperWoW, when present) reports a totem out, so
-- a legitimate recall is never wrongly blocked; only when both agree nothing is
-- out do we suppress the cast.
function TotemBar.anyTotemOut()
    if TotemBar.anyActiveTracked(TotemBar.activeTotems, TotemBar.TOTEM_ELEMENTS,
                                 GetTime(), TotemBar.remaining) then
        return true
    end
    if GetTotemInfo then
        for slot = 1, 4 do
            if GetTotemInfo(slot) then
                return true
            end
        end
    end
    return false
end

-- pure: does the addon currently hold ANY tracked totem record (regardless of expiry)?
-- NOTE: this is NOT the recall gate's session evidence any more -- see
-- confidentNoneOut below. Table occupancy cannot answer "did we cast something this
-- session": ui.lua's 0.1s timer tick EVICTS each record the moment it expires, and
-- clearActiveTotems() wipes the whole table after every recall.
function TotemBar.hasTrackedTotems(activeTotems, elements)
    if not activeTotems then return false end
    for i = 1, table.getn(elements) do
        if activeTotems[elements[i]] then return true end
    end
    return false
end

-- Should the manual-recall gate BLOCK the recall? Only when we are CONFIDENT that nothing
-- is out: we have tracked at least one totem THIS session AND all tracked totems have
-- expired. When tracking is empty (fresh load, or after a /reload -- activeTotems is
-- in-memory only and reset on load) the state is UNKNOWN, not "none out": on 1.12 there is
-- no GetTotemInfo / no "totemN" UnitID to re-detect a totem that was cast BEFORE the reload
-- (KG-confirmed 2026-07-14 -- no reload-proof detection exists for all totem types). So in
-- the unknown case FAIL OPEN -- let the recall through rather than falsely reporting "no
-- totems out" and blocking a legitimate recall of a still-standing totem (the bug this fixes:
-- our reloads wiped the tracking while the totems stayed physically out). Worst case of
-- fail-open is one needless recall right after a reload -- far cheaper than a blocked one.
--
-- The "cast something this session" half reads the STICKY castState.everCast flag set in
-- recordCast, not the occupancy of activeTotems. Occupancy was the original evidence and it
-- was wrong: ui.lua's 0.1s tick deletes a record the moment it expires and clearActiveTotems()
-- empties the table after every recall, so the gate fell open again ~0.1s after the last totem
-- ran out -- it only ever blocked while the bar was HIDDEN (hidden frame, no OnUpdate, no
-- eviction), the exact inverse of the intent above. castState is in-memory like activeTotems,
-- so a /reload still resets it to the fail-open state.
function TotemBar.confidentNoneOut()
    if not TotemBar.castState.everCast then
        return false
    end
    return not TotemBar.anyTotemOut()
end

-- Casts exactly ONE totem per call: the next slot in Fire -> Earth ->
-- Water -> Air order, skipping empty (unassigned) slots. If more than
-- gapSeconds has passed since the previous call, the cycle restarts at
-- the first filled slot (so a fresh spam always begins with totem 1).
--
-- Intended for a macro: `/script TotemBar.castNext()`
function TotemBar.castNext()
    local db = TotemBarDB
    local chosen = (db and db.chosen) or {}
    local gap = (db and db.gapSeconds) or TotemBar.DEFAULT_GAP_SECONDS
    local elements = TotemBar.TOTEM_ELEMENTS
    local numSlots = table.getn(elements)
    local now = GetTime()

    local state = TotemBar.castState
    local startIdx = TotemBar.nextIndex(state.index, state.lastTime, now, gap, numSlots)
    local slot = TotemBar.findFilledSlot(chosen, elements, startIdx)

    if not slot then
        -- Nothing assigned to any element; nothing to cast.
        state.index = 0
        state.lastTime = now
        return nil, nil
    end

    local element = elements[slot]
    local totemName = chosen[element]
    CastSpellByName(totemName)
    TotemBar.recordCast(element, totemName)
    state.index = slot
    state.lastTime = now
    return totemName, element
end

-- Casts ALL filled slots in a single call (Fire -> Earth -> Water ->
-- Air). On TurtleWoW each totem element has its own cooldown, so this
-- MAY drop all four from one keypress. Whether 4 CastSpellByName calls
-- in one Lua frame all land (vs only the last "winning") is unverified
-- on this client -- offered as a one-press alternative to castNext() to
-- test in-game.
--
-- Intended for a macro: `/script TotemBar.castAll()`
function TotemBar.castAll()
    local db = TotemBarDB
    local chosen = (db and db.chosen) or {}
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        local element = elements[i]
        local totemName = chosen[element]
        if totemName then
            CastSpellByName(totemName)
            TotemBar.recordCast(element, totemName)
        end
    end
end

-- Pure: should recallAndCastAll fire Totemic Recall this call?
--   autoRecall off              -> false (never recall)
--   never deployed (nil / <=0)  -> true  (nothing fresh to protect)
--   last deploy > guard ago     -> true
--   last deploy within guard    -> false (protect just-placed totems from a
--                                  rapid accidental second press)
function TotemBar.shouldRecall(autoRecall, lastDeployTime, now, guardSeconds)
    if not autoRecall then
        return false
    end
    if not lastDeployTime or lastDeployTime <= 0 then
        return true
    end
    if not guardSeconds then
        return true
    end
    if (now - lastDeployTime) > guardSeconds then
        return true
    end
    return false
end

-- Casts Totemic Recall bypassing nampower's spell queue when that API is
-- present. Root cause of the "place a set, it vanishes a moment later" bug:
-- under nampower, a plain CastSpellByName of Totemic Recall (a GCD-tied
-- instant) issued while a GCD is active is QUEUED, not cast, and pops at
-- GCD-end -- by which time the totems are already down (TWoW gives each totem
-- element its own non-GCD recovery category, so the 4 totems fire immediately
-- with queue priority). The late Recall then sweeps the fresh set. Bypassing
-- the queue means a GCD-blocked Recall simply fails that press instead of
-- being deferred, so it can never fire late and tear the totems down. Falls
-- back to a plain cast when nampower isn't installed (the function is nil).
-- (KG: NP_QueueInstantSpells default 1 is the deferral; CastSpellByNameNoQueue
-- is nampower's queue-bypass cast.)
local function castRecallNoQueue()
    if type(CastSpellByNameNoQueue) == "function" then
        CastSpellByNameNoQueue(RECALL_SPELL_NAME)
    else
        CastSpellByName(RECALL_SPELL_NAME)
    end
end

-- pure: does GetSpellCooldown's (start, duration) pair describe a cooldown
-- that is RUNNING right now? 1.12 reports a live cooldown as start > 0 AND
-- duration > 0. It reports the GLOBAL cooldown here too for a GCD-tied spell
-- like Totemic Recall, which is exactly what we want: castRecallNoQueue above
-- deliberately does not queue, so a GCD-blocked press simply fails -- treating
-- it as "cannot cast" keeps this check honest about what the client will do.
--
-- Missing data (nil) means "no cooldown information", never "on cooldown" --
-- FAIL OPEN, so an unreadable cooldown can never block a legitimate recall
-- (same policy as confidentNoneOut above).
function TotemBar.cooldownActive(start, duration)
    if not start or not duration then
        return false
    end
    return start > 0 and duration > 0
end

-- Can Totemic Recall actually be cast right now? Reads the live cooldown via
-- the shared spellbook index cache (core/spellindex.lua). Unknowns fail OPEN --
-- no GetSpellCooldown, no index cache at all -- so an unreadable cooldown can
-- never block a legitimate recall.
--
-- "Not in the book" is deliberately NOT an unknown: it is only unknown while
-- the scan itself is unusable. A nil index against a NON-EMPTY cached scan is
-- KNOWN state -- the spell cannot be cast, so a press cannot have gone out --
-- and failing open there was the same evidence-destroying bug this function
-- exists to prevent: a shaman below level 30 has not learned Totemic Recall
-- (learned at 30), so every press returned "cast", ran clearActiveTotems() on a
-- still-standing set and left confidentNoneOut() saying "confidently nothing
-- out" -- the fail-CLOSED state that gate forbids. Same non-empty-scan idiom as
-- recordCast above: the book is not reliably populated at login and the cache
-- is built lazily, so an EMPTY scan means "no data", not "not known".
function TotemBar.recallReady()
    if type(GetSpellCooldown) ~= "function" or not TotemBar.findSpellIndex then
        return true
    end
    local idx = TotemBar.findSpellIndex(RECALL_SPELL_NAME)
    if not idx then
        return not (TotemBar.spellbookEntryCount and TotemBar.spellbookEntryCount() > 0)
    end
    return not TotemBar.cooldownActive(GetSpellCooldown(idx, BOOKTYPE_SPELL))
end

-- pure: what should a MANUAL Totemic Recall press do?
--   "none-out"  the gate is confident nothing is out -> skip the cast, saving
--               Totemic Recall's 6s cooldown.
--   "cooldown"  Recall is not castable right now (its own 6s cooldown, a GCD,
--               or never learned -- see recallReady) -> skip the cast AND keep
--               the own-tracking. A recall that cannot have gone out must never
--               destroy the evidence that the totems are still standing: the
--               tracking is one half of confidentNoneOut's gate while
--               castState.everCast (the other half) is sticky for the whole
--               session, so wiping it on a refused press left the gate saying
--               "confidently nothing out" with a full set on the ground --
--               fail-CLOSED, the one outcome confidentNoneOut forbids.
--   "cast"      cast it.
--
-- The override exists for the same reason: any state where a totem is out but
-- UNTRACKED still trips the gate -- e.g. a totem dropped from the action bar
-- on a client without pfUI's GetTotemInfo (1.12 cannot read an action slot's
-- spell, see the UseAction note above). So the gate is never a dead end: a
-- DELIBERATE re-press after a blocked one lets the recall through. The
-- overrideMin/Max window separates that from an accidental double-click and
-- expires the override again for the next, unrelated press.
function TotemBar.manualRecallAction(noneOut, ready, lastBlockedAt, now, overrideMin, overrideMax)
    if noneOut then
        local override = false
        if lastBlockedAt and overrideMin and overrideMax then
            local since = now - lastBlockedAt
            override = (since >= overrideMin) and (since <= overrideMax)
        end
        if not override then
            return "none-out"
        end
    end
    if not ready then
        return "cooldown"
    end
    return "cast"
end

-- The ONE manual-recall implementation, shared by the Recall button's
-- left-click (ui.lua) and the TOTEMBAR_RECALL keybind (bind.lua) so the two
-- can never drift apart again. Returns the action taken ("none-out" /
-- "cooldown" / "cast"); the callers own the chat feedback.
--
-- Casts through castRecallNoQueue exactly like the auto paths: a plain
-- CastSpellByName here was queueable under nampower, so a manual press during
-- a GCD could pop AFTER the next set was placed and sweep it away -- the very
-- teardown that helper exists to prevent.
function TotemBar.manualRecall()
    local now = GetTime()
    local noneOut = TotemBar.confidentNoneOut and TotemBar.confidentNoneOut()
    local action = TotemBar.manualRecallAction(noneOut, TotemBar.recallReady(),
        TotemBar.castState.recallBlockedAt, now,
        TotemBar.RECALL_OVERRIDE_MIN, TotemBar.RECALL_OVERRIDE_MAX)

    if action == "none-out" then
        -- Remember the refusal so a deliberate re-press can override it.
        TotemBar.castState.recallBlockedAt = now
        return action
    end
    if action == "cooldown" then
        -- Deliberately KEEPS recallBlockedAt: this press was refused by the
        -- client, not by the gate, so an override the player already expressed
        -- must survive a transient cooldown/GCD instead of costing them another
        -- paired press once it clears.
        return action
    end

    TotemBar.castState.recallBlockedAt = nil
    castRecallNoQueue()
    -- The refund learner's snapshot runs AFTER the cast but BEFORE the wipe:
    -- it sums the cost of the totems still held in activeTotems.
    if TotemBar.snapshotRecallCost then TotemBar.snapshotRecallCost() end
    -- Totemic Recall drops every active totem at once; clear own-tracking so
    -- the icons' countdowns disappear too (GetTotemInfo, if present, will also
    -- reflect this).
    TotemBar.clearActiveTotems()
    return action
end

-- Recall-then-deploy: when TotemBarDB.autoRecall is on (the default -
-- toggleable via the Recall button's right-click, see ui.lua), casts
-- Totemic Recall FIRST (drops existing totems and refunds some mana)
-- and clears own-tracking, then always places all filled slots via
-- castAll(). One keypress = recall + redeploy (or just redeploy, with
-- the flag off). Like castAll, relies on TurtleWoW allowing several
-- CastSpellByName calls in one Lua frame -- verify in-game.
--
-- Guarded against rapid double-presses: shouldRecall() only fires Recall
-- if the last deploy was more than DEFAULT_RECALL_GUARD seconds ago. A
-- fast accidental second press then just re-attempts placement (a no-op,
-- since the totems are still up and each element is on its own ~1.5s
-- cooldown) instead of recalling the totems that were just placed.
--
-- Also gated on recallReady(): a Recall the client cannot cast right now (its
-- own 6s cooldown, or a GCD -- castRecallNoQueue never defers, so such a press
-- just fails) must not run clearActiveTotems() either, or it wipes the timers
-- of totems that are still standing.
--
-- Intended for a macro: `/script TotemBar.recallAndCastAll()`
function TotemBar.recallAndCastAll()
    local now = GetTime()
    local autoRecall = TotemBarDB and TotemBarDB.autoRecall
    local guard = (TotemBarDB and TotemBarDB.recallGuardSeconds) or TotemBar.DEFAULT_RECALL_GUARD
    if TotemBar.shouldRecall(autoRecall, TotemBar.castState.lastDeployTime, now, guard)
       and TotemBar.recallReady() and TotemBar.anyTotemOut() then
        castRecallNoQueue()
        TotemBar.clearActiveTotems()
    end
    TotemBar.castAll()
    TotemBar.castState.lastDeployTime = now
end

-- Key-down/key-up split for the DropSet keybind. Bound in Bindings.xml with
-- runOnUp="true", so this runs on BOTH flanks with the global `keystate` set
-- to "down" / "up" beforehand. Casting Totemic Recall on the DOWN stroke and
-- placing the set on the RELEASE. The real fix for the teardown is
-- castRecallNoQueue() (see above) -- bypassing nampower's queue so a
-- GCD-blocked Recall never fires late and sweeps the fresh set. The down/up
-- split adds belt-and-suspenders temporal separation: the Recall on the down
-- stroke has definitively resolved-or-failed (it is never queued) by the time
-- the release places the set. Both flanks are real hardware events, so both
-- may cast (Blizzard's own ActionButtonUp casts on release too), unlike a
-- timer-deferred placement which this client blocks as a non-hardware cast.
--
-- Still guarded by shouldRecall()'s 2s window (a rapid re-press within the
-- guard skips the Recall so it can't pull the just-placed set). keystate is
-- nil only if the binding ran without runOnUp (misconfig / older client);
-- treat nil like "up" so a single fire at least still PLACES rather than
-- silently doing nothing.
function TotemBar.dropSetKey(keystate)
    if keystate == "down" then
        local now = GetTime()
        local autoRecall = TotemBarDB and TotemBarDB.autoRecall
        local guard = (TotemBarDB and TotemBarDB.recallGuardSeconds) or TotemBar.DEFAULT_RECALL_GUARD
        if TotemBar.shouldRecall(autoRecall, TotemBar.castState.lastDeployTime, now, guard)
           and TotemBar.recallReady() and TotemBar.anyTotemOut() then
            castRecallNoQueue()
            TotemBar.clearActiveTotems()
        end
    else
        -- Release (or nil fallback): place the set now, in this hardware frame.
        TotemBar.castAll()
        TotemBar.castState.lastDeployTime = GetTime()
    end
end

-- Dev aid (/tb tdump): dumps TotemBar's own per-element cast-tracking
-- (TotemBar.activeTotems, the resolveRemaining/resolveDuration own-tracking
-- fallback source, see this file's header comment) side by side with the
-- RAW GetTotemInfo(1..4) (pfUI libtotem, when present -- the OTHER,
-- normally-authoritative source), so a "countdown missing" report can be
-- diagnosed off-client without an in-game screenshot: did TotemBar ever
-- record this cast at all, and what does GTI say about the same slot right
-- now? Also appends ui.lua's TotemBar.DumpRingRenderState() output (2026-07-
-- 16, Searing-ring bug: countdown TEXT shows but no pulse RING) -- the pure
-- ring math was already proven correct offline, so this section captures
-- the WoW-side render state instead: cached ring flags plus the LIVE
-- ringFill/ringTrack texture objects (shown/texture/alpha/texCoord/parent),
-- see that function's own comment for the full field list. Written to
-- <WoW>\imports\tb_tdump.txt via SuperWoW's ExportFile (name WITHOUT
-- the .txt extension -- ExportFile appends it itself); chat fallback when
-- SuperWoW isn't present. GetTotemInfo is pcall-wrapped since it's
-- third-party (pfUI) code this dump must never itself error on.
function TotemBar.DumpTimerState()
    local now = GetTime()
    local els = TotemBar.TOTEM_ELEMENTS
    local activeTotems = TotemBar.activeTotems
    local out = "TotemBar timer-state dump (now=" .. tostring(now) .. ")\n"

    out = out .. "\n-- own tracking (TotemBar.activeTotems) --\n"
    for i = 1, table.getn(els) do
        local element = els[i]
        local rec = activeTotems[element]
        if rec then
            local rem = TotemBar.remaining(rec.start, rec.duration, now)
            out = out .. element .. ": spell='" .. tostring(rec.totemName) .. "'"
                .. " start=" .. tostring(rec.start)
                .. " duration=" .. tostring(rec.duration)
                .. " remaining=" .. tostring(rem) .. "\n"
        else
            out = out .. element .. ": (no record)\n"
        end
    end

    out = out .. "\n-- raw GetTotemInfo(1..4) (pfUI libtotem, when present) --\n"
    if type(GetTotemInfo) == "function" then
        for slot = 1, 4 do
            local ok, active, name, start, duration = pcall(GetTotemInfo, slot)
            if ok then
                out = out .. "slot " .. slot .. ": active=" .. tostring(active)
                    .. " name='" .. tostring(name) .. "'"
                    .. " start=" .. tostring(start)
                    .. " duration=" .. tostring(duration) .. "\n"
            else
                out = out .. "slot " .. slot .. ": pcall error: " .. tostring(active) .. "\n"
            end
        end
    else
        out = out .. "(GetTotemInfo not present -- no pfUI libtotem loaded)\n"
    end

    -- Render-state section (ui.lua): the pure timer/duration/ring math
    -- above was already proven correct offline for the Searing-ring
    -- report (text shows, no ring) -- this is the other half, the
    -- WoW-side render state (cached ring flags + LIVE texture objects)
    -- that this dump previously never captured. pcall-wrapped: ui.lua
    -- loads after this file (see TotemBar.toc), but by the time a player
    -- runs /tb tdump everything is loaded; the guard just keeps this dump
    -- from erroring if that ever isn't true (e.g. a future load-order
    -- change) or if TotemBar.DumpRingRenderState itself hits something
    -- unexpected.
    local okRender, renderOut = pcall(TotemBar.DumpRingRenderState)
    if okRender and renderOut then
        out = out .. renderOut
    else
        out = out .. "\n-- render state: unavailable (" .. tostring(renderOut) .. ") --\n"
    end

    if ExportFile then
        ExportFile("tb_tdump", out)
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("TotemBar: tdump exported.")
    end
end
