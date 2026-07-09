# TotemBar Minimap Button + Options Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pfUI-safe minimap button that opens a standalone TotemBar options panel (settings + UI-size slider + a "create Totems macro" button).

**Architecture:** Pure, offline-testable helpers (`angleToOffset`, `clampValue`, `macroSpec`) go in `core/optionslogic.lua`. `config.lua` gains new SavedVariables; `ui.lua` gains `ToggleBar`/`ResetPosition`, applies scale/hidden on build, and promotes `RefreshRecallIndicator`. `options.lua` builds the standalone panel (checkboxes/sliders/buttons) and `ToggleOptions`. `minimap.lua` builds the orbit-draggable minimap button (uses `ToggleOptions`/`ToggleBar`). WoW-API files are parse-checked; logic files are TDD-tested.

**Tech Stack:** Lua 5.0 (WoW 1.12.1 / TurtleWoW), real Lua 5.0.3 (`lua50.exe`) for offline tests, existing `tools/luatests/harness.lua`.

## Global Constraints

- Lua 5.0 only — no `#table`, no string `:method` calls, no `string.match`/`gmatch`, no `table.wipe`, no `C_Timer`. Use `table.getn`, `string.xxx(...)`, reassign `{}` to clear.
- All frames named with the `TotemBar` prefix (no anonymous frames that need `getglobal`; template child labels REQUIRE a non-nil frame name). Pool/reuse widgets; no per-frame allocation; no `OnUpdate` on the options panel.
- All user-facing strings in **English**.
- `GetChecked()` returns `1` or `nil` in 1.12 — always compare `== 1`. `SetMinMaxValues` BEFORE `SetValue` on sliders. Never override `OptionsSliderTemplate`'s 16px height.
- Minimap button: parent MUST be `Minimap`; name MUST contain `"Minimap"`; `SetFrameStrata("HIGH")` + `SetFrameLevel(9)` (pfUI hides MEDIUM); size 31×31; derive radius from `Minimap:GetWidth()`, never hardcode. `/tb options` is the guaranteed access path.
- Offline tests run from the repo root: `lua50.exe tools/luatests/test_x.lua`. Parse-check WoW-API files: `lua50.exe -e "assert(loadfile('file.lua'))"`. Exe at `C:\Users\muell\AppData\Local\Programs\Lua50\lua50.exe` (Bash: `/c/Users/muell/AppData/Local/Programs/Lua50/lua50.exe`).
- Local client `C:\turtle`; deploy `robocopy C:\dev\TotemBar C:\turtle\Interface\AddOns\TotemBar /MIR` from **PowerShell**. Do NOT push (push paused) — local commits on `dev`.
- New `.lua` files added to the `.toc` → **full client restart** required (not `/reload`).

---

### Task 1: Pure options helpers (`core/optionslogic.lua`)

**Files:**
- Create: `core/optionslogic.lua`
- Test: `tools/luatests/test_optionslogic.lua`

**Interfaces:**
- Produces: `TotemBar.angleToOffset(angleDeg, radius) -> x, y`; `TotemBar.clampValue(v, minVal, maxVal) -> number`; `TotemBar.macroSpec() -> name, body, icon`.

- [ ] **Step 1: Write the failing test**

Create `tools/luatests/test_optionslogic.lua`:

```lua
-- Offline test: core/optionslogic.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_optionslogic.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/optionslogic.lua")

local function round(n) return math.floor(n + 0.5) end

H.run("angleToOffset: cardinal angles on radius 100", function()
    local x, y = TotemBar.angleToOffset(0, 100)
    H.assert_eq(round(x), 100, "0deg x=100"); H.assert_eq(round(y), 0, "0deg y=0")
    x, y = TotemBar.angleToOffset(90, 100)
    H.assert_eq(round(x), 0, "90deg x=0"); H.assert_eq(round(y), 100, "90deg y=100")
    x, y = TotemBar.angleToOffset(180, 100)
    H.assert_eq(round(x), -100, "180deg x=-100"); H.assert_eq(round(y), 0, "180deg y=0")
    x, y = TotemBar.angleToOffset(270, 100)
    H.assert_eq(round(x), 0, "270deg x=0"); H.assert_eq(round(y), -100, "270deg y=-100")
end)

H.run("clampValue: below / within / above", function()
    H.assert_eq(TotemBar.clampValue(-1, 0, 5), 0, "below -> min")
    H.assert_eq(TotemBar.clampValue(3, 0, 5), 3, "within -> unchanged")
    H.assert_eq(TotemBar.clampValue(9, 0, 5), 5, "above -> max")
end)

H.run("macroSpec: fixed name/body/icon", function()
    local name, body, icon = TotemBar.macroSpec()
    H.assert_eq(name, "Totems", "macro name")
    H.assert_eq(body, "/script TotemBar.recallAndCastAll()", "macro body")
    H.assert_eq(icon, "Spell_Nature_TremorTotem", "macro icon (bare name)")
end)

H.summary()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua50.exe tools/luatests/test_optionslogic.lua`
Expected: FAIL — `cannot open core/optionslogic.lua`.

