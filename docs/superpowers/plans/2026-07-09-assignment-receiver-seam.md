# TotemBar Assignment Receiver Seam — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a transport-agnostic seam to TotemBar so a future assigner can hand it a proposed totem set, shown as a pending suggestion the player applies with one click.

**Architecture:** New pure-logic module `core/assign.lua` owns the assignment contract, validation, pending state, and apply logic (offline-testable, WoW-API-light). `ui.lua` provides the pending-suggestion panel plus thin glue functions (`isTotemKnown`, `RefreshAll`, `ShowAssignPanel`, `HideAssignPanel`) that `assign.lua` calls through optional hook slots. A `/tb assign` dev command injects a sample assignment to exercise the whole flow without any transport.

**Tech Stack:** Lua 5.0 (WoW 1.12.1 / TurtleWoW), real Lua 5.0.3 (`lua50.exe`) for offline tests, existing `tools/luatests/harness.lua`.

## Global Constraints

- Lua 5.0 only — no `#table`, no string `:method` calls, no `string.match`/`gmatch`, no `table.wipe`, no `C_Timer`. Use `table.getn`, `string.find(s, p, 1, true)`, reassign `{}` to clear.
- All frames named with the `TotemBar` prefix (no anonymous frames); pool/reuse widgets, no per-frame allocation.
- All user-facing strings in **English**.
- Element keys are exactly `TotemBar.TOTEM_ELEMENTS` = `{ "Fire", "Earth", "Water", "Air" }`.
- Offline tests run from the repo root: `lua50.exe tools/luatests/test_x.lua`.
- Local client is `C:\turtle`; deploy via `robocopy C:\dev\TotemBar C:\turtle\Interface\AddOns\TotemBar /MIR` **from PowerShell** (Git-Bash mangles `/MIR`).
- Do NOT push to GitHub (push paused) — local commits only, on `dev`.
- `.toc` change in this plan → **full client restart** required (not `/reload`).

---

### Task 1: Pure assignment logic (`core/assign.lua`)

**Files:**
- Create: `core/assign.lua`
- Test: `tools/luatests/test_assign.lua`

**Interfaces:**
- Consumes: `TotemBar.TOTEM_ELEMENTS` (from `core/totemdata.lua`); global `TotemBarDB` (stubbed in tests).
- Produces:
  - `TotemBar.isElement(key) -> boolean`
  - `TotemBar.validateAssignment(set) -> true | (false, reasonString)`
  - `TotemBar.copySet(set) -> table` (only valid element keys kept)
  - `TotemBar.GetChosenSet() -> table` (fresh copy of `TotemBarDB.chosen`, element keys only)
  - `TotemBar.filterKnown(set, isKnownFn) -> appliedTable, skippedTable`

- [ ] **Step 1: Write the failing test**

Create `tools/luatests/test_assign.lua`:

```lua
-- Offline test: core/assign.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_assign.lua

dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")
dofile("core/assign.lua")

H.run("isElement: valid and invalid keys", function()
    H.assert_eq(TotemBar.isElement("Fire"), true, "Fire is an element")
    H.assert_eq(TotemBar.isElement("Air"), true, "Air is an element")
    H.assert_eq(TotemBar.isElement("Spirit"), false, "Spirit is not an element")
    H.assert_eq(TotemBar.isElement(nil), false, "nil is not an element")
end)

H.run("validateAssignment: accepts a valid set", function()
    local ok = TotemBar.validateAssignment({ Fire = "Searing Totem", Air = "Windfury Totem" })
    H.assert_eq(ok, true, "valid set accepted")
end)

H.run("validateAssignment: rejects non-table", function()
    local ok, reason = TotemBar.validateAssignment("nope")
    H.assert_eq(ok, false, "string rejected")
    H.assert_eq(type(reason), "string", "reason is a string")
end)

H.run("validateAssignment: rejects empty set", function()
    local ok = TotemBar.validateAssignment({})
    H.assert_eq(ok, false, "empty set rejected")
end)

H.run("validateAssignment: rejects unknown element key", function()
    local ok = TotemBar.validateAssignment({ Spirit = "Ghost Totem" })
    H.assert_eq(ok, false, "unknown element key rejected")
end)

H.run("validateAssignment: rejects non-string / empty totem name", function()
    H.assert_eq(TotemBar.validateAssignment({ Fire = 123 }), false, "numeric name rejected")
    H.assert_eq(TotemBar.validateAssignment({ Fire = "" }), false, "empty name rejected")
end)

H.run("copySet: keeps only element keys, returns a copy", function()
    local src = { Fire = "Searing Totem", Junk = "x" }
    local out = TotemBar.copySet(src)
    H.assert_eq(out.Fire, "Searing Totem", "Fire copied")
    H.assert_eq(out.Junk, nil, "non-element key dropped")
    out.Fire = "changed"
    H.assert_eq(src.Fire, "Searing Totem", "source not mutated (copy)")
end)

H.run("GetChosenSet: returns a fresh copy of TotemBarDB.chosen", function()
    TotemBarDB = { chosen = { Fire = "Magma Totem", Water = "Mana Spring Totem" } }
    local snap = TotemBar.GetChosenSet()
    H.assert_eq(snap.Fire, "Magma Totem", "Fire chosen read")
    H.assert_eq(snap.Water, "Mana Spring Totem", "Water chosen read")
    snap.Fire = "mutated"
    H.assert_eq(TotemBarDB.chosen.Fire, "Magma Totem", "underlying DB not mutated")
    TotemBarDB = nil
end)

H.run("filterKnown: splits by predicate", function()
    local set = { Fire = "Searing Totem", Air = "Windfury Totem" }
    local isKnown = function(name) return name == "Searing Totem" end
    local applied, skipped = TotemBar.filterKnown(set, isKnown)
    H.assert_eq(applied.Fire, "Searing Totem", "known kept in applied")
    H.assert_eq(applied.Air, nil, "unknown not in applied")
    H.assert_eq(skipped.Air, "Windfury Totem", "unknown in skipped")
    H.assert_eq(skipped.Fire, nil, "known not in skipped")
end)

H.summary()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua50.exe tools/luatests/test_assign.lua`
Expected: FAIL — `core/assign.lua` does not exist (`cannot open core/assign.lua`).

- [ ] **Step 3: Write minimal implementation**

Create `core/assign.lua`:

```lua
-- TotemBar - core/assign.lua
-- Assignment receiver seam: the contract + pure logic by which an external
-- assigner (future "ShamiPower") hands TotemBar a proposed totem set.
-- WoW-API-light so the logic below is offline-testable under real Lua 5.0.
-- The pending-suggestion UI lives in ui.lua and is reached through the
-- optional hook slots (ShowAssignPanel/HideAssignPanel/isTotemKnown/
-- RefreshAll) that ui.lua fills in at load time.
--
-- An "assignment set" is a table keyed by element -> totem spell name:
--   { Fire = "Searing Totem", Air = "Windfury Totem", ... }
-- Any subset of elements; a missing element means "nothing for that slot".

TotemBar = TotemBar or {}

-- True if `key` is one of the four totem elements.
function TotemBar.isElement(key)
    if not key then
        return false
    end
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        if elements[i] == key then
            return true
        end
    end
    return false
end

-- Validates an assignment set. Returns true, or false plus a reason string.
function TotemBar.validateAssignment(set)
    if type(set) ~= "table" then
        return false, "set must be a table"
    end
    local count = 0
    for k, v in pairs(set) do
        if not TotemBar.isElement(k) then
            return false, "unknown element key: " .. tostring(k)
        end
        if type(v) ~= "string" or v == "" then
            return false, "totem name for " .. tostring(k) .. " must be a non-empty string"
        end
        count = count + 1
    end
    if count == 0 then
        return false, "set is empty"
    end
    return true
end

-- Shallow copy of a set, keeping only valid element keys.
function TotemBar.copySet(set)
    local out = {}
    if type(set) == "table" then
        for k, v in pairs(set) do
            if TotemBar.isElement(k) then
                out[k] = v
            end
        end
    end
    return out
end

-- Fresh copy (element -> name) of the currently chosen totems.
function TotemBar.GetChosenSet()
    local out = {}
    local chosen = TotemBarDB and TotemBarDB.chosen
    if chosen then
        local elements = TotemBar.TOTEM_ELEMENTS
        for i = 1, table.getn(elements) do
            local e = elements[i]
            if chosen[e] then
                out[e] = chosen[e]
            end
        end
    end
    return out
end

-- Splits a set into applied (isKnown(name) true) and skipped (false).
function TotemBar.filterKnown(set, isKnown)
    local applied, skipped = {}, {}
    for k, v in pairs(set) do
        if isKnown(v) then
            applied[k] = v
        else
            skipped[k] = v
        end
    end
    return applied, skipped
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua50.exe tools/luatests/test_assign.lua`
Expected: PASS — ends with `... assertion(s) passed.`

