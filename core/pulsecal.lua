-- TotemBar - core/pulsecal.lua
-- Dev-only pulse-calibration telemetry (/tb pulsecal): captures raw
-- totem-related combat lines + our own placements into a fixed ring buffer
-- and exports them via SuperWoW ExportFile, so the dev environment can
-- measure REAL TurtleWoW pulse intervals offline and bake them back into
-- core/pulsedata.lua (verified=true).
-- Pure buffer/serializer on top (offline-tested); WoW-gated capture below.

TotemBar = TotemBar or {}

TotemBar.PULSECAL_CAP = 2000

-- Dev-only diagnostic probe (/tb tprobe) for the destroyed-totem GUID-latch
-- paths in core/cast.lua ("Destroyed-totem detection (GUID liveness)"). Built
-- because two in-game measurement attempts against those latch paths were
-- both silently wiped by a /reload before their taps could be read (see
-- 2026-08-19/20 session) -- unlike pulsecal above (start, drop totems, dump
-- once by hand), this probe survives /reload on its own: it re-exports its
-- WHOLE ring buffer after every kept event (not only on demand) and re-arms
-- itself from TotemBarDB.tprobeArmed at ADDON_LOADED (see the WoW-gated
-- section below). Shares pulsecalPush/pulsecalFormat above for the ring
-- buffer itself -- only the filter and the per-line detail string are new.
TotemBar.TPROBE_CAP = 300

-- Pure: push one record into the ring buffer. state = { n = total pushed,
-- idx = next write slot 1..cap }. Record tables are REUSED on wrap (no
-- allocation growth while capturing).
function TotemBar.pulsecalPush(buf, cap, state, t, ev, msg)
    local slot = state.idx
    local rec = buf[slot]
    if not rec then
        rec = {}
        buf[slot] = rec
    end
    rec.t = t
    rec.e = ev
    rec.m = msg
    state.n = state.n + 1
    state.idx = slot + 1
    if state.idx > cap then
        state.idx = 1
    end
end

-- Pure: serialize surviving records in chronological order, one
-- "t;event;msg" line each (t with millisecond precision). Allocates - dump
-- time only, never per capture.
function TotemBar.pulsecalFormat(buf, cap, state)
    local count = state.n
    if count > cap then
        count = cap
    end
    if count == 0 then
        return ""
    end
    local start = state.idx - count
    if start < 1 then
        start = start + cap
    end
    local lines = {}
    for i = 0, count - 1 do
        local slot = start + i
        if slot > cap then
            slot = slot - cap
        end
        local rec = buf[slot]
        lines[i + 1] = string.format("%.3f;%s;%s", rec.t, rec.e, rec.m)
    end
    return table.concat(lines, "\n")
end

-- ===== /tb tprobe -- pure filter + line-builder (offline-tested) =====

