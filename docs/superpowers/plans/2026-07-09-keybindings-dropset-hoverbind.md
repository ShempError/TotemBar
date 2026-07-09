# TotemBar Keybindings + Drop-Set Button + Hover-Bind Mode — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add a drop-set bar button, Esc→Key-Bindings entries for every TotemBar action (incl. each individual totem), and a Dominos-style hover-bind mode.

**Architecture:** Pure bind-logic (name sanitize, modifier assembly, frame→action mapping) in `core/bindlogic.lua` (offline-tested). A generated static `Bindings.xml` + a `bind.lua` (label globals, cast entry points, hover-bind mode). `ui.lua` gets the drop-set button + bind-mode overlays; `options.lua` gets a bind-mode toggle. Bindings persist via the client (`SaveBindings`), no new SavedVariables.

**Tech Stack:** Lua 5.0 (WoW 1.12.1 / TurtleWoW), real Lua 5.0.3 (`lua50.exe`) for offline tests + XML generation, existing `tools/luatests/harness.lua`.

## Global Constraints

- Lua 5.0 only — no `#table`, no string `:method` calls, no `string.match`/`gmatch` (use `string.gsub`/`string.find`/`string.upper`), no `table.wipe`, no `C_Timer`. `table.getn`, `setglobal`/`getglobal`.
- All frames named with the `TotemBar` prefix. English strings.
- Key bindings persist client-side via `SaveBindings(GetCurrentBindingSet())` — NO addon SavedVariables for bindings. Bind mode is transient (off on load).
- `Bindings.xml` must be listed in the `.toc` **before** `bind.lua` (which sets the `BINDING_*` globals). Binding `name` → global `BINDING_NAME_<name>`; `header` → `BINDING_HEADER_<header>` (header attr only on the first binding of a group).
- 1.12 binding commands used: `"CLICK <GlobalButtonName>:LeftButton"`, a binding `name`, and cast-by-name in binding bodies. Modifier order in key strings: `ALT-CTRL-SHIFT-key`.
- Existing global button names: `TotemBarButtonFire/Earth/Water/Air`, `TotemBarButtonRecall`. New: `TotemBarButtonDropSet`. Flyout icons: `TotemBarFlyoutIcon1..6` (pooled; each has `.totemName` when shown).
- Offline tests + XML generation run from repo root: `lua50.exe tools/luatests/test_x.lua`. Exe `C:\Users\muell\AppData\Local\Programs\Lua50\lua50.exe` (Bash `/c/...`).
- Deploy `robocopy … /MIR` via PowerShell excl `.git/.superpowers/docs/tools`. Local commits on `dev`; push `dev`→`master` only at release.
- New files (`Bindings.xml`, `bind.lua`, `core/bindlogic.lua`) → **full client restart** for the in-game task.
- Two KG-UNVERIFIED points to confirm in the in-game task, NOT to block earlier tasks: (a) a plain Frame's `OnKeyDown` passes `arg1` = string key name; (b) mouse-wheel binding key strings. Build assuming the standard vanilla idiom.

---

### Task 1: Pure bind-logic (`core/bindlogic.lua`)

**Files:** Create `core/bindlogic.lua`; Test `tools/luatests/test_bindlogic.lua`.

**Interfaces produced:**
- `TotemBar.bindingSuffix(name) -> string` (uppercase, non-alnum runs → `_`, trimmed)
- `TotemBar.modifierPrefix(isAlt, isCtrl, isShift) -> string`
- `TotemBar.actionForButton(frameName, totemName) -> commandString | nil`

- [ ] **Step 1: Write the failing test** — create `tools/luatests/test_bindlogic.lua`:

