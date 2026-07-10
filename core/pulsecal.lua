-- TotemBar - core/pulsecal.lua
-- Dev-only pulse-calibration telemetry (/tb pulsecal): captures raw
-- totem-related combat lines + our own placements into a fixed ring buffer
-- and exports them via SuperWoW ExportFile, so the dev environment can
-- measure REAL TurtleWoW pulse intervals offline and bake them back into
-- core/pulsedata.lua (verified=true) + the knowledge graph.
-- Pure buffer/serializer on top (offline-tested); WoW-gated capture below.

TotemBar = TotemBar or {}

TotemBar.PULSECAL_CAP = 2000

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
            -- anyway).
            local sname = SpellInfo and SpellInfo(arg4)
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
end