- [ ] **Step 3: Write minimal implementation**

Create `core/optionslogic.lua`:

```lua
-- TotemBar - core/optionslogic.lua
-- PURE helpers for the options panel + minimap button (no WoW API), so the
-- fiddly bits (orbit math, slider clamping, the macro contract) are
-- offline-testable under real Lua 5.0. The UI (minimap.lua / options.lua)
-- calls these.

TotemBar = TotemBar or {}

-- Orbit offset (x, y) for a minimap button at angleDeg on a circle of the
-- given radius. 0deg -> (radius,0); 90 -> (0,radius); 180 -> (-radius,0).
function TotemBar.angleToOffset(angleDeg, radius)
    local rad = math.rad(angleDeg)
    return math.cos(rad) * radius, math.sin(rad) * radius
end

-- Clamp v into [minVal, maxVal].
function TotemBar.clampValue(v, minVal, maxVal)
    if v < minVal then
        return minVal
    end
    if v > maxVal then
        return maxVal
    end
    return v
end

-- The fixed spec for the "Totems" convenience macro: name, body, and a BARE
-- icon file name (no Interface\Icons\ prefix, no extension - TurtleWoW's
-- CreateMacro/EditMacro prepend the path themselves).
function TotemBar.macroSpec()
    return "Totems", "/script TotemBar.recallAndCastAll()", "Spell_Nature_TremorTotem"
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua50.exe tools/luatests/test_optionslogic.lua`
Expected: PASS — ends with `... assertion(s) passed.`

- [ ] **Step 5: Commit**

```bash
git add core/optionslogic.lua tools/luatests/test_optionslogic.lua
git commit -m "TotemBar: add pure options helpers (angleToOffset/clampValue/macroSpec)"
```

---

### Task 2: SavedVariables + bar wiring (`config.lua`, `ui.lua`, `TotemBar.toc`)

**Files:**
- Modify: `core/config.lua` (new `ensureDefaults` fields)
- Modify: `ui.lua` (`ToggleBar`, `ResetPosition`, apply scale/hidden in `BuildUI`, promote `RefreshRecallIndicator`, route `/tb` empty command through `ToggleBar`)
- Modify: `TotemBar.toc` (add `core\optionslogic.lua`)
- Test: `tools/luatests/test_config.lua`

**Interfaces:**
- Consumes: `TotemBar.DEFAULT_GAP_SECONDS` (cast.lua), `TotemBar.DEFAULT_RECALL_GUARD` (cast.lua).
- Produces: `TotemBarDB.scale/minimapAngle/hidden/recallGuardSeconds` defaults; `TotemBar.ToggleBar()`; `TotemBar.ResetPosition()`; global `TotemBar.RefreshRecallIndicator`.

- [ ] **Step 1: Add `core\optionslogic.lua` to the TOC**

Edit `TotemBar.toc` — insert `core\optionslogic.lua` after `core\assign.lua`, before `ui.lua`:

```
core\config.lua
core\assign.lua
core\optionslogic.lua
ui.lua
```

- [ ] **Step 2: Write the failing test for ensureDefaults**

Create `tools/luatests/test_config.lua`:

```lua
-- Offline test: core/config.lua ensureDefaults fills the new SavedVariables
-- fields. Run from repo root: lua50.exe tools/luatests/test_config.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
TotemBar.DEFAULT_GAP_SECONDS = 2
TotemBar.DEFAULT_RECALL_GUARD = 2
dofile("core/config.lua")

H.run("ensureDefaults: fills new fields on a fresh DB", function()
    TotemBarDB = {}
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.scale, 1.0, "scale default 1.0")
    H.assert_eq(TotemBarDB.minimapAngle, 225, "minimapAngle default 225")
    H.assert_eq(TotemBarDB.hidden, false, "hidden default false")
    H.assert_eq(TotemBarDB.recallGuardSeconds, 2, "recallGuardSeconds default 2")
end)

H.run("ensureDefaults: preserves existing values", function()
    TotemBarDB = { scale = 1.5, minimapAngle = 40, hidden = true, recallGuardSeconds = 3 }
    TotemBar.ensureDefaults()
    H.assert_eq(TotemBarDB.scale, 1.5, "scale preserved")
    H.assert_eq(TotemBarDB.minimapAngle, 40, "angle preserved")
    H.assert_eq(TotemBarDB.hidden, true, "hidden preserved")
    H.assert_eq(TotemBarDB.recallGuardSeconds, 3, "guard preserved")
end)

H.summary()
```

- [ ] **Step 3: Run test to verify it fails**

Run: `lua50.exe tools/luatests/test_config.lua`
Expected: FAIL — `scale default 1.0` (and the others) fail: `expected 1, got nil`.

- [ ] **Step 4: Extend `ensureDefaults` in `core/config.lua`**

In `TotemBar.ensureDefaults()`, before the final `end`, add:

```lua
    TotemBarDB.scale = TotemBarDB.scale or 1.0
    TotemBarDB.minimapAngle = TotemBarDB.minimapAngle or 225
    if TotemBarDB.hidden == nil then
        TotemBarDB.hidden = false
    end
    TotemBarDB.recallGuardSeconds = TotemBarDB.recallGuardSeconds or TotemBar.DEFAULT_RECALL_GUARD
```

- [ ] **Step 5: Run test to verify it passes**

Run: `lua50.exe tools/luatests/test_config.lua`
Expected: PASS.

- [ ] **Step 6: Add `ToggleBar`, `ResetPosition`, apply scale/hidden, promote the indicator in `ui.lua`**

(a) In `ui.lua`, `RefreshRecallIndicator` is a file-local assigned at its definition. Immediately after that assignment block ends (after its closing `end`), add a public alias:

```lua
-- Public alias so options.lua can refresh the "A" auto-recall indicator
-- after the auto-recall checkbox is toggled.
TotemBar.RefreshRecallIndicator = RefreshRecallIndicator
```

(b) In `function TotemBar.BuildUI()`, right after `frame:SetBackdropColor(0, 0, 0, 0.5)` (before the movable/backdrop setup is fine; just after the frame exists), apply the saved scale:

```lua
    frame:SetScale(TotemBarDB.scale or 1.0)
```

And change the final `frame:Show()` at the end of `BuildUI` to honor `hidden`:

```lua
    frame:Show()
    if TotemBarDB.hidden then
        frame:Hide()
    end
```

(c) Add these two functions near the other `TotemBar.` bar operations (e.g. just after `TotemBar.BuildUI` ends):

```lua
-- Shows/hides the bar and persists the choice (TotemBarDB.hidden). Driven
-- by the options panel's "Show bar" checkbox, the minimap right-click, and
-- the bare /tb command.
function TotemBar.ToggleBar()
    if not TotemBarFrame then
        return
    end
    if TotemBarFrame:IsShown() then
        TotemBarFrame:Hide()
        TotemBarDB.hidden = true
    else
        TotemBarFrame:Show()
        TotemBarDB.hidden = false
    end
end

-- Resets the bar's saved anchor to centered defaults and re-anchors it.
-- Does NOT change scale. Driven by the options panel's "Reset position".
function TotemBar.ResetPosition()
    TotemBarDB.point = "CENTER"
    TotemBarDB.relPoint = "CENTER"
    TotemBarDB.x = 0
    TotemBarDB.y = 0
    if TotemBarFrame then
        TotemBarFrame:ClearAllPoints()
        TotemBarFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end
```

(d) Route the bare `/tb` command through `ToggleBar` for persistence. In `HandleSlashCommand`, replace the `if cmd == "" then ... end` block body:

```lua
    if cmd == "" then
        TotemBar.ToggleBar()
```
(remove the old inline `if TotemBarFrame:IsShown() then Hide else Show`.)

- [ ] **Step 7: Parse-check + full suite**