```lua
-- Offline test: core/bindlogic.lua pure helpers. Run from repo root:
--   lua50.exe tools/luatests/test_bindlogic.lua
dofile("tools/luatests/harness.lua")

TotemBar = {}
dofile("core/totemdata.lua")   -- TOTEM_ELEMENTS
dofile("core/bindlogic.lua")

H.run("bindingSuffix: uppercase + non-alnum to underscore", function()
    H.assert_eq(TotemBar.bindingSuffix("Searing Totem"), "SEARING_TOTEM", "spaces")
    H.assert_eq(TotemBar.bindingSuffix("Grace of Air Totem"), "GRACE_OF_AIR_TOTEM", "multi word")
    H.assert_eq(TotemBar.bindingSuffix("Fire Nova Totem"), "FIRE_NOVA_TOTEM", "three words")
    H.assert_eq(TotemBar.bindingSuffix(nil), "", "nil -> empty")
end)

H.run("modifierPrefix: order ALT-CTRL-SHIFT", function()
    H.assert_eq(TotemBar.modifierPrefix(nil, nil, nil), "", "none")
    H.assert_eq(TotemBar.modifierPrefix(nil, nil, 1), "SHIFT-", "shift")
    H.assert_eq(TotemBar.modifierPrefix(1, nil, nil), "ALT-", "alt")
    H.assert_eq(TotemBar.modifierPrefix(1, 1, 1), "ALT-CTRL-SHIFT-", "all three, in order")
    H.assert_eq(TotemBar.modifierPrefix(nil, 1, 1), "CTRL-SHIFT-", "ctrl+shift")
end)

H.run("actionForButton: buttons -> CLICK, flyout totem -> named binding", function()
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonFire", nil), "CLICK TotemBarButtonFire:LeftButton", "element")
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonRecall", nil), "CLICK TotemBarButtonRecall:LeftButton", "recall")
    H.assert_eq(TotemBar.actionForButton("TotemBarButtonDropSet", nil), "CLICK TotemBarButtonDropSet:LeftButton", "dropset")
    H.assert_eq(TotemBar.actionForButton("TotemBarFlyoutIcon1", "Searing Totem"), "TOTEMBAR_TOTEM_SEARING_TOTEM", "flyout totem")
    H.assert_eq(TotemBar.actionForButton("SomethingElse", nil), nil, "unknown -> nil")
    H.assert_eq(TotemBar.actionForButton(nil, nil), nil, "nil -> nil")
end)

H.summary()
```

- [ ] **Step 2: Run test → FAIL** — `lua50.exe tools/luatests/test_bindlogic.lua` → cannot open `core/bindlogic.lua`.

- [ ] **Step 3: Implement `core/bindlogic.lua`:**

```lua
-- TotemBar - core/bindlogic.lua
-- PURE helpers for keybindings + hover-bind mode (no WoW API), offline-testable.

TotemBar = TotemBar or {}

-- Binding-name suffix for a totem: uppercase, non-alphanumeric runs -> "_",
-- trimmed. "Grace of Air Totem" -> "GRACE_OF_AIR_TOTEM". MUST match the
-- Bindings.xml generation and the BINDING_NAME_ globals.
function TotemBar.bindingSuffix(name)
    if not name then
        return ""
    end
    local up = string.upper(name)
    up = string.gsub(up, "[^A-Z0-9]+", "_")
    up = string.gsub(up, "^_+", "")
    up = string.gsub(up, "_+$", "")
    return up
end

-- Modifier prefix for a key string, order ALT-CTRL-SHIFT (each arg is 1/nil
-- as IsAltKeyDown()/IsControlKeyDown()/IsShiftKeyDown() return on 1.12).
function TotemBar.modifierPrefix(isAlt, isCtrl, isShift)
    local p = ""
    if isAlt then p = p .. "ALT-" end
    if isCtrl then p = p .. "CTRL-" end
    if isShift then p = p .. "SHIFT-" end
    return p
end

-- Binding COMMAND for a hovered thing, or nil. A flyout icon (totemName
-- given) -> the named per-totem binding (casts that specific totem, same
-- action as the Esc menu). A bar button (by global frame name) -> a CLICK
-- binding on it.
function TotemBar.actionForButton(frameName, totemName)
    if totemName and totemName ~= "" then
        return "TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(totemName)
    end
    if not frameName then
        return nil
    end
    if frameName == "TotemBarButtonRecall" or frameName == "TotemBarButtonDropSet" then
        return "CLICK " .. frameName .. ":LeftButton"
    end
    local elements = TotemBar.TOTEM_ELEMENTS
    for i = 1, table.getn(elements) do
        if frameName == "TotemBarButton" .. elements[i] then
            return "CLICK " .. frameName .. ":LeftButton"
        end
    end
    return nil
end
```

