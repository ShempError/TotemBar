# TotemBar Mana Tooltips + Totemic Mastery Duration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Show total mana cost on the drop-set tooltip and refunded mana on the Recall tooltip (from active totems, auto-learned %), and make duration timers +20% for helpful totems when Totemic Mastery is skilled.

**Architecture:** Pure math/classify helpers + WoW-API pieces (hidden-tooltip mana-cost scan, talent scan, refund learner) go in a new `core/manacost.lua`. `cast.lua` applies the Mastery duration multiplier; `ui.lua` adds the two tooltip lines and snapshots recall cost. Bindings/keybinds untouched.

**Tech Stack:** Lua 5.0 (WoW 1.12.1 / TurtleWoW), real Lua 5.0.3 (`lua50.exe`) for offline tests, existing `tools/luatests/harness.lua`.

## Global Constraints

- Lua 5.0 only — no `#table`, no string `:method` calls, no `string.match`/`gmatch` (use `string.find`), no `table.wipe`. `table.getn`, `getglobal`.
- All frames named with `TotemBar` prefix. English strings.
- Mana cost read via hidden `GameTooltip` `SetSpell` scan (no `GetSpellManaCost` on 1.12) — it auto-reflects cost talents (Tidal Focus / Restorative Totems), so do NOT model those.
- Refund % is auto-learned from the real recall mana-gain (default 0.25 until learned); stored in `TotemBarDB.recallRefundPct`.
- Totemic Mastery (TWoW) = +20% helpful-totem duration (+15% recall refund, which the auto-learn captures). Detect via `GetTalentInfo` by talent name "Totemic Mastery".
- Offline tests from repo root: `lua50.exe tools/luatests/test_x.lua`. Parse-check WoW-API: `lua50.exe -e "assert(loadfile('file.lua'))"`. Exe `C:\Users\muell\AppData\Local\Programs\Lua50\lua50.exe` (Bash `/c/...`).
- Deploy `robocopy … /MIR` via PowerShell excl `.git/.superpowers/docs/tools`. Local commits on `dev`; push `dev`→`master` at release (v0.1.2).
- New file `core\manacost.lua` → **full client restart** for the in-game task.

---

### Task 1: Pure logic (`core/manacost.lua` part 1)

**Files:** Create `core/manacost.lua`; Test `tools/luatests/test_manacost.lua`.

**Interfaces produced:** `TotemBar.parseManaCost(text)`, `TotemBar.sumChosenCost(chosen, elements, costFn)`, `TotemBar.sumActiveCost(activeTotems, elements, now, costFn, remainingFn)`, `TotemBar.refundAmount(pct, activeCost)`, `TotemBar.learnRefundPct(manaGained, activeCost)`, `TotemBar.durationWithMastery(base, isHelpful, hasMastery)`, `TotemBar.isHelpfulTotem(name)`, `TotemBar.NON_HELPFUL_TOTEMS`.

- [ ] **Step 1: Write the failing test** — create `tools/luatests/test_manacost.lua`:

```lua
-- Offline test: core/manacost.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_manacost.lua
dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")   -- TOTEM_ELEMENTS
dofile("core/manacost.lua")

local EL = TotemBar.TOTEM_ELEMENTS

H.run("parseManaCost", function()
    H.assert_eq(TotemBar.parseManaCost("155 Mana"), 155, "155 Mana")
    H.assert_eq(TotemBar.parseManaCost("55 Mana"), 55, "55 Mana")
    H.assert_eq(TotemBar.parseManaCost("Instant"), nil, "no number")
    H.assert_eq(TotemBar.parseManaCost(nil), nil, "nil")
end)

H.run("sumChosenCost: sums chosen, skips nil", function()
    local chosen = { Fire = "A", Water = "C" }
    local costs = { A = 100, C = 50 }
    local fn = function(n) return costs[n] end
    H.assert_eq(TotemBar.sumChosenCost(chosen, EL, fn), 150, "100+50")
    H.assert_eq(TotemBar.sumChosenCost({}, EL, fn), 0, "empty")
end)

H.run("sumActiveCost: excludes expired (remaining<=0)", function()
    local active = {
        Fire  = { totemName = "A", start = 0, duration = 100 },
        Earth = { totemName = "B", start = 0, duration = 100 },
    }
    local costs = { A = 100, B = 40 }
    local costFn = function(n) return costs[n] end
    -- remainingFn stub: A still up (10), B expired (-5)
    local rem = { A = 10, B = -5 }
    local remFn = function(start, dur, now) return nil end
    -- use totemName via closure: map by duration is awkward; use a name-aware stub
    local remByName = { A = 10, B = -5 }
    local activeByName = {}
    -- rebuild remainingFn to look up by the rec passed; simpler: encode remaining in start
    active.Fire.start = 0;  active.Fire.duration = 10   -- remaining(0,10,0)=10 >0
    active.Earth.start = 0; active.Earth.duration = 0   -- remaining(0,0,5)=-5 <=0
    local realRem = function(s, d, now) if not s or not d then return nil end return s + d - now end
    H.assert_eq(TotemBar.sumActiveCost(active, EL, 5, costFn, realRem), 100, "only A (100), B expired")
end)

H.run("refundAmount: floor(pct*cost)", function()
    H.assert_eq(TotemBar.refundAmount(0.25, 400), 100, "25% of 400")
    H.assert_eq(TotemBar.refundAmount(0.25, 401), 100, "floored")
    H.assert_eq(TotemBar.refundAmount(nil, 400), 0, "nil pct")
end)

H.run("learnRefundPct: in-range else nil", function()
    H.assert_eq(TotemBar.learnRefundPct(100, 400), 0.25, "100/400")
    H.assert_eq(TotemBar.learnRefundPct(100, 0), nil, "zero cost")
    H.assert_eq(TotemBar.learnRefundPct(1, 400), nil, "too small (<0.05)")
    H.assert_eq(TotemBar.learnRefundPct(500, 400), nil, "too big (>1.0)")
end)

H.run("durationWithMastery", function()
    H.assert_eq(TotemBar.durationWithMastery(100, true, true), 120, "helpful+mastery")
    H.assert_eq(TotemBar.durationWithMastery(100, false, true), 100, "not helpful")
    H.assert_eq(TotemBar.durationWithMastery(100, true, false), 100, "no mastery")
end)

H.run("isHelpfulTotem: damage totems excluded", function()
    H.assert_eq(TotemBar.isHelpfulTotem("Searing Totem"), false, "searing")
    H.assert_eq(TotemBar.isHelpfulTotem("Magma Totem"), false, "magma")
    H.assert_eq(TotemBar.isHelpfulTotem("Fire Nova Totem"), false, "fire nova")
    H.assert_eq(TotemBar.isHelpfulTotem("Grace of Air Totem"), true, "buff totem")
    H.assert_eq(TotemBar.isHelpfulTotem(nil), false, "nil")
end)

H.summary()
```

- [ ] **Step 2: Run test → FAIL** — `lua50.exe tools/luatests/test_manacost.lua` (cannot open core/manacost.lua).

- [ ] **Step 3: Implement `core/manacost.lua` (pure part):**