Run:
```
lua50.exe -e "assert(loadfile('core/config.lua'))"
lua50.exe -e "assert(loadfile('ui.lua'))"
lua50.exe tools/luatests/test_config.lua
lua50.exe tools/luatests/test_optionslogic.lua
lua50.exe tools/luatests/test_assign.lua
lua50.exe tools/luatests/test_known.lua
lua50.exe tools/luatests/test_totemdata.lua
lua50.exe tools/luatests/test_cast.lua
lua50.exe tools/luatests/test_duration.lua
lua50.exe tools/luatests/test_buffmatch.lua
```
Expected: parse-checks clean (no output); every suite ends with `... assertion(s) passed.`

- [ ] **Step 8: Commit**

```bash
git add TotemBar.toc core/config.lua ui.lua tools/luatests/test_config.lua
git commit -m "TotemBar: add scale/minimapAngle/hidden/recallGuard SVs + ToggleBar/ResetPosition"
```

---

### Task 3: Options panel + 6 controls + `ToggleOptions` (`options.lua`)

**Files:**
- Create: `options.lua`
- Modify: `ui.lua` (`/tb options` slash command + updated usage line)
- Modify: `TotemBar.toc` (add `options.lua` after `ui.lua`)

**Interfaces:**
- Consumes: `TotemBar.clampValue` (Task 1); `TotemBarDB` fields (Task 2); `TotemBar.RefreshRecallIndicator` (Task 2); `TotemBarFrame`.
- Produces: `TotemBar.ToggleOptions()`; global frame `TotemBarOptionsFrame`.

- [ ] **Step 1: Add `options.lua` to the TOC**

Edit `TotemBar.toc` — add `options.lua` after `ui.lua`:

```
ui.lua
options.lua
```

- [ ] **Step 2: Create `options.lua` with the panel + factories + 6 controls**

Create `options.lua`:

```lua
-- TotemBar - options.lua
-- Standalone options panel (no Blizzard InterfaceOptions integration). Built
-- once (lazy) on first ToggleOptions; repopulated from TotemBarDB on show.
-- Opened by the minimap button's left-click and by /tb options. WoW-API
-- file (parse-checked only). Widget wiring uses 1.12 templates:
-- UICheckButtonTemplate (GetChecked() -> 1/nil) and OptionsSliderTemplate
-- (SetMinMaxValues before SetValue; $parentLow/$parentHigh/$parentText).

TotemBar = TotemBar or {}

local ChatOut = DEFAULT_CHAT_FRAME or ChatFrame1
local optionsFrame = nil

-- Unique widget-name counters (template child labels resolve via getglobal,
-- so every widget needs a non-nil, unique frame name).
local cbIndex = 0
local slIndex = 0

-- Factory: a labeled checkbox wired to getter/setter. getter()->boolean,
-- setter(boolean). Returns the CheckButton.
local function CreateCheckbox(parent, label, getter, setter)
    cbIndex = cbIndex + 1
    local name = "TotemBarOptCheck" .. cbIndex
    local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    local lbl = getglobal(name .. "Text")
    if lbl then
        lbl:SetText(label)
        lbl:SetFontObject(GameFontNormalSmall)
    end
    cb.tbGet = getter
    cb.tbSet = setter
    cb:SetScript("OnClick", function()
        this.tbSet(this:GetChecked() == 1)
    end)
    return cb
end

-- Factory: a labeled slider wired to getter/setter over [minVal,maxVal] in
-- `step` increments. `fmt` is a printf pattern for the live value text
-- (e.g. "UI size: %.2f"). Returns the Slider.
local function CreateSlider(parent, label, minVal, maxVal, step, fmt, getter, setter)
    slIndex = slIndex + 1
    local name = "TotemBarOptSlider" .. slIndex
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetWidth(200)
    sl:SetHeight(16)
    sl:SetMinMaxValues(minVal, maxVal)   -- BEFORE SetValue, else clamps to 0
    sl:SetValueStep(step)
    local low, high, txt = getglobal(name .. "Low"), getglobal(name .. "High"), getglobal(name .. "Text")
    if low then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    sl.tbLabel = label
    sl.tbFmt = fmt
    sl.tbText = txt
    sl.tbSet = setter
    sl.tbGet = getter
    sl:SetScript("OnValueChanged", function()
        local v = this:GetValue()
        if this.tbText then
            this.tbText:SetText(string.format(this.tbFmt, v))
        end
        this.tbSet(v)
    end)
    return sl
end

-- Factory: a labeled push button wired to an onClick. Returns the Button.
local function CreateButton(parent, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(140)
    btn:SetHeight(22)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- All widgets, stored so OnShow can repopulate them from TotemBarDB.
local widgets = {}

local function BuildOptionsFrame()
    if optionsFrame then
        return optionsFrame
    end

    local f = CreateFrame("Frame", "TotemBarOptionsFrame", UIParent)
    f:SetWidth(280)
    f:SetHeight(360)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)

    local title = f:CreateFontString("TotemBarOptionsTitle", "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("TotemBar Options")

    local close = CreateFrame("Button", "TotemBarOptionsClose", f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

    -- Layout cursor.
    local x = 24
    local y = -44
    local function place(w, dy)
        w:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
        y = y + dy
    end

    -- Checkboxes.
    widgets.lock = CreateCheckbox(f, "Lock bar",
        function() return TotemBarDB.locked end,
        function(v) TotemBarDB.locked = v end)
    place(widgets.lock, -28)

    widgets.autoRecall = CreateCheckbox(f, "Auto-recall before setting",
        function() return TotemBarDB.autoRecall end,
        function(v)
            TotemBarDB.autoRecall = v
            if TotemBar.RefreshRecallIndicator then TotemBar.RefreshRecallIndicator() end
        end)
    place(widgets.autoRecall, -28)

    widgets.show = CreateCheckbox(f, "Show bar",
        function() return not TotemBarDB.hidden end,
        function(v)
            if v then
                TotemBarDB.hidden = false
                if TotemBarFrame then TotemBarFrame:Show() end
            else
                TotemBarDB.hidden = true
                if TotemBarFrame then TotemBarFrame:Hide() end
            end
        end)
    place(widgets.show, -40)

    -- Sliders (leave headroom below each for its low/high/value text).
    widgets.guard = CreateSlider(f, "Recall guard (sec)", 0, 5, 0.5, "Recall guard: %.1fs",
        function() return TotemBarDB.recallGuardSeconds end,
        function(v) TotemBarDB.recallGuardSeconds = v end)
    place(widgets.guard, -44)

    widgets.gap = CreateSlider(f, "Cycle reset gap (sec)", 0.5, 5, 0.5, "Cycle gap: %.1fs",
        function() return TotemBarDB.gapSeconds end,
        function(v) TotemBarDB.gapSeconds = v end)
    place(widgets.gap, -44)

    widgets.scale = CreateSlider(f, "UI size", 0.5, 2.0, 0.05, "UI size: %.2f",
        function() return TotemBarDB.scale end,
        function(v)
            TotemBarDB.scale = v
            if TotemBarFrame then TotemBarFrame:SetScale(v) end
        end)
    place(widgets.scale, -44)

    optionsFrame = f
    -- Buttons (Reset position, Create macro) are added in Task 4.
    if TotemBar.BuildOptionsButtons then
        TotemBar.BuildOptionsButtons(f, x, y)
    end

    -- Repopulate every widget from TotemBarDB whenever the panel shows.
    f:SetScript("OnShow", function()
        widgets.lock:SetChecked(TotemBarDB.locked and 1 or nil)
        widgets.autoRecall:SetChecked(TotemBarDB.autoRecall and 1 or nil)
        widgets.show:SetChecked((not TotemBarDB.hidden) and 1 or nil)
        widgets.guard:SetValue(TotemBar.clampValue(TotemBarDB.recallGuardSeconds, 0, 5))
        widgets.gap:SetValue(TotemBar.clampValue(TotemBarDB.gapSeconds, 0.5, 5))
        widgets.scale:SetValue(TotemBar.clampValue(TotemBarDB.scale, 0.5, 2.0))
    end)

    -- ESC closes it.
    tinsert(UISpecialFrames, "TotemBarOptionsFrame")

    f:Hide()
    return f
end

-- Show/hide the options panel (builds it lazily). Left-click on the minimap
-- button and /tb options both call this.
function TotemBar.ToggleOptions()
    local f = BuildOptionsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
```

- [ ] **Step 3: Add `/tb options` in `ui.lua`**

In `HandleSlashCommand`, add an `elseif` branch before the final `else`:

```lua
    elseif cmd == "options" or cmd == "opt" then
        TotemBar.ToggleOptions()
```

And update the usage string in the final `else` branch to include `options`:

```lua
        ChatOut:AddMessage("TotemBar: unknown command '" .. msg .. "'. Usage: /tb, /tb lock, /tb scan, /tb assign, /tb options")
```

- [ ] **Step 4: Parse-check + full suite**