- [ ] **Step 5: Commit**

```bash
git add core/assign.lua tools/luatests/test_assign.lua
git commit -m "TotemBar: add pure assignment-set logic (validate/copy/getchosen/filter)"
```

---

### Task 2: Pending-assignment state machine (`core/assign.lua`)

**Files:**
- Modify: `core/assign.lua` (append)
- Test: `tools/luatests/test_assign.lua` (append)

**Interfaces:**
- Consumes: `TotemBar.validateAssignment`, `TotemBar.copySet`, `TotemBar.filterKnown` (Task 1); optional hook slots read at call time: `TotemBar.ShowAssignPanel`, `TotemBar.HideAssignPanel`, `TotemBar.isTotemKnown`, `TotemBar.RefreshAll`, `TotemBar.onAssignmentApplied`; global `TotemBarDB`.
- Produces:
  - `TotemBar.pending` — `{ set = table, label = string|nil }` or `nil`
  - `TotemBar.ReceiveAssignment(set, label) -> true | (false, reason)`
  - `TotemBar.ClearAssignment()`
  - `TotemBar.ApplyPending()`

- [ ] **Step 1: Write the failing test**

Append to `tools/luatests/test_assign.lua` **before** the final `H.summary()` line:

```lua
H.run("ReceiveAssignment: stores pending + calls ShowAssignPanel", function()
    TotemBar.pending = nil
    local shown = false
    TotemBar.ShowAssignPanel = function() shown = true end
    local ok = TotemBar.ReceiveAssignment({ Fire = "Searing Totem" }, "TEST")
    H.assert_eq(ok, true, "valid assignment accepted")
    H.assert_eq(TotemBar.pending.set.Fire, "Searing Totem", "pending set stored")
    H.assert_eq(TotemBar.pending.label, "TEST", "pending label stored")
    H.assert_eq(shown, true, "ShowAssignPanel called")
    TotemBar.ShowAssignPanel = nil
end)

H.run("ReceiveAssignment: rejects invalid, no pending set", function()
    TotemBar.pending = nil
    local ok = TotemBar.ReceiveAssignment({}, "x")
    H.assert_eq(ok, false, "empty set rejected")
    H.assert_eq(TotemBar.pending, nil, "no pending stored on reject")
end)

H.run("ClearAssignment: drops pending + calls HideAssignPanel", function()
    TotemBar.pending = { set = { Fire = "Searing Totem" }, label = "x" }
    local hidden = false
    TotemBar.HideAssignPanel = function() hidden = true end
    TotemBar.ClearAssignment()
    H.assert_eq(TotemBar.pending, nil, "pending cleared")
    H.assert_eq(hidden, true, "HideAssignPanel called")
    TotemBar.HideAssignPanel = nil
end)

H.run("ApplyPending: writes known totems to chosen, skips unknown, clears", function()
    TotemBarDB = { chosen = {} }
    TotemBar.pending = {
        set = { Fire = "Searing Totem", Air = "Windfury Totem" }, label = "TEST",
    }
    TotemBar.isTotemKnown = function(name) return name == "Searing Totem" end
    local refreshed = false
    TotemBar.RefreshAll = function() refreshed = true end
    local appliedArg = nil
    TotemBar.onAssignmentApplied = function(s) appliedArg = s end

    TotemBar.ApplyPending()

    H.assert_eq(TotemBarDB.chosen.Fire, "Searing Totem", "known totem applied")
    H.assert_eq(TotemBarDB.chosen.Air, nil, "unknown totem skipped")
    H.assert_eq(refreshed, true, "RefreshAll called")
    H.assert_eq(appliedArg.Fire, "Searing Totem", "onAssignmentApplied got applied set")
    H.assert_eq(TotemBar.pending, nil, "pending cleared after apply")

    TotemBar.isTotemKnown = nil
    TotemBar.RefreshAll = nil
    TotemBar.onAssignmentApplied = nil
    TotemBarDB = nil
end)

H.run("ApplyPending: no-op when nothing pending", function()
    TotemBar.pending = nil
    TotemBar.ApplyPending()   -- must not error
    H.assert_eq(TotemBar.pending, nil, "still nil")
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua50.exe tools/luatests/test_assign.lua`
Expected: FAIL — `ReceiveAssignment`/`ClearAssignment`/`ApplyPending` are nil (attempt to call a nil value).