```lua
-- TotemBar - core/manacost.lua
-- Mana-cost reading + refund/duration helpers. The PURE functions here are
-- offline-tested; the WoW-API pieces (hidden-tooltip scan, talent scan, refund
-- learner) are appended in a later task and are guarded so this file loads
-- fine under plain Lua for the tests.

TotemBar = TotemBar or {}

-- Pure: mana cost from a tooltip line like "155 Mana" -> 155, else nil.
function TotemBar.parseManaCost(text)
    if not text then
        return nil
    end
    local _, _, n = string.find(text, "^(%d+) ")
    if n then
        return tonumber(n)
    end
    return nil
end

-- Pure: sum costFn(chosen[element]) over the elements that have a chosen totem.
function TotemBar.sumChosenCost(chosen, elements, costFn)
    local total = 0
    if not chosen then
        return 0
    end
    for i = 1, table.getn(elements) do
        local name = chosen[elements[i]]
        if name then
            local c = costFn(name)
            if c then
                total = total + c
            end
        end
    end
    return total
end

-- Pure: sum cost of active totems that are still out (remaining > 0).
function TotemBar.sumActiveCost(activeTotems, elements, now, costFn, remainingFn)
    local total = 0
    if not activeTotems then
        return 0
    end
    for i = 1, table.getn(elements) do
        local rec = activeTotems[elements[i]]
        if rec then
            local rem = remainingFn(rec.start, rec.duration, now)
            if rem and rem > 0 then
                local c = costFn(rec.totemName)
                if c then
                    total = total + c
                end
            end
        end
    end
    return total
end

-- Pure: floored refund.
function TotemBar.refundAmount(pct, activeCost)
    if not pct or not activeCost then
        return 0
    end
    return math.floor(pct * activeCost)
end

-- Pure: learn refund pct from an observed mana gain; nil if out of sane range.
function TotemBar.learnRefundPct(manaGained, activeCost)
    if not manaGained or not activeCost or activeCost <= 0 then
        return nil
    end
    local pct = manaGained / activeCost
    if pct < 0.05 or pct > 1.0 then
        return nil
    end
    return pct
end

-- Pure: helpful totems get Totemic Mastery's +20% duration.
function TotemBar.durationWithMastery(baseDuration, isHelpful, hasMastery)
    if hasMastery and isHelpful then
        return baseDuration * 1.2
    end
    return baseDuration
end

-- The pure fire-DAMAGE totems do NOT get the +20% helpful-totem duration.
-- Everything else is treated as helpful. VERIFY in-game and adjust.
TotemBar.NON_HELPFUL_TOTEMS = {
    ["Searing Totem"] = true,
    ["Magma Totem"] = true,
    ["Fire Nova Totem"] = true,
}

function TotemBar.isHelpfulTotem(name)
    if not name then
        return false
    end
    if TotemBar.NON_HELPFUL_TOTEMS[name] then
        return false
    end
    return true
end
```

- [ ] **Step 4: Run test → PASS.**
- [ ] **Step 5: Commit** — `git add core/manacost.lua tools/luatests/test_manacost.lua && git commit -m "TotemBar: add pure mana-cost/refund/duration helpers"`

---

### Task 2: WoW-API layer (`core/manacost.lua` part 2) + TOC + config default

**Files:** Modify `core/manacost.lua` (append), `core/config.lua`, `TotemBar.toc`.

**Interfaces produced:** `TotemBar.getTotemManaCost(name) -> number|nil` (cached scan); `TotemBar.hasTotemicMastery() -> boolean`; `TotemBar.snapshotRecallCost()`; `TotemBarDB.recallRefundPct` default.

- [ ] **Step 1: Add `core\manacost.lua` to the TOC** — after `core\cast.lua` and `core\totemdata.lua`, before `ui.lua` (it uses `TotemBar.TOTEM_ELEMENTS`, `TotemBar.remaining`, `TotemBar.activeTotems`, `FindSpellIndexByName` is ui-local so manacost has its own slot finder). Place among the `core\` block before `ui.lua`.

- [ ] **Step 2: Append the WoW-API layer to `core/manacost.lua`:**

```lua
-- ===== WoW-API layer (not offline-executed) =====