Run:
```
lua50.exe -e "assert(loadfile('options.lua'))"
lua50.exe -e "assert(loadfile('ui.lua'))"
```
Then run all 8 offline suites (test_optionslogic, test_config, test_assign, test_known, test_totemdata, test_cast, test_duration, test_buffmatch) — each must pass.
Expected: parse-checks clean; all suites green.

- [ ] **Step 5: Commit**

```bash
git add TotemBar.toc options.lua ui.lua
git commit -m "TotemBar: options panel with 6 controls + ToggleOptions + /tb options"
```

---

### Task 4: Options buttons — Reset position + Create macro (`options.lua`)

**Files:**
- Modify: `options.lua` (add `TotemBar.BuildOptionsButtons`)

**Interfaces:**
- Consumes: `TotemBar.ResetPosition` (Task 2); `TotemBar.macroSpec` (Task 1); WoW `GetMacroIndexByName`/`GetNumMacros`/`CreateMacro`/`EditMacro`.
- Produces: `TotemBar.BuildOptionsButtons(frame, x, yStart)` (called by `BuildOptionsFrame` in Task 3).

- [ ] **Step 1: Add the macro-apply helper + button builder to `options.lua`**

In `options.lua`, above `function TotemBar.ToggleOptions()`, add:

```lua
-- Creates or updates the "Totems" convenience macro from TotemBar.macroSpec.
-- General (account) macro, capped at 18 in 1.12; if the cap is full and no
-- "Totems" macro exists yet, reports and does nothing. Never auto-places it
-- on the action bar (no 1.12 API for that - the player drags it).
local function ApplyTotemsMacro()
    local name, body, icon = TotemBar.macroSpec()
    local existing = GetMacroIndexByName(name)
    if existing and existing > 0 then
        EditMacro(existing, name, icon, body, 1, nil)
        ChatOut:AddMessage("TotemBar: '" .. name .. "' macro updated - drag it to your action bar.")
        return
    end
    local numGlobal = GetNumMacros()   -- returns global, perChar in 1.12
    if numGlobal and numGlobal >= 18 then
        ChatOut:AddMessage("TotemBar: macro slots full (18) - free one and retry.")
        return
    end
    CreateMacro(name, icon, body, nil)
    ChatOut:AddMessage("TotemBar: '" .. name .. "' macro created - drag it to your action bar.")
end

-- Adds the Reset-position and Create-macro buttons to the options frame.
-- Called by BuildOptionsFrame (Task 3) after the sliders, at layout cursor
-- (x, yStart). Kept separate so the panel body and the action buttons are
-- two focused units.
function TotemBar.BuildOptionsButtons(f, x, yStart)
    local reset = CreateButton(f, "Reset position", function()
        if TotemBar.ResetPosition then TotemBar.ResetPosition() end
    end)
    reset:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart)

    local macro = CreateButton(f, "Create 'Totems' macro", function()
        ApplyTotemsMacro()
    end)
    macro:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart - 28)
end
```

Note: `BuildOptionsFrame` (Task 3) already calls `TotemBar.BuildOptionsButtons(f, x, y)` when present, and `CreateButton` is a file-local defined in Task 3 — this code lives in the SAME file, below those definitions, so both are in scope.

- [ ] **Step 2: Parse-check + full suite**

Run:
```
lua50.exe -e "assert(loadfile('options.lua'))"
```
Then run all 8 offline suites — each must pass (no logic changed, this is a parse/regression gate).
Expected: parse-check clean; all suites green.

- [ ] **Step 3: Commit**

```bash
git add options.lua
git commit -m "TotemBar: options buttons - reset position + create Totems macro"
```

---

### Task 5: Minimap button (`minimap.lua`)

**Files:**
- Create: `minimap.lua`
- Modify: `TotemBar.toc` (add `minimap.lua` after `options.lua`)

**Interfaces:**
- Consumes: `TotemBar.angleToOffset` (Task 1); `TotemBar.ToggleOptions` (Task 3); `TotemBar.ToggleBar` (Task 2); `TotemBarDB.minimapAngle`.
- Produces: global frame `TotemBarMinimapButton`.

- [ ] **Step 1: Add `minimap.lua` to the TOC**

Edit `TotemBar.toc` — add `minimap.lua` after `options.lua`:

```
options.lua
minimap.lua
```

- [ ] **Step 2: Create `minimap.lua`**

Create `minimap.lua`:

```lua
-- TotemBar - minimap.lua
-- Hand-rolled minimap button (no LibDBIcon on 1.12). Orbits the minimap at a
-- saved angle, drag-repositions (angle persisted), left-click opens the
-- options panel, right-click toggles the bar. pfUI-safe: parent = Minimap,
-- name contains "Minimap", FrameStrata HIGH + level 9 (MEDIUM hides under
-- pfUI). /tb options is the guaranteed access path if pfUI collects/hides
-- the button. WoW-API file (parse-checked only).

TotemBar = TotemBar or {}

local button = nil

-- Repositions the button on its orbit for the given angle (degrees).
local function PlaceButton(angleDeg)
    if not button then
        return
    end
    local radius = (Minimap:GetWidth() / 2) + 5
    local x, y = TotemBar.angleToOffset(angleDeg, radius)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function BuildMinimapButton()
    if button then
        return
    end

    local btn = CreateFrame("Button", "TotemBarMinimapButton", Minimap)
    btn:SetWidth(31)
    btn:SetHeight(31)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(9)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Nature_TremorTotem")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(53)
    border:SetHeight(53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 5)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn.angle = TotemBarDB.minimapAngle or 225

    -- Drag (repositions around the orbit). Drag needs the movement threshold,
    -- so a plain click still fires OnClick; the two coexist (verified 1.12
    -- pattern).
    btn:RegisterForDrag("LeftButton")
    btn.isDragging = false
    btn:SetScript("OnDragStart", function() this.isDragging = true end)
    btn:SetScript("OnDragStop", function()
        this.isDragging = false
        TotemBarDB.minimapAngle = this.angle
    end)
    btn:SetScript("OnUpdate", function()
        if not this.isDragging then
            return
        end
        local mx, my = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        mx = mx / scale
        my = my / scale
        local cx, cy = Minimap:GetCenter()
        this.angle = math.deg(math.atan2(my - cy, mx - cx))
        PlaceButton(this.angle)
    end)

    -- Clicks: left = options, right = toggle bar.
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if TotemBar.ToggleBar then TotemBar.ToggleBar() end
        else
            if TotemBar.ToggleOptions then TotemBar.ToggleOptions() end
        end
    end)

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("TotemBar")
        GameTooltip:AddLine("Left-click: Options", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: Toggle bar", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: reposition", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    button = btn
    PlaceButton(btn.angle)
end

-- Build on ADDON_LOADED (SavedVariables are populated by then, same as the
-- bar). Guarded; never on PLAYER_ENTERING_WORLD (would re-run and leak
-- textures).
local ev = CreateFrame("Frame", "TotemBarMinimapEventFrame", UIParent)
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TotemBar" then
        BuildMinimapButton()
        ev:UnregisterEvent("ADDON_LOADED")
    end
end)
```

- [ ] **Step 3: Parse-check + full suite**

Run:
```
lua50.exe -e "assert(loadfile('minimap.lua'))"
```
Then run all 8 offline suites — each must pass.
Expected: parse-check clean; all suites green.

- [ ] **Step 4: Lua 5.0 lint of the new WoW-API files**

Confirm no Lua-5.0 traps in the new `options.lua` / `minimap.lua` (string-colon method calls, `#var`, `string.match`/`gmatch`). Frame-object method calls (`btn:SetWidth`, `f:Hide`) are fine — only STRING-colon methods are the trap.