- [ ] **Step 3: Write minimal implementation**

Append to `core/assign.lua`:

```lua
-- Current pending assignment: { set = {element=name,...}, label = string } or nil.
-- In-memory only (not a SavedVariable) - an assignment is ephemeral coordination.
TotemBar.pending = nil

-- Optional hook, filled by an external assigner: called with the applied
-- set table after the player accepts. Nil by default.
TotemBar.onAssignmentApplied = nil

-- THE SEAM. An external assigner calls this to propose a set. Validates,
-- stores it as the pending suggestion (replacing any prior), and asks the
-- UI to show the panel. Does NOT apply. Returns true, or false + reason.
function TotemBar.ReceiveAssignment(set, label)
    local ok, reason = TotemBar.validateAssignment(set)
    if not ok then
        return false, reason
    end
    TotemBar.pending = { set = TotemBar.copySet(set), label = label }
    if TotemBar.ShowAssignPanel then
        TotemBar.ShowAssignPanel()
    end
    return true
end

-- Drops any pending suggestion and hides the panel (decline / post-apply).
function TotemBar.ClearAssignment()
    TotemBar.pending = nil
    if TotemBar.HideAssignPanel then
        TotemBar.HideAssignPanel()
    end
end

-- Applies the pending suggestion: sets each KNOWN totem as the chosen
-- default for its element (unknown totems are skipped), refreshes the bar,
-- clears pending, hides the panel, and fires onAssignmentApplied. No cast.
function TotemBar.ApplyPending()
    local p = TotemBar.pending
    if not p then
        return
    end
    local isKnown = TotemBar.isTotemKnown or function() return true end
    local applied = TotemBar.filterKnown(p.set, isKnown)
    TotemBarDB.chosen = TotemBarDB.chosen or {}
    for element, name in pairs(applied) do
        TotemBarDB.chosen[element] = name
    end
    if TotemBar.RefreshAll then
        TotemBar.RefreshAll()
    end
    TotemBar.pending = nil
    if TotemBar.HideAssignPanel then
        TotemBar.HideAssignPanel()
    end
    if TotemBar.onAssignmentApplied then
        TotemBar.onAssignmentApplied(applied)
    end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua50.exe tools/luatests/test_assign.lua`
Expected: PASS — all assertions pass.

- [ ] **Step 5: Commit**

```bash
git add core/assign.lua tools/luatests/test_assign.lua
git commit -m "TotemBar: add pending-assignment state machine (receive/clear/apply)"
```

---

### Task 3: Wire `assign.lua` into the addon + ui.lua glue

**Files:**
- Modify: `TotemBar.toc` (add `core\assign.lua` before `ui.lua`)
- Modify: `ui.lua` (register glue functions)

**Interfaces:**
- Consumes: local `FindSpellIndexByName`, local `RefreshButton`, `TotemBar.TOTEM_ELEMENTS` (all in `ui.lua`).
- Produces (globals other code reads): `TotemBar.isTotemKnown(name) -> boolean`, `TotemBar.RefreshAll()`.