-- Own spellbook-slot finder (ui.lua's FindSpellIndexByName is file-local).
local function findSpellSlot(name)
    if not name then return nil end
    local i = 1
    while true do
        local n = GetSpellName(i, BOOKTYPE_SPELL)
        if not n then return nil end
        if n == name then return i end
        i = i + 1
    end
end

local scanTip = nil
local manaCache = {}   -- name -> cost (only positive results cached)

-- Reads a totem's mana cost via a hidden tooltip scan (no GetSpellManaCost on
-- 1.12). Reflects cost talents (Tidal Focus, Restorative Totems) automatically.
-- Cached by name; cache cleared on SPELLS_CHANGED (talent/rank changes).
function TotemBar.getTotemManaCost(name)
    if not name then return nil end
    if manaCache[name] then return manaCache[name] end
    local idx = findSpellSlot(name)
    if not idx then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "TotemBarScanTooltip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetSpell(idx, BOOKTYPE_SPELL)
    local cost = nil
    local lines = scanTip:NumLines() or 0
    for i = 1, lines do
        local fs = getglobal("TotemBarScanTooltipTextLeft" .. i)
        local text = fs and fs:GetText()
        local c = TotemBar.parseManaCost(text)
        if c then
            cost = c
            break
        end
    end
    if cost then manaCache[name] = cost end
    return cost
end

-- Totemic Mastery (TWoW: +20% helpful-totem duration): cached scan of the
-- talent trees by name.
local masteryCached = false
local function scanMastery()
    masteryCached = false
    local tabs = (GetNumTalentTabs and GetNumTalentTabs()) or 0
    for tab = 1, tabs do
        local num = GetNumTalents(tab)
        for i = 1, num do
            local tname, _, _, _, rank = GetTalentInfo(tab, i)
            if tname == "Totemic Mastery" and rank and rank > 0 then
                masteryCached = true
            end
        end
    end
end

function TotemBar.hasTotemicMastery()
    return masteryCached
end

-- Recall-refund auto-learn. Snapshot the summed cost of the totems currently
-- out just before a DELIBERATE Totemic Recall; when the mana-gain message
-- arrives shortly after, learn the real refund %.
TotemBar.recallPendingCost = 0
local recallExpectUntil = 0

function TotemBar.snapshotRecallCost()
    TotemBar.recallPendingCost = TotemBar.sumActiveCost(
        TotemBar.activeTotems, TotemBar.TOTEM_ELEMENTS, GetTime(),
        TotemBar.getTotemManaCost, TotemBar.remaining)
    recallExpectUntil = GetTime() + 2
end

-- Events: refresh mastery, clear the cost cache on spell changes, and learn
-- the refund % from the recall mana-gain message.
local mcEvents = CreateFrame("Frame", "TotemBarManaCostEventFrame", UIParent)
mcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
mcEvents:RegisterEvent("CHARACTER_POINTS_CHANGED")
mcEvents:RegisterEvent("SPELLS_CHANGED")
mcEvents:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
mcEvents:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or event == "CHARACTER_POINTS_CHANGED" then
        scanMastery()
    elseif event == "SPELLS_CHANGED" then
        manaCache = {}
        scanMastery()
    elseif event == "CHAT_MSG_SPELL_SELF_BUFF" then
        if GetTime() > recallExpectUntil then return end
        local msg = arg1
        if not msg then return end
        -- Learn only from a Totemic Recall mana-gain within the window.
        -- NOTE: exact message text is locale/format dependent - VERIFY in-game
        -- (adjust the "Totemic Recall" + number pattern if needed).
        if string.find(msg, "Totemic Recall") then
            local _, _, num = string.find(msg, "(%d+)")
            local gained = tonumber(num)
            local pct = TotemBar.learnRefundPct(gained, TotemBar.recallPendingCost)
            if pct and TotemBarDB then
                TotemBarDB.recallRefundPct = pct
            end
        end
    end