Run (each should print nothing that is a string method on the new lines):
```
grep -nE "#[A-Za-z_]" options.lua minimap.lua
grep -nE "string\.(match|gmatch)" options.lua minimap.lua
```
Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add TotemBar.toc minimap.lua
git commit -m "TotemBar: pfUI-safe minimap button (orbit-drag, left=options, right=toggle)"
```

---

### Task 6: Deploy + in-game verification + KG writeback

**Files:** none (deploy + verify + knowledge)

- [ ] **Step 1: Deploy to the live client (PowerShell)**

```
robocopy "C:\dev\TotemBar" "C:\turtle\Interface\AddOns\TotemBar" /MIR /XD .git .superpowers docs /NFL /NDL /NJH /NJS /NC /NS
```
Expected: exit 0-7. Confirm `minimap.lua`, `options.lua`, `core\optionslogic.lua` exist under the live AddOns path.

- [ ] **Step 2: Full client restart**

New files were added to the `.toc` → the client must be fully restarted (close + reopen), not `/reload`ed. Ask Phil to fully restart and confirm he is back in-world. (First, `ls C:\turtle\Errors` for any new #132 after restart — a load error in a new file would crash on startup; if so, read the crash log and fix before proceeding.)

- [ ] **Step 3: In-game verification**

Have Phil confirm each:
- **Minimap button** appears on the minimap ring (totem icon + border). Hover shows the tooltip. Drag it around the ring — it follows and stays after release; `/reload` and it returns to the dragged spot (angle persisted). If pfUI hides it, `/tb options` still opens the panel.
- **Left-click** the button → options panel opens; **right-click** → bar hides/shows.
- **Panel controls**: Lock bar (bar can't be dragged when checked), Auto-recall (the "A" indicator updates), Show bar (persists across reload), Recall guard slider (changes the double-press window — set to 0 and a rapid double-press recalls again; set to 2 and it doesn't), Cycle gap slider, **UI size** slider (bar visibly scales live).
- **Reset position** re-centers the bar. **Create 'Totems' macro** creates a "Totems" macro (open the macro UI to confirm; drag it to a bar and it casts). Run it twice quickly to confirm the recall guard still holds via the macro.

Capture Phil's confirmation per item.

- [ ] **Step 4: KG writeback (only after in-game confirmation)**

POST to `http://127.0.0.1:8080/api/knowledge/nodes` (skip if PROPAGATOR offline). Two nodes, schema `domain:"wow", knowledge_class:"wissen", knowledge_type:<t>, confidence:0.9, trust_level:"agent", created_by_engine:"addon-dev-cc", metadata:{provenance_category:"konsumenten-erweitert", verification:"in-game-confirmed"}, content:<text>`:
- knowledge_type `"ui-recipe"`: the pfUI-safe minimap-button recipe AS VERIFIED on this client (parent Minimap, name contains "Minimap", FrameStrata HIGH + level 9, orbit via angleToOffset + radius from Minimap:GetWidth(), drag via GetCursorPosition()/Minimap:GetEffectiveScale() + atan2, build on guarded ADDON_LOADED, /tb options slash fallback because pfUI can collect/hide it; the exact border offset that looked right).
- knowledge_type `"ui-recipe"`: the 1.12 options-panel widget wiring that worked (UICheckButtonTemplate with getglobal(name.."Text") label + GetChecked()==1; OptionsSliderTemplate with SetMinMaxValues-before-SetValue + $parentLow/High/Text; UIPanelButtonTemplate buttons; UISpecialFrames for ESC; repopulate on OnShow).

- [ ] **Step 5: Devlog**

Append a concise entry to the current session devlog under `C:\dev\turtle-wow-kb\15-devlog\`: the minimap button + options panel feature (controls, UI-scale slider, create-macro), built subagent-driven with offline tests, in-game confirmed, committed locally on dev (not pushed), KG node ids. Commit the KB change locally.

---

## Self-Review

**Spec coverage:** minimap button (Task 5) ✅; options panel + 6 controls (Task 3) ✅; reset + create-macro buttons (Task 4) ✅; UI-scale slider (Task 3, applied live) ✅; new SVs scale/minimapAngle/hidden/recallGuardSeconds (Task 2) ✅; `ToggleOptions`/`ToggleBar`/`ResetPosition`/promoted `RefreshRecallIndicator` (Tasks 2-3) ✅; `/tb options` fallback (Task 3) ✅; macro create/update with cap check (Task 4) ✅; pure helpers offline-tested (Task 1) ✅; deploy + full restart + in-game + KG (Task 6) ✅.

**Placeholder scan:** every step has concrete code/commands; the only in-game-gated unknowns (border offset, icon render) are explicitly flagged for the Task 6 visual check, not left as code TBDs.

**Type consistency:** `angleToOffset(angleDeg, radius) -> x,y`, `clampValue(v,min,max)`, `macroSpec() -> name,body,icon` identical across definition, tests, and call sites (minimap orbit, sliders, ApplyTotemsMacro). `ToggleOptions`/`ToggleBar`/`ResetPosition`/`RefreshRecallIndicator`/`BuildOptionsButtons` names identical between definitions and callers. SV field names (`scale`/`minimapAngle`/`hidden`/`recallGuardSeconds`) consistent across config defaults, sliders, and apply sites. Load order in the TOC (`optionslogic` before `ui`; `options` then `minimap` after `ui`) matches the runtime dependencies (minimap uses ToggleOptions/ToggleBar at click time; all resolve by ADDON_LOADED).
