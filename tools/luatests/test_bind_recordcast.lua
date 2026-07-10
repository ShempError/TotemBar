-- Offline test: keybind CastTotem/CastElement record casts (bind.lua fix).
-- Loads the REAL bind.lua via dofile, with the minimal WoW-API stubs it
-- needs at file scope (ChatFrame sink, setglobal, CreateFrame/UIParent for
-- the UPDATE_BINDINGS event frame near the bottom of the file). This
-- exercises the actual TotemBar.CastTotem/TotemBar.CastElement functions -
-- NOT a copy - so a regression in bind.lua's recordCast wiring fails this
-- test. Run from repo root: lua50.exe tools/luatests/test_bind_recordcast.lua

dofile("tools/luatests/harness.lua")

-- Real pure-Lua modules bind.lua depends on at file scope: the per-totem
-- BINDING_NAME_ loop walks TOTEM_ELEMENTS/TOTEMS_BY_ELEMENT and calls
-- TotemBar.bindingSuffix.
TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/bindlogic.lua")

-- ===== Minimal WoW-API stubs bind.lua needs to LOAD (file-scope only) =====

-- setglobal doesn't exist in plain Lua 5.0 (it's a WoW-API-provided
-- global-env helper); getfenv(0) is real Lua 5.0 though.
function setglobal(n, v)
    local e = getfenv(0)
    e[n] = v
end

-- Chat output sink: bind.lua does
--   local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1
-- at file scope.
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

-- Generic stub frame: ANY method access returns a no-op function that
-- itself returns another stub frame, so arbitrary chains
-- (RegisterEvent/SetScript/SetPoint/CreateTexture/CreateFontString/...)
-- all resolve without error, without hand-listing every method bind.lua
-- (or a future edit to it) might call.
local function stubFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() return stubFrame() end end })
    return f
end
CreateFrame = function() return stubFrame() end
UIParent = stubFrame()

-- ===== Load the REAL bind.lua =====
dofile("bind.lua")

-- ===== Mocks installed AFTER dofile, so bind.lua can't clobber them -----
-- bind.lua does NOT define TotemBar.recordCast (that lives in
-- core/cast.lua, not loaded here) or CastSpellByName, so overriding them
-- here is safe and they stay in place for every test below.
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

H.run("CastTotem('Searing Totem') triggers recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TotemBar.CastTotem("Searing Totem")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once")
    H.assert_eq(castSpellByNameCalls[1], "Searing Totem", "CastSpellByName called with correct name")
    H.assert_eq(table.getn(recordCastCalls), 1, "recordCast called once")
    H.assert_eq(recordCastCalls[1].element, "Fire", "recordCast element is Fire")
    H.assert_eq(recordCastCalls[1].totemName, "Searing Totem", "recordCast totemName is Searing Totem")
end)

H.run("CastElement('Fire') triggers recordCast with chosen totem", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TotemBar.CastElement("Fire")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once")
    H.assert_eq(castSpellByNameCalls[1], "Searing Totem", "CastSpellByName called with chosen totem")
    H.assert_eq(table.getn(recordCastCalls), 1, "recordCast called once")
    H.assert_eq(recordCastCalls[1].element, "Fire", "recordCast element is Fire")
    H.assert_eq(recordCastCalls[1].totemName, "Searing Totem", "recordCast totemName is chosen Searing Totem")
end)

H.run("CastTotem with unknown name does NOT trigger recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TotemBar.CastTotem("UnknownSpell")
    H.assert_eq(table.getn(castSpellByNameCalls), 1, "CastSpellByName called once (even for unknown)")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called (unknown name)")
end)

H.run("CastElement with no chosen totem for the element does NOT trigger recordCast", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    -- "Wind" has no chosen entry -> else-branch (ChatOut:AddMessage,
    -- stubbed to a no-op above; DEFAULT_CHAT_FRAME swallows the message).
    TotemBar.CastElement("Wind")
    H.assert_eq(table.getn(castSpellByNameCalls), 0, "CastSpellByName NOT called (no chosen)")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called (no chosen)")
end)

H.run("CastTotem with nil name does nothing", function()
    recordCastCalls = {}
    castSpellByNameCalls = {}
    TotemBar.CastTotem(nil)
    H.assert_eq(table.getn(castSpellByNameCalls), 0, "CastSpellByName NOT called")
    H.assert_eq(table.getn(recordCastCalls), 0, "recordCast NOT called")
end)

H.summary()