- [ ] **Step 1: Add the module to the TOC**

Edit `TotemBar.toc` — insert `core\assign.lua` immediately after `core\config.lua` and before `ui.lua`:

```
core\totemdata.lua
core\known.lua
core\cast.lua
core\config.lua
core\assign.lua
ui.lua
```

- [ ] **Step 2: Add the glue in ui.lua**

In `ui.lua`, immediately after the `RefreshCooldown = function(element) ... end` block ends (i.e. right before the `-- Lazily builds the single shared flyout frame` comment / `EnsureFlyoutFrame = function()`), insert:

```lua
-- Glue for core/assign.lua's pending-assignment logic: it stays WoW-API-
-- light and reaches the spellbook / bar refresh through these slots.
-- isTotemKnown resolves a totem name against the live spellbook; RefreshAll
-- re-skins every element button (used after a pending assignment is applied).
TotemBar.isTotemKnown = function(name)
    return FindSpellIndexByName(name) ~= nil
end

TotemBar.RefreshAll = function()
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        RefreshButton(elements[i])
    end
end
```

- [ ] **Step 3: Syntax-check both changed files (parse only, no execution)**

Run:
```
lua50.exe -e "assert(loadfile('core/assign.lua'))"
lua50.exe -e "assert(loadfile('ui.lua'))"
```
Expected: no output, exit 0 for each (a syntax error would print a `.lua:LINE:` message).

- [ ] **Step 4: Re-run the full offline suite (nothing regressed)**

Run each and confirm all pass:
```
lua50.exe tools/luatests/test_assign.lua
lua50.exe tools/luatests/test_known.lua
lua50.exe tools/luatests/test_totemdata.lua
lua50.exe tools/luatests/test_cast.lua
lua50.exe tools/luatests/test_duration.lua
lua50.exe tools/luatests/test_buffmatch.lua
```
Expected: each ends with `... assertion(s) passed.`

- [ ] **Step 5: Commit**

```bash
git add TotemBar.toc ui.lua
git commit -m "TotemBar: load assign.lua and register isTotemKnown/RefreshAll glue"
```

---

### Task 4: Pending-suggestion panel (`ui.lua`)

**Files:**
- Modify: `ui.lua` (new `TotemBarAssignFrame` + Show/Hide + Ensure builder + forward decls)

**Interfaces:**
- Consumes: `TotemBar.pending`, `TotemBar.ApplyPending`, `TotemBar.ClearAssignment` (Tasks 1-2); `TotemBar.TOTEM_ELEMENTS`; local `GetElementIcon`-style resolution via `FindSpellIndexByName` + `GetSpellTexture`; `EMPTY_ICON`; `TotemBarFrame`; `BUTTON_SIZE`, `BUTTON_GAP`.
- Produces (globals): `TotemBar.ShowAssignPanel()`, `TotemBar.HideAssignPanel()`.

- [ ] **Step 1: Add forward declarations**

In `ui.lua`, in the forward-declaration block (near `local CreateElementButton`, around line 77), add:

```lua
local EnsureAssignFrame
local assignFrame        -- lazily created pending-suggestion panel
```

- [ ] **Step 2: Add a spellbook icon resolver for a specific totem name**

`GetElementIcon` resolves the *chosen* totem; the panel needs the icon for an *arbitrary* name plus a known/unknown flag. In `ui.lua`, right after the `GetElementIcon` function (ends ~line 118), add:

```lua
-- Resolves (iconTexture, known) for an arbitrary totem name: the spellbook
-- texture when the player knows it, else the empty/question-mark icon and
-- known=false (the pending panel greys unknown totems).
local function ResolveTotemIcon(name)
    if not name then
        return EMPTY_ICON, false
    end
    local idx = FindSpellIndexByName(name)
    if not idx then
        return EMPTY_ICON, false
    end
    local texture = GetSpellTexture(idx, BOOKTYPE_SPELL)
    return texture or EMPTY_ICON, true
end
```

