-- TotemBar - bind.lua
-- Key-binding labels (for the Esc > Key Bindings menu) + the cast entry
-- points the Bindings.xml bodies call. Hover-bind mode is added below in a
-- later step. Loaded AFTER Bindings.xml (see the .toc).

TotemBar = TotemBar or {}

local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1

-- Section + fixed-action labels.
BINDING_HEADER_TOTEMBAR = "TotemBar"
BINDING_NAME_TOTEMBAR_DROPSET = "Drop all totems"
BINDING_NAME_TOTEMBAR_RECALL = "Totemic Recall"
BINDING_NAME_TOTEMBAR_TOGGLEBAR = "Toggle bar"
BINDING_NAME_TOTEMBAR_TOGGLEOPTIONS = "Toggle options"
BINDING_NAME_TOTEMBAR_TOGGLEBIND = "Toggle key-bind mode"

-- Per-element "cast the chosen totem" labels + per-element sub-headers.
do
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        local e = elements[i]
        setglobal("BINDING_NAME_TOTEMBAR_CAST_" .. string.upper(e), "Cast " .. e .. " totem (chosen)")
        setglobal("BINDING_HEADER_TOTEMBAR_" .. string.upper(e), "TotemBar: " .. e .. " Totems")
    end
    -- Per-totem labels (must match Bindings.xml names via bindingSuffix).
    for i = 1, table.getn(elements) do
        local e = elements[i]
        local list = TotemBar.TOTEMS_BY_ELEMENT[e]
        for j = 1, table.getn(list) do
            local totem = list[j]
            setglobal("BINDING_NAME_TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(totem), "Cast " .. totem)
        end
    end
end

-- Cast a specific totem by name (no-op in-game if not known).
function TotemBar.CastTotem(name)
    if name then
        CastSpellByName(name)
    end
end

-- Cast the currently-chosen totem for an element.
function TotemBar.CastElement(element)
    local n = TotemBarDB and TotemBarDB.chosen and TotemBarDB.chosen[element]
    if n then
        CastSpellByName(n)
    else
        ChatOut:AddMessage("TotemBar: no totem chosen for " .. tostring(element) .. ".")
    end
end

-- Cast Totemic Recall and clear own-tracking (mirrors the Recall button).
function TotemBar.CastRecall()
    CastSpellByName("Totemic Recall")
    if TotemBar.clearActiveTotems then
        TotemBar.clearActiveTotems()
    end
end

-- Stub so the TOTEMBAR_TOGGLEBIND binding never calls nil before Task 4
-- fills it in. Replaced (same name) by the real implementation below.
if not TotemBar.ToggleBindMode then
    function TotemBar.ToggleBindMode()
        ChatOut:AddMessage("TotemBar: key-bind mode not available.")
    end
end