end)
```

- [ ] **Step 3: `config.lua` default** — in `ensureDefaults`, add `TotemBarDB.recallRefundPct = TotemBarDB.recallRefundPct or 0.25`.

- [ ] **Step 4: Parse-check + suite** — `lua50.exe -e "assert(loadfile('core/manacost.lua'))"` and `... loadfile('core/config.lua') ...` (clean); run all offline suites — all pass. (The WoW-API code is only loaded, not executed, under plain Lua; the `CreateFrame`/event code is at file scope but `CreateFrame` is nil in tests — so guard it: wrap the `mcEvents` block in `if CreateFrame then ... end` so `loadfile`+the test's `dofile` don't error. Add that guard.)

- [ ] **Step 5: Commit** — `git add core/manacost.lua core/config.lua TotemBar.toc && git commit -m "TotemBar: mana-cost tooltip scan + Totemic Mastery detection + refund auto-learn"`

---

### Task 3: Apply the Mastery duration multiplier (`core/cast.lua`)

**Files:** Modify `core/cast.lua` (`recordCast`).

- [ ] **Step 1: Wrap the duration in `recordCast`.** Find where `recordCast` builds `rec` with `duration = TotemBar.totemDuration(totemName, highestRank)` and change it to:
```lua
        duration = TotemBar.durationWithMastery(
            TotemBar.totemDuration(totemName, highestRank),
            TotemBar.isHelpfulTotem(totemName),
            TotemBar.hasTotemicMastery and TotemBar.hasTotemicMastery()),
```
(The `TotemBar.hasTotemicMastery and ...` guard keeps `recordCast` safe if manacost.lua isn't loaded, e.g. offline test_cast.lua — verify test_cast still passes, since it dofiles cast.lua without manacost. If test_cast calls recordCast it would need the helpers; it does NOT (it only tests the pure fns), so this is safe. Confirm.)

- [ ] **Step 2: Parse-check + suite** — `lua50.exe -e "assert(loadfile('core/cast.lua'))"` (clean); run all offline suites (esp. test_cast, test_manacost) — all pass.

- [ ] **Step 3: Commit** — `git add core/cast.lua && git commit -m "TotemBar: apply Totemic Mastery +20% duration to helpful-totem timers"`

---

### Task 4: Tooltips + recall-cost snapshot (`ui.lua`, `bind.lua`)

**Files:** Modify `ui.lua` (drop-set + recall `OnEnter`; snapshot on the recall button click), `bind.lua` (`CastRecall` snapshot).

- [ ] **Step 1: Drop-set tooltip.** In `CreateDropSetButton`'s `OnEnter`, after the existing `AddLine`, before `GameTooltip:Show()`, add:
```lua
        local cost = TotemBar.sumChosenCost(TotemBarDB.chosen, TotemBar.TOTEM_ELEMENTS, TotemBar.getTotemManaCost)
        if cost and cost > 0 then
            GameTooltip:AddLine("Mana: " .. cost, 0.6, 0.6, 1)
        end
```

- [ ] **Step 2: Recall tooltip + snapshot.** Find the Recall button's `OnEnter` (in `CreateRecallButton`) and add, before `GameTooltip:Show()`:
```lua
        local activeCost = TotemBar.sumActiveCost(TotemBar.activeTotems, TotemBar.TOTEM_ELEMENTS, GetTime(), TotemBar.getTotemManaCost, TotemBar.remaining)
        local pct = (TotemBarDB and TotemBarDB.recallRefundPct) or 0.25
        local refund = TotemBar.refundAmount(pct, activeCost)
        if refund > 0 then
            GameTooltip:AddLine("Refund: ~" .. refund .. " mana", 0.6, 0.6, 1)
        end
```
And in the Recall button's `OnClick` LEFT branch (the deliberate recall), before `CastSpellByName("Totemic Recall")`, add:
```lua
            if TotemBar.snapshotRecallCost then TotemBar.snapshotRecallCost() end
```

- [ ] **Step 3: `CastRecall` snapshot.** In `bind.lua`'s `TotemBar.CastRecall`, before `CastSpellByName("Totemic Recall")`, add:
```lua
    if TotemBar.snapshotRecallCost then TotemBar.snapshotRecallCost() end
