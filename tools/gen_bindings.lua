-- Generates Bindings.xml from the totem list. Run from repo root:
--   lua50.exe tools/gen_bindings.lua > Bindings.xml
TotemBar = {}
dofile("core/totemdata.lua")   -- TOTEM_ELEMENTS, TOTEMS_BY_ELEMENT
dofile("core/bindlogic.lua")   -- bindingSuffix

local L = {}
local function w(s) table.insert(L, s) end
w('<Bindings>')
w('  <Binding name="TOTEMBAR_DROPSET" header="TOTEMBAR">TotemBar.recallAndCastAll();</Binding>')
w('  <Binding name="TOTEMBAR_RECALL">TotemBar.CastRecall();</Binding>')
w('  <Binding name="TOTEMBAR_TOGGLEBAR">TotemBar.ToggleBar();</Binding>')
w('  <Binding name="TOTEMBAR_TOGGLEOPTIONS">TotemBar.ToggleOptions();</Binding>')
w('  <Binding name="TOTEMBAR_TOGGLEBIND">TotemBar.ToggleBindMode();</Binding>')
local elements = TotemBar.TOTEM_ELEMENTS
for i = 1, table.getn(elements) do
    local e = elements[i]
    w('  <Binding name="TOTEMBAR_CAST_' .. string.upper(e) .. '">TotemBar.CastElement("' .. e .. '");</Binding>')
end
for i = 1, table.getn(elements) do
    local e = elements[i]
    local list = TotemBar.TOTEMS_BY_ELEMENT[e]
    for j = 1, table.getn(list) do
        local totem = list[j]
        local hdr = ""
        if j == 1 then hdr = ' header="TOTEMBAR_' .. string.upper(e) .. '"' end
        w('  <Binding name="TOTEMBAR_TOTEM_' .. TotemBar.bindingSuffix(totem) .. '"' .. hdr .. '>TotemBar.CastTotem("' .. totem .. '");</Binding>')
    end
end
w('</Bindings>')
print(table.concat(L, "\n"))
