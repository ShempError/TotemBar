-- TotemBar - tools/luatests/harness.lua
-- Tiny offline test harness for real Lua 5.0.3. Run test files from the
-- repo root (they dofile() relative paths), e.g.:
--   lua50.exe tools/luatests/test_totemdata.lua

H = H or {}
H.failures = 0
H.total = 0

function H.assert_eq(actual, expected, label)
    H.total = H.total + 1
    if actual == expected then
        print("  ok   - " .. label)
    else
        H.failures = H.failures + 1
        print("  FAIL - " .. label .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
    end
end

function H.run(name, fn)
    print("== " .. name .. " ==")
    fn()
end

function H.summary()
    print("")
    if H.failures == 0 then
        print(H.total .. " assertion(s) passed.")
    else
        print(H.failures .. " of " .. H.total .. " assertion(s) FAILED.")
        os.exit(1)
    end
end