- [ ] **Step 3: Build the panel builder + Show/Hide**

In `ui.lua`, immediately before `function TotemBar.BuildUI()` (~line 809), add:

```lua
-- Lazily builds the pending-suggestion panel: a heading label, a row of up
-- to 4 element-ordered totem icons, an Accept button, and a close "X".
-- Built once, reused; event-driven show/hide (no OnUpdate, no per-frame
-- allocation). Anchored above the bar.
EnsureAssignFrame = function()
    if assignFrame then
        return assignFrame
    end

    local f = CreateFrame("Frame", "TotemBarAssignFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetWidth(4 * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP + 40)
    f:SetHeight(BUTTON_SIZE + 34)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetClampedToScreen(true)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", TotemBarFrame, "TOP", 0, 6)

    local heading = f:CreateFontString("TotemBarAssignHeading", "OVERLAY")
    heading:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    heading:SetPoint("TOP", f, "TOP", 0, -6)
    heading:SetText("Assigned set")
    f.heading = heading

    f.icons = {}
    for i = 1, 4 do
        local ico = f:CreateTexture("TotemBarAssignIcon" .. i, "ARTWORK")
        ico:SetWidth(BUTTON_SIZE)
        ico:SetHeight(BUTTON_SIZE)
        ico:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
            BUTTON_GAP + (i - 1) * (BUTTON_SIZE + BUTTON_GAP), 6)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.icons[i] = ico
    end

    local accept = CreateFrame("Button", "TotemBarAssignAccept", f, "UIPanelButtonTemplate")
    accept:SetWidth(28)
    accept:SetHeight(BUTTON_SIZE)
    accept:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    accept:SetText("OK")
    accept:SetScript("OnClick", function()
        TotemBar.ApplyPending()
    end)
    accept:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Apply assigned set")
        GameTooltip:AddLine("Sets these as your chosen totems (no cast).", 1, 1, 1)
        GameTooltip:Show()
    end)
    accept:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.accept = accept

    local close = CreateFrame("Button", "TotemBarAssignClose", f, "UIPanelCloseButton")
    close:SetWidth(22)
    close:SetHeight(22)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        TotemBar.ClearAssignment()
    end)
    f.close = close

    f:Hide()
    assignFrame = f
    return f
end

-- Populates and shows the panel from TotemBar.pending. Unknown totems are
-- greyed (desaturated + dimmed). Called by ReceiveAssignment via the hook.
TotemBar.ShowAssignPanel = function()
    local p = TotemBar.pending
    if not p then
        return
    end
    local f = EnsureAssignFrame()
    f.heading:SetText(p.label or "Assigned set")

    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, 4 do
        local element = elements[i]
        local name = element and p.set[element]
        local ico = f.icons[i]
        if name then
            local tex, known = ResolveTotemIcon(name)
            ico:SetTexture(tex)
            if known then
                ico:SetVertexColor(1, 1, 1)
                ico:SetAlpha(1)
            else
                ico:SetVertexColor(0.5, 0.5, 0.5)
                ico:SetAlpha(0.5)
            end
            ico:Show()
        else
            ico:Hide()
        end
    end
    f:Show()
end

-- Hides the panel (called by ClearAssignment / ApplyPending via the hook).
TotemBar.HideAssignPanel = function()
    if assignFrame then
        assignFrame:Hide()
    end
end
```

- [ ] **Step 4: Syntax-check ui.lua (parse only)**

Run: `lua50.exe -e "assert(loadfile('ui.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ui.lua
git commit -m "TotemBar: add pending-suggestion panel (icons, OK/close, unknown greying)"
```

---

### Task 5: `/tb assign` dev command + help line

**Files:**
- Modify: `ui.lua` (`HandleSlashCommand`, ~lines 878-898)

**Interfaces:**
- Consumes: `TotemBar.ReceiveAssignment` (Task 2).
- Produces: `/tb assign` command behavior.

- [ ] **Step 1: Add the `assign` branch**

In `ui.lua`, in `HandleSlashCommand`, add an `elseif` branch for `"assign"` before the final `else` (unknown-command) branch:

```lua
    elseif cmd == "assign" then
        -- Dev aid: inject a sample assignment to exercise the pending panel
        -- + accept/decline flow end-to-end without any transport.
        local sample = {
            Fire  = "Searing Totem",
            Earth = "Strength of Earth Totem",
            Water = "Mana Spring Totem",
            Air   = "Grace of Air Totem",
        }
        local ok, reason = TotemBar.ReceiveAssignment(sample, "TEST assignment")
        if ok then
            ChatOut:AddMessage("TotemBar: injected TEST assignment (click OK on the panel to apply).")
        else
            ChatOut:AddMessage("TotemBar: assign failed - " .. tostring(reason))
        end
```

- [ ] **Step 2: Update the usage/help line**

In the same function, in the final `else` branch, change the usage string to include `assign`:

Find:
```lua
        ChatOut:AddMessage("TotemBar: unknown command '" .. msg .. "'. Usage: /tb, /tb lock, /tb scan")
```
Replace with:
```lua
        ChatOut:AddMessage("TotemBar: unknown command '" .. msg .. "'. Usage: /tb, /tb lock, /tb scan, /tb assign")
```

- [ ] **Step 3: Syntax-check ui.lua (parse only)**

Run: `lua50.exe -e "assert(loadfile('ui.lua'))"`
Expected: no output, exit 0.

- [ ] **Step 4: Mechanical Lua 5.0 lint of the new code**

Confirm no Lua-5.0 traps were introduced in `core/assign.lua` / `ui.lua` additions:
- No `#tbl` length operator.
- No string method calls (`name:find`, `s:sub`, …) — use `string.xxx(...)`.
- No `string.match` / `string.gmatch`.

Run (should print nothing):
```
grep -nE "#[A-Za-z_]" core/assign.lua
grep -nE "[A-Za-z0-9_)\"']:(find|sub|gsub|upper|lower|len|format|gmatch|match)\(" core/assign.lua ui.lua
grep -nE "string\.(match|gmatch)" core/assign.lua ui.lua
```
Expected: no matches from the new code (pre-existing matches elsewhere in ui.lua are out of scope; verify any hit is not in the lines this plan added).

- [ ] **Step 5: Commit**

```bash
git add ui.lua
git commit -m "TotemBar: add /tb assign dev command to test the assignment seam"
```

---

### Task 6: Deploy + in-game verification + KG writeback

**Files:** none (deploy + verify + knowledge)

**Interfaces:** none.

- [ ] **Step 1: Deploy to the live client (PowerShell)**

Run in PowerShell (not Git-Bash):
```
robocopy "C:\dev\TotemBar" "C:\turtle\Interface\AddOns\TotemBar" /MIR /NFL /NDL /NJH /NJS /NC /NS
```
Expected: exit code 0-7 (1 = files copied). Confirm `core\assign.lua` now exists under the live AddOns path.

- [ ] **Step 2: Full client restart (TOC changed → /reload is NOT enough)**

A new file was added to the `.toc`, so the client must be fully restarted (close + reopen), not `/reload`ed. `askreload` only does `ReloadUI()` and will NOT pick up the new file. Ask Phil to fully restart the WoW client, and wait for confirmation that he is back in-world.

- [ ] **Step 3: In-game verification — happy path**

Have Phil run `/tb assign`, then observe:
- the pending panel appears above the bar with heading "TEST assignment" and 4 totem icons (Searing / Strength of Earth / Mana Spring / Grace of Air) shown in color (assuming he knows them);
- clicking **OK** applies them — the 4 element buttons update to those totems (icons + hover tooltips), the panel closes, and no totems are auto-cast;
- dropping via the normal element-button click / "Totems" macro still works.

Capture confirmation from Phil (or a `debug`/screenshot-free readout he reports).

- [ ] **Step 4: In-game verification — decline + unknown**

