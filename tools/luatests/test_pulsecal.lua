-- Offline test: core/pulsecal.lua pure ring buffer + serializer.
-- Run from repo root: lua50.exe tools/luatests/test_pulsecal.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/pulsecal.lua")

H.run("pulsecalPush: fills sequentially below cap", function()
    local buf, state = {}, { n = 0, idx = 1 }
    TotemBar.pulsecalPush(buf, 3, state, 1.5, "EV_A", "one")
    TotemBar.pulsecalPush(buf, 3, state, 2.5, "EV_B", "two")
    H.assert_eq(state.n, 2, "two pushed")
    H.assert_eq(state.idx, 3, "next slot is 3")
    H.assert_eq(buf[1].m, "one", "slot 1 holds first record")
    H.assert_eq(buf[2].e, "EV_B", "slot 2 holds second record")
end)

H.run("pulsecalPush: wraps at cap, reuses record tables", function()
    local buf, state = {}, { n = 0, idx = 1 }
    TotemBar.pulsecalPush(buf, 2, state, 1, "A", "one")
    TotemBar.pulsecalPush(buf, 2, state, 2, "B", "two")
    local firstTable = buf[1]
    TotemBar.pulsecalPush(buf, 2, state, 3, "C", "three")
    H.assert_eq(state.idx, 2, "wrapped back past slot 1")
    H.assert_eq(buf[1].m, "three", "slot 1 overwritten by third record")
    H.assert_eq(buf[1] == firstTable, true, "record table reused, not reallocated")
end)

H.run("pulsecalFormat: chronological lines below cap", function()
    local buf, state = {}, { n = 0, idx = 1 }
    TotemBar.pulsecalPush(buf, 4, state, 1.25, "A", "one")
    TotemBar.pulsecalPush(buf, 4, state, 2.5, "B", "two")
    H.assert_eq(TotemBar.pulsecalFormat(buf, 4, state),
        "1.250;A;one\n2.500;B;two", "two lines, t;event;msg")
end)

H.run("pulsecalFormat: wrapped buffer keeps chronological order", function()
    local buf, state = {}, { n = 0, idx = 1 }
    TotemBar.pulsecalPush(buf, 2, state, 1, "A", "one")
    TotemBar.pulsecalPush(buf, 2, state, 2, "B", "two")
    TotemBar.pulsecalPush(buf, 2, state, 3, "C", "three")
    H.assert_eq(TotemBar.pulsecalFormat(buf, 2, state),
        "2.000;B;two\n3.000;C;three", "oldest surviving first")
end)

H.run("pulsecalFormat: empty buffer", function()
    local buf, state = {}, { n = 0, idx = 1 }
    H.assert_eq(TotemBar.pulsecalFormat(buf, 4, state), "", "empty -> empty string")
end)

H.summary()
