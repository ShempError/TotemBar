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
end
