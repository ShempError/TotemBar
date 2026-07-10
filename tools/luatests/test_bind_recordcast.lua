-- Offline test: keybind CastTotem/CastElement record casts (bind.lua fix).
-- The bind.lua file itself is not directly offline-testable (File-Scope
-- ChatFrame + setglobal WoW-API calls), so this test reproduces the
-- recordCast logic with pure-Lua mocks.
-- Run from repo root: lua50.exe tools/luatests/test_bind_recordcast.lua

dofile("tools/luatests/harness.lua")

-- Load the pure-Lua data module (no WoW-API calls).
dofile("core/totemdata.lua")

-- Mock recordCast and CastSpellByName to capture calls.
local recordCastCalls = {}
local castSpellByNameCalls = {}

function TotemBar.recordCast(element, totemName)
    table.insert(recordCastCalls, { element = element, totemName = totemName })
end

function CastSpellByName(name)
    table.insert(castSpellByNameCalls, name)
end

-- Minimal mock DB.
TotemBarDB = {
    chosen = {
        Fire = "Searing Totem",
        Earth = "Stoneclaw Totem",
        Water = "Healing Stream Totem",
        Air = "Windfury Totem",
    }
}

-- Now test the CastTotem and CastElement functions as they are defined
-- in bind.lua (copied here with the new recordCast calls).

-- CastTotem: cast a specific totem by name
function TestCastTotem(name)
    if name then
        CastSpellByName(name)
        local element = TotemBar.elementOf(name)
        if element then
            TotemBar.recordCast(element, name)
        end
    end
end

-- CastElement: cast the currently-chosen totem for an element
function TestCastElement(element)
    local n = TotemBarDB and TotemBarDB.chosen and TotemBarDB.chosen[element]
    if n then
        CastSpellByName(n)
        TotemBar.recordCast(element, n)
    end
end

H.run("CastTotem('Searing Totem') triggers recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TestCastTotem("Searing Totem")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once")
    H.assert_eq(castSpellByNameCalls[1], "Searing Totem", "CastSpellByName called with correct name")
    H.assert_eq(table.getn(recordCastCalls), 1, "recordCast called once")
    H.assert_eq(recordCastCalls[1].element, "Fire", "recordCast element is Fire")
    H.assert_eq(recordCastCalls[1].totemName, "Searing Totem", "recordCast totemName is Searing Totem")
end)

H.run("CastElement('Fire') triggers recordCast with chosen totem", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TestCastElement("Fire")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once")
    H.assert_eq(castSpellByNameCalls[1], "Searing Totem", "CastSpellByName called with chosen totem")
    H.assert_eq(table.getn(recordCastCalls), 1, "recordCast called once")
    H.assert_eq(recordCastCalls[1].element, "Fire", "recordCast element is Fire")
    H.assert_eq(recordCastCalls[1].totemName, "Searing Totem", "recordCast totemName is chosen Searing Totem")
end)

H.run("CastTotem with unknown name does NOT trigger recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TestCastTotem("UnknownSpell")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once (even for unknown)")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called (unknown name)")
end)

H.run("CastElement with nil chosen does NOT trigger recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    -- Setup: no chosen totem for Wind element (doesn't exist in mock DB)
    TestCastElement("Wind")  -- not a valid element
    H.assert_eq(table.getn(castSpellByNameCalls), 0, "CastSpellByName NOT called (no chosen)")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called (no chosen)")
end)

H.run("CastTotem with nil name does nothing", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TestCastTotem(nil)
    H.assert_eq(table.getn(castSpellByNameCalls), 0, "CastSpellByName NOT called")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called")
end)

H.summary()