- `/tb assign` again, then click the **X** (close): panel hides, chosen totems unchanged.
- If feasible, temporarily edit the `sample` in `/tb assign` to include a totem Phil does NOT know (e.g. `Water = "Mana Tide Totem"` if unlearned), redeploy + restart, `/tb assign`: that icon shows greyed and is skipped on OK (the other three still apply). Revert the sample afterward. (Optional if a suitable unknown totem isn't handy.)

- [ ] **Step 5: KG writeback (only after in-game confirmation)**

POST the seam contract to the KG so ShamiPower can be built against a recorded interface. If PROPAGATOR (`127.0.0.1:8080`) is offline, skip (not fatal).
```
curl -s -X POST http://127.0.0.1:8080/api/knowledge/nodes \
  -H "Content-Type: application/json" \
  -d '{"domain":"wow","knowledge_class":"wissen","knowledge_type":"addon-interface","confidence":0.9,"trust_level":"agent","created_by_engine":"addon-dev-cc","metadata":{"provenance_category":"konsumenten-erweitert","verification":"in-game-confirmed"},"content":"TotemBar (TurtleWoW shaman addon) exposes an assignment-receiver seam for a future assigner (\"ShamiPower\"): TotemBar.ReceiveAssignment(set, label) where set = { Fire=totemName, Earth=..., Water=..., Air=... } (any subset; element keys = TotemBar.TOTEM_ELEMENTS). It stores the set as an in-memory PENDING suggestion and shows a panel; the player applies it with one click (sets TotemBarDB.chosen, no auto-cast); unknown totems are greyed and skipped. Also: TotemBar.GetChosenSet() returns a copy of the current chosen totems; TotemBar.ClearAssignment() drops the pending; TotemBar.onAssignmentApplied(appliedSet) optional hook fires on accept. Transport (SendAddonMessage) is intentionally NOT in TotemBar - the assigner owns it and calls ReceiveAssignment. In-game confirmed via /tb assign."}'
```
Expected: a new node id in the response, or a connection error → report "PROPAGATOR offline, skipped".

- [ ] **Step 6: Devlog**

Append a short entry to the current session devlog under `C:\dev\turtle-wow-kb\15-devlog\` (the Session 73/74 file): what was built (TotemBar assignment-receiver seam), the design (pending suggestion + 1-click apply, transport deferred), status (offline tests green, in-game confirmed, committed locally on dev, not pushed), and the KG node id. Commit the KB change locally (do not push).

---

## Self-Review

**Spec coverage:**
- Data contract → Task 1 (`validateAssignment`, `copySet`, element keys) ✅
- `ReceiveAssignment` / `GetChosenSet` / `ClearAssignment` / `onAssignmentApplied` → Tasks 1-2 ✅
- Pending panel (icons, label, Accept, decline, unknown greying) → Task 4 ✅
- Apply = set-only, no auto-cast → Task 2 `ApplyPending` + Task 4 tooltip ✅
- In-memory-only persistence → Task 2 (comment; no SavedVariable added) ✅
- `/tb assign` dev command + help → Task 5 ✅
- Offline Lua 5.0 tests for pure helpers → Tasks 1-2 ✅
- In-game verification + KG writeback → Task 6 ✅
- `core/assign.lua` new, `ui.lua` + `TotemBar.toc` modified, `tools/luatests/test_assign.lua` new → Tasks 1-5 ✅
- Deferred (transport, assigner UI, live coverage) → not implemented, noted in Task 6 KG note ✅

**Placeholder scan:** No TBD/TODO; every code + test step shows full code; the only optional step (Task 6 Step 4 unknown-totem case) is explicitly marked optional with a concrete fallback.

**Type consistency:** `set` shape `{element=name}` consistent across all tasks; `filterKnown` returns `(applied, skipped)` and `ApplyPending` uses only `applied`; hook names (`ShowAssignPanel`/`HideAssignPanel`/`isTotemKnown`/`RefreshAll`/`onAssignmentApplied`) identical in `assign.lua` calls and `ui.lua` definitions; `ReceiveAssignment`/`ClearAssignment`/`ApplyPending`/`GetChosenSet`/`isElement`/`validateAssignment`/`copySet` names identical between definitions, tests, and consumers.