- [ ] **Step 4: Run test → PASS.**
- [ ] **Step 5: Commit** — `git add core/bindlogic.lua tools/luatests/test_bindlogic.lua && git commit -m "TotemBar: add pure bind-logic (bindingSuffix/modifierPrefix/actionForButton)"`

---

### Task 2: Generated `Bindings.xml` + `bind.lua` entry points/labels + TOC

**Files:** Create `Bindings.xml`, `bind.lua`, `tools/gen_bindings.lua`; Modify `TotemBar.toc`.

**Interfaces produced:** globals `BINDING_HEADER_*`/`BINDING_NAME_*`; `TotemBar.CastTotem(name)`, `TotemBar.CastElement(element)`, `TotemBar.CastRecall()`. (Bindings.xml references `TotemBar.recallAndCastAll`/`ToggleBar`/`ToggleOptions` which already exist, and `TotemBar.ToggleBindMode` added in Task 4 — a stub is added here so the binding never calls a nil.)

- [ ] **Step 1: Create the generator `tools/gen_bindings.lua`** (deterministic XML from the totem list, so names never drift from `bindingSuffix`):

```lua
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
```

- [ ] **Step 2: Generate `Bindings.xml`** — run:
```
lua50.exe tools/gen_bindings.lua > Bindings.xml
```
Then open `Bindings.xml` and confirm: it starts `<Bindings>`, the first binding has `header="TOTEMBAR"`, each element's first totem binding has `header="TOTEMBAR_<ELEMENT>"`, every `<Binding>` body is non-empty, and there are 5 fixed + 4 element + 23 totem = **32 bindings**. (Do NOT hand-edit; regenerate if wrong.)

- [ ] **Step 3: Create `bind.lua`** (labels + cast entry points; the hover-bind mode is appended in Task 4):

```lua
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
```