```

- [ ] **Step 4: Parse-check + suite** — parse-check `ui.lua` + `bind.lua` (clean); run all offline suites — all pass.

- [ ] **Step 5: Commit** — `git add ui.lua bind.lua && git commit -m "TotemBar: mana-cost drop tooltip + recall-refund tooltip + recall-cost snapshot"`

---

### Task 5: Deploy + full restart + in-game verification + v0.1.2

**Files:** none.

- [ ] **Step 1: Deploy (PowerShell)** — `robocopy "C:\dev\TotemBar" "C:\turtle\Interface\AddOns\TotemBar" /MIR /XD .git .superpowers docs tools /XF README.md LICENSE CHANGELOG.md` — confirm `core\manacost.lua` lands. Exit 0-7.

- [ ] **Step 2: Full client restart** (new file `core\manacost.lua`). Check `C:\turtle\Errors` for a new #132 first (a load error would crash on startup).

- [ ] **Step 3: In-game verification** (have Phil confirm):
  - **Drop-set tooltip**: "Mana: N" matches the summed cost of the four chosen totems' spellbook tooltips (and reflects talent discounts). Verify the tooltip **line index** (Left2) actually holds the mana cost for totems — if a "Mana: 0"/missing line, the cost line is a different index; widen/adjust the scan.
  - **Recall tooltip**: "Refund: ~N mana" is present when totems are out, scales with how many are out, and drops as totems expire (re-hover to recompute).
  - **Refund learning**: recall a full set a couple times; confirm the shown refund settles to a stable, believable value (and if Totemic Mastery is skilled, higher). **Verify the CHAT_MSG_SPELL_SELF_BUFF message text/pattern** for the recall mana-gain — adjust the `string.find` in manacost.lua if it doesn't match.
  - **Duration fix**: with Totemic Mastery skilled, a freshly-dropped helpful totem's timer is ~20% longer than without; a fire-damage totem (Searing/Magma/Fire Nova) is not boosted. **Verify WHICH totems actually get the +20%** and adjust `NON_HELPFUL_TOTEMS`.

- [ ] **Step 4: KG write-back** (after confirmation): the verified totem mana-cost tooltip line index, the recall mana-gain message pattern + learned refund %, and the confirmed helpful-totem set for the +20%. `verification:"in-game-confirmed"`.

- [ ] **Step 5: Release** — bump `TotemBar.toc` `## Version` to `0.1.2`; add a `## v0.1.2` section to `CHANGELOG.md` (mana-cost/refund tooltips, Totemic Mastery duration); commit on `dev`; merge `dev`→`master`; tag `v0.1.2`; push both + tag; rebuild `TotemBar-v0.1.2.zip` (clean `TotemBar/` folder, runtime files + README/LICENSE/CHANGELOG) and `gh release create v0.1.2` with it. Update the devlog + HANDOVER.

---

## Self-Review

**Spec coverage:** drop-set mana tooltip (Task 4) ✅; recall refund tooltip from active totems (Task 4, `sumActiveCost` excludes expired) ✅; mana-cost hidden-tooltip scan + cache + SPELLS_CHANGED invalidation (Task 2) ✅; refund auto-learn + default (Tasks 1/2/config) ✅; Totemic Mastery detection (Task 2) + duration ×1.2 for helpful totems (Task 3) ✅; pure helpers offline-tested (Task 1) ✅; deploy/full-restart/in-game + the four verify-points + KG writeback + v0.1.2 (Task 5) ✅; new SV `recallRefundPct` (Task 2/config) ✅.

**Placeholder scan:** every step has concrete code; the two message-format unknowns (mana-cost tooltip line index; recall mana-gain message text) and the helpful-totem set are explicit in-game verify steps, not code TBDs.

**Type consistency:** `costFn` signature `(name)->number|nil` used identically by `sumChosenCost`/`sumActiveCost` and supplied as `TotemBar.getTotemManaCost` at call sites; `remainingFn` = `TotemBar.remaining(start,duration,now)` (existing, cast.lua); `durationWithMastery(base,isHelpful,hasMastery)` args match `recordCast`'s call; `TotemBarDB.recallRefundPct` default (config) ↔ read (ui recall tooltip) ↔ written (manacost learner) consistent. TOC: `core\manacost.lua` before `ui.lua`; it references `TotemBar.TOTEM_ELEMENTS`/`remaining`/`activeTotems` (all defined in earlier-loaded core files) only inside functions called at runtime.
