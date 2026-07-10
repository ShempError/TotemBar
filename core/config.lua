-- TotemBar - core/config.lua
-- SavedVariables model. TotemBarDB is declared in the .toc as a
-- SavedVariable; ensureDefaults() fills in anything missing (first run,
-- or a saved file from an older version that lacks newer fields).

TotemBar = TotemBar or {}

TotemBarDB = TotemBarDB or {}

-- TotemBarDB shape:
--   chosen[element]  = totemName ("Fire" -> "Searing Totem", ...)
--   gapSeconds       = spam-cycle reset gap (seconds)
--   locked           = boolean, whether the bar can be dragged
--   autoRecall       = boolean, whether recallAndCastAll() prepends
--                       Totemic Recall (toggled via the Recall button's
--                       right-click, see ui.lua); default ON
--   point/relPoint/x/y = saved frame anchor (see ui.lua)
--   showDurationRing/ringStyle/showPulseBars/showPulseWaves/pulseGlow/
--   showTimerText    = Pulse UI (see spec). showPulseBars = the countdown
--                       bar (primary "when's the next pulse" readout);
--                       showPulseWaves = the ripple (event feedback only);
--                       independently toggleable.
--   barLayout        = bar arrangement: "1x6"|"2x3"|"3x2" (rows x cols),
--                       cycled via the options panel (see ui.lua's
--                       ApplyBarLayout / options.lua's layout button).
--   buttonGap        = px gap between bar buttons, range 10-30, default
--                       TotemBar.DEFAULT_BUTTON_GAP (see core/cast.lua);
--                       live-applied via ui.lua's TotemBar.SetButtonGap,
--                       set from the options panel's "Button spacing" slider.
function TotemBar.ensureDefaults()
    TotemBarDB.chosen = TotemBarDB.chosen or {}
    TotemBarDB.gapSeconds = TotemBarDB.gapSeconds or TotemBar.DEFAULT_GAP_SECONDS
    if TotemBarDB.locked == nil then
        TotemBarDB.locked = false
    end
    if TotemBarDB.autoRecall == nil then
        TotemBarDB.autoRecall = true
    end
    TotemBarDB.point = TotemBarDB.point or "CENTER"
    TotemBarDB.relPoint = TotemBarDB.relPoint or "CENTER"
    TotemBarDB.x = TotemBarDB.x or 0
    TotemBarDB.y = TotemBarDB.y or 0
    TotemBarDB.scale = TotemBarDB.scale or 1.0
    TotemBarDB.minimapAngle = TotemBarDB.minimapAngle or 225
    if TotemBarDB.hidden == nil then
        TotemBarDB.hidden = false
    end
    TotemBarDB.recallGuardSeconds = TotemBarDB.recallGuardSeconds or TotemBar.DEFAULT_RECALL_GUARD
    TotemBarDB.recallRefundPct = TotemBarDB.recallRefundPct or 0.25
    TotemBarDB.buttonGap = TotemBarDB.buttonGap or TotemBar.DEFAULT_BUTTON_GAP

    -- Pulse UI (spec docs/superpowers/specs/2026-07-09-pulse-ui-design.md):
    -- duration ring + pulse bars, all on by default; ringStyle "round" vs
    -- "square" is the in-game comparison toggle.
    if TotemBarDB.showDurationRing == nil then
        TotemBarDB.showDurationRing = true
    end
    TotemBarDB.ringStyle = TotemBarDB.ringStyle or "round"
    if TotemBarDB.showPulseBars == nil then
        TotemBarDB.showPulseBars = true
    end
    if TotemBarDB.showPulseWaves == nil then
        TotemBarDB.showPulseWaves = true
    end
    if TotemBarDB.pulseGlow == nil then
        TotemBarDB.pulseGlow = true
    end
    if TotemBarDB.showTimerText == nil then
        TotemBarDB.showTimerText = true
    end

    TotemBarDB.barLayout = TotemBarDB.barLayout or "1x6"
end