- [ ] **Step 4: Wire the TOC** — edit `TotemBar.toc`. Add `Bindings.xml` and `bind.lua`. `Bindings.xml` must come before `bind.lua`; `bind.lua` needs `core\bindlogic.lua` and `core\totemdata.lua` already loaded. Final order (append after the current entries):
```
core\bindlogic.lua
...
ui.lua
options.lua
minimap.lua
Bindings.xml
bind.lua
```
(Place `core\bindlogic.lua` among the other `core\` files, before `ui.lua`.)

- [ ] **Step 5: Parse-check + full suite** — `lua50.exe -e "assert(loadfile('bind.lua'))"` (clean); run all offline suites (test_bindlogic + the existing ones) — all pass. (Bindings.xml is XML, not Lua — not loadfile-checked; the generator already validated its shape.)

- [ ] **Step 6: Commit** — `git add TotemBar.toc Bindings.xml bind.lua tools/gen_bindings.lua && git commit -m "TotemBar: keybindings (generated Bindings.xml + labels + cast entry points)"`

---

### Task 3: Drop-set button (`ui.lua`)

**Files:** Modify `ui.lua`.

**Interfaces produced:** global button `TotemBarButtonDropSet`.

- [ ] **Step 1: Read `BuildUI` + `CreateRecallButton`** to see the bar-width math (`totalButtons`) and the button-creation pattern. The bar currently has `numElements + 1` (Recall) buttons.

- [ ] **Step 2: Add a drop-set button factory** in `ui.lua` (near `CreateRecallButton`), forward-declared like the others:

```lua
-- The "drop set" button: one click casts all four chosen totems
-- (TotemBar.recallAndCastAll, with its 2s double-press guard). Placed after
-- the Recall button.
CreateDropSetButton = function(index)
    local name = "TotemBarButtonDropSet"
    local btn = CreateFrame("Button", name, TotemBarFrame)
    btn:SetWidth(BUTTON_SIZE)
    btn:SetHeight(BUTTON_SIZE)
    btn:SetPoint("LEFT", TotemBarFrame, "LEFT", (index - 1) * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP, 0)
    btn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0, 0, 0, 1)

    local icon = btn:CreateTexture(name .. "Icon", "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture("Interface\\Icons\\Spell_Nature_TremorTotem")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        TotemBar.recallAndCastAll()
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        GameTooltip:SetText("Drop all totems")
        GameTooltip:AddLine("Left-click: cast your whole set", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end
```
Add `local CreateDropSetButton` to the forward-declaration block.

- [ ] **Step 3: Grow the bar + create the button** in `BuildUI`: change `totalButtons` to `numElements + 2` (Recall + DropSet) so the frame width includes it, and after `CreateRecallButton(...)` add the drop-set button one slot further right. Read the exact lines (the recall button is created at index `numElements + 1`); create the drop-set at `numElements + 2`:
```lua
    CreateRecallButton(numElements + 1)
    CreateDropSetButton(numElements + 2)
```
And update the width calc: `local totalButtons = numElements + 2`.

- [ ] **Step 4: Parse-check `ui.lua`** (clean) + run all offline suites (regression) — all pass.

- [ ] **Step 5: Commit** — `git add ui.lua && git commit -m "TotemBar: add drop-set bar button (casts the whole set, guarded)"`

---

### Task 4: Hover-bind mode + overlays (`bind.lua`, `ui.lua`)

**Files:** Modify `bind.lua` (append the mode), `ui.lua` (bind-mode key-label overlays on element/recall/dropset buttons + flyout icons; a hook the mode calls to refresh them).

**Interfaces produced:** `TotemBar.ToggleBindMode()` (real), `TotemBar.isBindMode()`, `TotemBar.refreshBindOverlays()` (set by ui.lua). Consumes `TotemBar.actionForButton`, `TotemBar.modifierPrefix`.

- [ ] **Step 1: Append the hover-bind mode to `bind.lua`:**

```lua
-- ===== Hover-bind mode =====
-- Toggle a mode where hovering a bar button / flyout totem and pressing a
-- key binds that key to the thing's action (buttons -> CLICK binding, flyout
-- totems -> the named per-totem binding). ESC clears the hovered thing's
-- binding. Bindings persist via the client (SaveBindings), no addon SV.

local bindMode = false
local captureFrame = nil

-- Base keys that are pure modifiers - never bind these alone.
local BARE_MODIFIERS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

function TotemBar.isBindMode()
    return bindMode
end

-- Resolves the mouse-focused frame to a binding action. Uses the pure
-- TotemBar.actionForButton with the frame's global name and, for a flyout
-- icon, its current .totemName.
local function actionForFocus(focus)
    if not focus then
        return nil
    end
    local totemName = focus.totemName   -- set on flyout icon buttons when shown
    local fname = focus.GetName and focus:GetName() or nil
    return TotemBar.actionForButton(fname, totemName)
end

local function ensureCaptureFrame()
    if captureFrame then
        return captureFrame
    end
    local f = CreateFrame("Frame", "TotemBarBindCapture", UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableKeyboard(false)
    f:Hide()
    f:SetScript("OnKeyDown", function()
        local key = arg1   -- NOTE: OnKeyDown arg1 = key name string (verify in-game)
        if not key or BARE_MODIFIERS[key] then
            return
        end
        local focus = GetMouseFocus()
        local action = actionForFocus(focus)
        if not action then
            return
        end
        if key == "ESCAPE" then
            local k1, k2 = GetBindingKey(action)
            if k1 then SetBinding(k1) end
            if k2 then SetBinding(k2) end
        else
            local full = TotemBar.modifierPrefix(IsAltKeyDown(), IsControlKeyDown(), IsShiftKeyDown()) .. key
            SetBinding(full)          -- clear whatever `full` was bound to
            SetBinding(full, action)  -- bind it to this action
        end
        SaveBindings(GetCurrentBindingSet())
        if TotemBar.refreshBindOverlays then
            TotemBar.refreshBindOverlays()
        end
    end)
    captureFrame = f
    return f
end

function TotemBar.ToggleBindMode()
    bindMode = not bindMode
    local f = ensureCaptureFrame()
    if bindMode then
        f:EnableKeyboard(true)
        f:Show()
        ChatOut:AddMessage("TotemBar: key-bind mode ON - hover a button or flyout totem and press a key. ESC clears. /tb bind to exit.")
    else
        f:EnableKeyboard(false)
        f:Hide()
        ChatOut:AddMessage("TotemBar: key-bind mode OFF.")
    end
    if TotemBar.refreshBindOverlays then
        TotemBar.refreshBindOverlays()
    end
end

-- Refresh overlays whenever the client's bindings change.
local bindEvents = CreateFrame("Frame", "TotemBarBindEventFrame", UIParent)
bindEvents:RegisterEvent("UPDATE_BINDINGS")
bindEvents:SetScript("OnEvent", function()
    if TotemBar.refreshBindOverlays then
        TotemBar.refreshBindOverlays()
    end
end)
```

- [ ] **Step 2: Add the bind overlays in `ui.lua`.** Each element/recall/dropset button and each flyout icon gets a small OVERLAY FontString (top-right) shown only in bind mode with the bound key. Implement `TotemBar.refreshBindOverlays` and attach an overlay to a button via a helper. In `ui.lua`, after the buttons/flyout exist, add:

```lua
-- Bind-mode key overlays: a small top-right FontString on each bindable
-- button/flyout icon, shown only in bind mode, with the currently-bound key.
local bindOverlayTargets = {}   -- { frame = button, action = fn()->command }

local function ensureBindOverlay(frame)
    if frame.bindKeyText then
        return frame.bindKeyText
    end
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    fs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    fs:SetTextColor(1, 0.9, 0.2)
    fs:Hide()
    frame.bindKeyText = fs
    return fs
end

-- action is a function returning the binding command for this frame right now
-- (flyout icons change totem), or nil.
local function registerBindOverlay(frame, actionFn)
    ensureBindOverlay(frame)
    tinsert(bindOverlayTargets, { frame = frame, action = actionFn })
end

TotemBar.refreshBindOverlays = function()
    local on = TotemBar.isBindMode and TotemBar.isBindMode()
    for i = 1, table.getn(bindOverlayTargets) do
        local t = bindOverlayTargets[i]
        local fs = t.frame.bindKeyText
        if not on then
            fs:Hide()
        else
            local cmd = t.action()
            local key = cmd and GetBindingKey(cmd) or nil
            if key then
                fs:SetText(GetBindingText(key, "KEY_", 1))
            else
                fs:SetText("")
            end
            fs:Show()
        end
    end
end
```

Then register overlays where the buttons are built:
- In `CreateElementButton`, before `return btn`, add:
  `registerBindOverlay(btn, function() return "CLICK " .. "TotemBarButton" .. element .. ":LeftButton" end)`
- In `CreateRecallButton`, before `return btn`:
  `registerBindOverlay(btn, function() return "CLICK TotemBarButtonRecall:LeftButton" end)`
- In `CreateDropSetButton` (Task 3), before `return btn`:
  `registerBindOverlay(btn, function() return "CLICK TotemBarButtonDropSet:LeftButton" end)`
- In `EnsureFlyoutFrame`, for each pooled icon `ico`, before `flyoutIcons[i] = ico`:
  `registerBindOverlay(ico, function() if ico.totemName then return "TOTEMBAR_TOTEM_" .. TotemBar.bindingSuffix(ico.totemName) end return nil end)`
  (Also call `TotemBar.refreshBindOverlays()` at the end of `ShowFlyout` so a freshly-populated flyout shows keys while in bind mode.)

`registerBindOverlay`/`ensureBindOverlay` are file-locals defined once; ensure they're declared before the button factories use them (place the block above `CreateElementButton`, or forward-declare). Verify placement by reading the file.

- [ ] **Step 3: Parse-check `bind.lua` + `ui.lua`** (clean); run the Lua-5.0 lint greps over both (no `#var`, no string `:method`, no `string.match`/`gmatch` in the new code); run all offline suites — all pass.

- [ ] **Step 4: Commit** — `git add bind.lua ui.lua && git commit -m "TotemBar: hover-bind mode (capture + CLICK/named bindings, persist) + key overlays"`

---

### Task 5: Options-panel bind toggle + `/tb bind`

**Files:** Modify `options.lua` (a "Key bind mode" button), `ui.lua` (`/tb bind` in `HandleSlashCommand` + usage line).

- [ ] **Step 1: Add a "Key bind mode" button** in `options.lua`'s `BuildOptionsFrame` (a full-width button below the existing ones, via the same `CreateButton` factory + `AddTooltip`), calling `TotemBar.ToggleBindMode()`. Read `BuildOptionsButtons`/the layout cursor and place it consistently (extend the panel height if needed so it doesn't collide with the version footer).
```lua
    local bind = CreateButton(f, "TotemBarOptBindButton", "Key bind mode", function()
        if TotemBar.ToggleBindMode then TotemBar.ToggleBindMode() end
    end)
    bind:SetWidth(w)
    bind:SetPoint("TOPLEFT", f, "TOPLEFT", x, yStart - 56)
    AddTooltip(bind, "Toggle bind mode, then hover any bar button or a flyout totem and press a key to bind it. ESC clears. Bindings are saved automatically.")
```
(Adjust `yStart - 56` / the frame height so the three buttons + version footer fit.)

- [ ] **Step 2: Add `/tb bind`** in `ui.lua`'s `HandleSlashCommand`, before the final `else`:
```lua
    elseif cmd == "bind" then
        if TotemBar.ToggleBindMode then TotemBar.ToggleBindMode() end
```
Update the usage line to include `bind`.

- [ ] **Step 3: Parse-check both** (clean); run offline suites — all pass.

- [ ] **Step 4: Commit** — `git add options.lua ui.lua && git commit -m "TotemBar: options 'Key bind mode' button + /tb bind"`

---

### Task 6: Deploy + full restart + in-game verification + KG writeback + v0.1.1

**Files:** none (deploy/verify/knowledge/release).

- [ ] **Step 1: Deploy (PowerShell)** — `robocopy "C:\dev\TotemBar" "C:\turtle\Interface\AddOns\TotemBar" /MIR /XD .git .superpowers docs tools /XF README.md LICENSE` (Bindings.xml + bind.lua + core\bindlogic.lua must land; confirm they exist under the live path). Exit 0-7.

- [ ] **Step 2: Full client restart** (new files `Bindings.xml`/`bind.lua`/`core\bindlogic.lua` in the TOC → `/reload` is not enough). Ask Phil to fully restart; check `C:\turtle\Errors` for a new #132 first (a malformed Bindings.xml or a load error would crash on startup — if so, read the crash log + fix).

- [ ] **Step 3: In-game verification** (have Phil confirm each):
  - **Drop-set button** appears right of Recall; click casts the whole set; a rapid double-press does NOT wipe the totems (guard holds).
  - **Esc → Key Bindings**: a "TotemBar" section exists with Drop all totems / Totemic Recall / Toggle bar / Toggle options / Toggle key-bind mode / per-element casts, plus per-element sub-sections listing **every totem**; assigning a key in that menu works and casts.
  - **`/tb bind`** and the options "Key bind mode" button both toggle bind mode (chat message).
  - In bind mode: hover an **element button** + press a key → binds (pressing the key later casts the chosen totem); hover **Recall**/**drop-set** + key → binds; hover a **flyout totem icon** + key → binds THAT specific totem (the key casts exactly it). The bound key shows as an overlay on the button/icon.
  - **ESC** while hovering clears that thing's binding. Bindings **survive a `/reload`** (SaveBindings).
  - **Confirm the two KG-unknowns:** that `OnKeyDown` `arg1` is the key-name string (if bindings don't register, dump `arg1` via a temporary `ChatOut:AddMessage`); and whether mouse-wheel binds (try `MOUSEWHEELUP` over a button).

- [ ] **Step 4: KG writeback** (after confirmation; skip if PROPAGATOR offline). Node (`knowledge_type:"ui-recipe"`, `verification:"in-game-confirmed"`): the working 1.12 hover-bind recipe — `EnableKeyboard(true)`+`OnKeyDown` `arg1` format AS VERIFIED, `GetMouseFocus()`, modifier assembly, `SetBinding(key,"CLICK Frame:LeftButton")` / named binding, `SaveBindings(GetCurrentBindingSet())` persistence, and whether mouse-wheel binds. Plus a node on the generated-Bindings.xml pattern.

- [ ] **Step 5: Devlog + release** — append to the current KB devlog (feature + in-game result), commit KB locally. Bump `TotemBar.toc` `## Version` to `0.1.1`; commit on `dev`; merge `dev`→`master`; tag `v0.1.1`; push both + tag; rebuild the clean `TotemBar-v0.1.1.zip` (top folder `TotemBar`, runtime files + README/LICENSE) and `gh release create v0.1.1` with it. (Git-pull/OctoWoW users get it automatically from `master`.)

---

## Self-Review

**Spec coverage:** drop-set button (Task 3) ✅; Bindings.xml with all fixed actions + per-element + every totem (Task 2, generated) ✅; bind labels/entry points (Task 2) ✅; hover-bind mode buttons-via-CLICK + flyout-totems-via-named-binding + ESC-clear + persist (Task 4) ✅; key overlays (Task 4) ✅; options toggle + `/tb bind` (Task 5) ✅; pure helpers offline-tested (Task 1) ✅; deploy/full-restart/in-game + the two KG-unknowns + KG writeback + v0.1.1 (Task 6) ✅; no new SavedVariables ✅.

**Placeholder scan:** every step has concrete code/commands; the two in-game-gated unknowns (`OnKeyDown arg1`, mouse-wheel) are explicit verification steps, not code TBDs; the `Bindings.xml` is generated (Task 2 Step 2) not hand-waved.

**Type consistency:** `bindingSuffix`/`modifierPrefix`/`actionForButton` signatures identical across bindlogic, tests, the generator, and bind.lua/ui.lua consumers. The per-totem binding command `"TOTEMBAR_TOTEM_"..bindingSuffix(name)` is produced identically by the generator (XML `name`), `bind.lua` (`BINDING_NAME_` global), the flyout overlay action, and `actionForButton` — one derivation, no drift. Button CLICK commands use the confirmed global names (`TotemBarButtonFire/Earth/Water/Air/Recall/DropSet`). Load order (bindlogic before ui/bind; Bindings.xml before bind.lua) matches the runtime references (all binding bodies call `TotemBar.*` resolved at keypress, post-load).