-- Pure: does `name` look like a totem to a plain substring eye -- "Totem" or
-- "Searing" (the latter because Searing Totem's own pulse-cast spell is
-- suspected to be named "Searing Bolt"/"Attack" rather than "Searing Totem",
-- suspicion (a) in the probe's own brief -- a name check that only looked
-- for "Totem" would silently drop exactly the lines needed to confirm or
-- kill that suspicion). Case-sensitive plain substring, same convention the
-- WoW-gated capture below (and pulsecal's own filter above) already uses --
-- not a design decision unique to this function. nil-safe.
function TotemBar.tprobeNameHit(name)
    if not name then
        return false
    end
    if string.find(name, "Totem", 1, true) then
        return true
    end
    if string.find(name, "Searing", 1, true) then
        return true
    end
    return false
end

-- Events always kept regardless of name (a death is diagnostic on its own --
-- there is no "name" to filter on for CHAT_MSG_COMBAT_*_DEATH, and UNIT_DIED
-- firing for something that never matched a totem name is itself evidence,
-- e.g. against suspicion (b)/(c) in the probe's brief).
local TPROBE_ALWAYS_EVENTS = {
    UNIT_DIED = true,
    CHAT_MSG_COMBAT_FRIENDLY_DEATH = true,
    CHAT_MSG_COMBAT_HOSTILE_DEATH = true,
}

-- Pure: should this event be kept? nameUnit is UnitName(arg1) as resolved by
-- the caller, nameSpell is SpellInfo(arg4) -- kept if EITHER hits
-- tprobeNameHit, or if the event is one of TPROBE_ALWAYS_EVENTS above.
function TotemBar.tprobeShouldKeep(event, nameUnit, nameSpell)
    if event and TPROBE_ALWAYS_EVENTS[event] then
        return true
    end
    if TotemBar.tprobeNameHit(nameUnit) then
        return true
    end
    if TotemBar.tprobeNameHit(nameSpell) then
        return true
    end
    return false
end

-- Pure: the "msg" half of one kept line (the ring buffer's "t;event;msg"
-- shape from pulsecalPush/pulsecalFormat above supplies t and event already).
-- nameUnit and nameSpell are BOTH kept, deliberately never collapsed into a
-- single "resolved name" -- the whole point of the probe is to see whether
-- they AGREE (suspicion (a): does a Searing Totem pulse's SpellInfo name
-- ever equal "Searing Totem" at all?). Every argument may be nil; tostring()
-- turns that into the literal string "nil", never a concat error.
function TotemBar.tprobeBuildDetail(a1, a2, a3, a4, nameUnit, nameSpell, ownerName, health, latched)
    return "a1=" .. tostring(a1)
        .. ";a2=" .. tostring(a2)
        .. ";a3=" .. tostring(a3)
        .. ";a4=" .. tostring(a4)
        .. ";nameUnit=" .. tostring(nameUnit)
        .. ";nameSpell=" .. tostring(nameSpell)
        .. ";owner=" .. tostring(ownerName)
        .. ";hp=" .. tostring(health)
        .. ";latched=" .. tostring(latched)
end

-- Pure: would the PRODUCTIVE handler (core/cast.lua's guidFrame) have
-- latched a GUID for this event's totem, and what does that element's
-- record show right now? nameUnit is tried first (arg1's own UnitName --
-- the identity the productive UNIT_MODEL_CHANGED path itself keys off),
-- nameSpell as a fallback (a totem that only ever surfaces through a SPELL
-- name elementOfFn doesn't recognise -- e.g. "Searing Bolt" -- correctly
-- resolves to nil here, which is itself the diagnostic: the productive
-- UNIT_CASTEVENT path (core/cast.lua's TotemBar.elementFromCastName) has
-- exactly the same blind spot). activeTotems/elementOfFn are injected (same
-- dependency-injection convention core/cast.lua's own TotemBar.elementForGuid
-- uses) so this needs no WoW globals to test. Returns nil both when no
-- element matches AND when the matched element's record has no guid yet --
-- either way there is no guid to report, matching the brief's own
-- "latched=<guid|nil>" literally.
function TotemBar.tprobeLatchedGuid(activeTotems, elementOfFn, nameUnit, nameSpell)
    if not elementOfFn then
        return nil
    end
    local element = elementOfFn(nameUnit) or elementOfFn(nameSpell)
    if not element or not activeTotems then
        return nil
    end
    local rec = activeTotems[element]
    if not rec then
        return nil
    end
    return rec.guid
end

-- ---------------------------------------------------------------------------
-- WoW-gated capture (skipped entirely by the offline test runner).
if CreateFrame then
    local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

    local capturing = false
    local buf = {}
    local state = { n = 0, idx = 1 }

    -- Everything that could plausibly carry a totem pulse on 1.12 (no
    -- COMBAT_LOG_EVENT_UNFILTERED here - all localized text in arg1).
    local CAPTURE_EVENTS = {
        "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
        "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",
        "CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS",
        "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
        "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
        "CHAT_MSG_SPELL_SELF_DAMAGE",
        "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
        "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
        "CHAT_MSG_SPELL_AURA_GONE_SELF",
        "CHAT_MSG_SPELL_AURA_GONE_PARTY",
    }

    local calFrame = CreateFrame("Frame", "TotemBarPulseCalFrame", UIParent)
    calFrame:SetScript("OnEvent", function()
        if not capturing then
            return
        end
        if event == "UNIT_CASTEVENT" then
            -- SuperWoW: casterGUID, targetGUID, type, spellId, castTime.
            -- Only record casts whose spell name mentions Totem (SpellInfo
            -- is a SuperWoW API; guarded because the event only exists there
            -- anyway). arg4 is guarded too (adversarial review, 2026-08-19
            -- destroyed-totem session) -- SpellInfo(nil) is unproven safe on
            -- this client, and a UNIT_CASTEVENT with no spellId is possible
            -- in principle (e.g. a non-cast event type on this arg3 slot).
            local sname = (SpellInfo and arg4) and SpellInfo(arg4)
            if sname and string.find(sname, "Totem", 1, true) then
                TotemBar.pulsecalPush(buf, TotemBar.PULSECAL_CAP, state, GetTime(), event,
                    tostring(arg1) .. ";" .. tostring(arg3) .. ";" .. tostring(sname))
            end
            return
        end
        -- Plain substring guard keeps the hot path cheap; "Totem"-less buff
        -- names (Mana Spring / Healing Stream gain lines) are the exception,
        -- so include the "You gain" prefix too.
        local msg = arg1
        if msg and (string.find(msg, "Totem", 1, true) or string.find(msg, "You gain", 1, true)) then
            TotemBar.pulsecalPush(buf, TotemBar.PULSECAL_CAP, state, GetTime(), event, msg)
        end
    end)

    -- Record our own placements as reference marks (t0 for interval math).
    -- Wrapping recordCast is safe here: core/pulsecal.lua loads AFTER
    -- core/cast.lua (see .toc) and ui.lua resolves TotemBar.recordCast at
    -- call time.
    local origRecordCast = TotemBar.recordCast
    TotemBar.recordCast = function(element, totemName)
        origRecordCast(element, totemName)
        if capturing then
            TotemBar.pulsecalPush(buf, TotemBar.PULSECAL_CAP, state, GetTime(),
                "TB_PLACED", tostring(element) .. ";" .. tostring(totemName))
        end
    end

    function TotemBar.PulseCal(sub)
        if sub == "start" then
            if not capturing then
                capturing = true
                for i = 1, table.getn(CAPTURE_EVENTS) do
                    calFrame:RegisterEvent(CAPTURE_EVENTS[i])
                end
                -- SuperWoW-only event; pcall-guarded in case a client build
                -- rejects unknown event names.
                pcall(function() calFrame:RegisterEvent("UNIT_CASTEVENT") end)
            end
            ChatOut:AddMessage("TotemBar: pulsecal capture STARTED (drop totems, then /tb pulsecal dump).")
        elseif sub == "stop" then
            capturing = false
            calFrame:UnregisterAllEvents()
            ChatOut:AddMessage("TotemBar: pulsecal capture stopped (" .. state.n .. " records kept).")
        elseif sub == "dump" then
            if not ExportFile then
                ChatOut:AddMessage("TotemBar: pulsecal dump needs SuperWoW (ExportFile missing).")
                return
            end
            -- Filename WITHOUT extension - the client appends .txt itself.
            ExportFile("totembar_pulsecal", TotemBar.pulsecalFormat(buf, TotemBar.PULSECAL_CAP, state))
            ChatOut:AddMessage("TotemBar: pulsecal dump written (imports\\totembar_pulsecal.txt, "
                .. state.n .. " records).")
        else
            local on = capturing and "ON" or "OFF"
            ChatOut:AddMessage("TotemBar: pulsecal " .. on .. ", " .. state.n
                .. " records. Usage: /tb pulsecal start|stop|dump")
        end
    end

    -- ===== /tb tprobe -- reload-survivable diagnostic probe =====
    -- Pure observation only: never touches TotemBar.activeTotems or any
    -- other productive state, only READS TotemBar.activeTotems/elementOf to
    -- report what the productive handler would have seen (see
    -- tprobeLatchedGuid above).
    local tprobeCapturing = false
    local tprobeBuf = {}
    local tprobeState = { n = 0, idx = 1 }

    local function tprobeExport()
        if ExportFile then
            -- Filename WITHOUT extension - the client appends .txt itself.
            ExportFile("tb_tprobe", TotemBar.pulsecalFormat(tprobeBuf, TotemBar.TPROBE_CAP, tprobeState))
        end
    end

    -- Takes explicit args (not the WoW globals directly) so the pcall below
    -- wraps a real function value, not a closure built fresh every event.
    local function tprobeHandleEvent(ev, a1, a2, a3, a4)
        local nameUnit = nil
        if a1 and type(UnitName) == "function" then
            nameUnit = UnitName(a1)
        end
        local nameSpell = nil
        if a4 and type(SpellInfo) == "function" then
            nameSpell = SpellInfo(a4)
        end
        if not TotemBar.tprobeShouldKeep(ev, nameUnit, nameSpell) then
            return
        end
        local ownerName = nil
        if a1 and type(UnitName) == "function" then
            ownerName = UnitName(a1 .. "owner")
        end
        local health = nil
        if a1 and type(UnitHealth) == "function" then
            health = UnitHealth(a1)
        end
        local latched = TotemBar.tprobeLatchedGuid(TotemBar.activeTotems, TotemBar.elementOf, nameUnit, nameSpell)
        local detail = TotemBar.tprobeBuildDetail(a1, a2, a3, a4, nameUnit, nameSpell, ownerName, health, latched)
        TotemBar.pulsecalPush(tprobeBuf, TotemBar.TPROBE_CAP, tprobeState, GetTime(), ev, detail)
        -- Export on EVERY kept event, not only on /tb tprobe dump - the
        -- whole reason this probe exists is that two earlier measurement
        -- attempts were wiped by a /reload before a manual dump could run.
        tprobeExport()
    end

    local tprobeFrame = CreateFrame("Frame", "TotemBarTProbeFrame", UIParent)
    tprobeFrame:SetScript("OnEvent", function()
        if not tprobeCapturing then
            return
        end
        -- pcall-wrapped end to end (per spec): observation must never be
        -- able to break anything else this client does.
        pcall(tprobeHandleEvent, event, arg1, arg2, arg3, arg4)
    end)

    local function tprobeArm()
        if tprobeCapturing then
            return
        end
        tprobeCapturing = true
        -- Native 1.12 events, safe to register directly.
        tprobeFrame:RegisterEvent("UNIT_MODEL_CHANGED")
        tprobeFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
        tprobeFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
        -- SuperWoW/nampower-only events; pcall-guarded exactly like
        -- calFrame's own UNIT_CASTEVENT registration above.
        pcall(function() tprobeFrame:RegisterEvent("UNIT_CASTEVENT") end)
        pcall(function() tprobeFrame:RegisterEvent("UNIT_DIED") end)
    end

    local function tprobeDisarm()
        tprobeCapturing = false
        tprobeFrame:UnregisterAllEvents()
    end

    function TotemBar.TProbe(sub)
        if sub == "on" then
            tprobeArm()
            if TotemBarDB then
                TotemBarDB.tprobeArmed = true
            end
            ChatOut:AddMessage("TotemBar: tprobe capture STARTED (" .. tprobeState.n .. " records kept so far).")
        elseif sub == "off" then
            tprobeDisarm()
            if TotemBarDB then
                TotemBarDB.tprobeArmed = false
            end
            ChatOut:AddMessage("TotemBar: tprobe capture stopped (" .. tprobeState.n .. " records kept).")
        elseif sub == "dump" then
            if not ExportFile then
                ChatOut:AddMessage("TotemBar: tprobe dump needs SuperWoW (ExportFile missing).")
                return
            end
            tprobeExport()
            ChatOut:AddMessage("TotemBar: tprobe dump written (imports\\tb_tprobe.txt, "
                .. tprobeState.n .. " records).")
        else
            local on = tprobeCapturing and "ON" or "OFF"
            ChatOut:AddMessage("TotemBar: tprobe " .. on .. ", " .. tprobeState.n
                .. " records. Usage: /tb tprobe on|off|dump|status")
        end
    end

    -- Re-arm after /reload if it was left on. SavedVariables survive a
    -- /reload; this frame's event registrations do not (a fresh Lua state
    -- runs on every reload) - so an on->reload->still-on session needs its
    -- own ADDON_LOADED hook to re-attach tprobeFrame's events, same "wait for
    -- ADDON_LOADED before trusting TotemBarDB" convention core/config.lua's
    -- ensureDefaults (called from ui.lua's own ADDON_LOADED handler) and
    -- minimap.lua's build-on-load both already use, rather than assuming
    -- load order against either of those.
    local tprobeInitFrame = CreateFrame("Frame", "TotemBarTProbeInitFrame", UIParent)
    tprobeInitFrame:RegisterEvent("ADDON_LOADED")
    tprobeInitFrame:SetScript("OnEvent", function()
        if event == "ADDON_LOADED" and arg1 == "TotemBar" then
            tprobeInitFrame:UnregisterEvent("ADDON_LOADED")
            if TotemBarDB and TotemBarDB.tprobeArmed then
                tprobeArm()
                ChatOut:AddMessage("TotemBar: tprobe re-armed after reload (" .. tprobeState.n .. " records kept).")
            end
        end
    end)
end
