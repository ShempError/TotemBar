# TotemBar — Drop-Set Button + Keybindings + Hover-Bind Mode (Design)

> Date: 2026-07-09 (Session 74 cont.)
> Status: scope approved (Phil, in-game chat) — pending spec sign-off
> Source: first tester feedback on the public v0.1.0 addon.

## Purpose

Three tester-requested additions:
1. A **"drop set" button** on the bar — one click casts all four chosen totems (the "Totems" macro action) without needing a macro on the action bar.
2. **Standard key bindings** in the Esc → Key Bindings menu under a "TotemBar" section, for every TotemBar action — including a binding for **every individual totem** (not just per-element).
3. A **hover-bind mode** (like Dominos/Bartender): toggle it on, hover a bar button or a flyout totem, press a key, and that key is bound; ESC clears; the bound key shows as an overlay on each button. Persisted client-side.

## Background (KG, domain=wow — 1.12 / TurtleWoW verified)

- **`Bindings.xml`**: `<Binding name="X" header="Y" runOnUp="...">lua body</Binding>`; `header=` only on the first binding of a group; body must be non-empty. Listed in the `.toc` **before** the `.lua` that sets the label globals. Labels: `BINDING_HEADER_<HEADER>` and `BINDING_NAME_<NAME>` plain globals.
- Casting from a binding works (hardware event); `CastSpellByName` is unprotected on 1.12 anyway.
- **`SetBinding(key, command)`** — `command` may be a binding `name`, `"CLICK Frame:LeftButton"` (Frame must be a **global** Button), or `"SPELL SpellName"`. `SetBinding(key)` (no command) unbinds. In-memory until **`SaveBindings(GetCurrentBindingSet())`** (1=account, 2=character). `GetBindingKey(command)` → keys bound to it; `GetBindingText(key, "KEY_", 1)` → abbreviated label. `UPDATE_BINDINGS` event fires on change.
- **Hover capture**: `GetMouseFocus()` → frame under cursor; a frame with `EnableKeyboard(true)` + `OnKeyDown` captures keys. Modifier state via `IsShiftKeyDown()/IsControlKeyDown()/IsAltKeyDown()` (return `1`/nil); assemble in order `ALT-CTRL-SHIFT-key`. `EnableKeyboard(true)` **swallows all keys** while active → only enable it while bind-mode is on. Skip bare modifier keys (`LSHIFT/RSHIFT/LCTRL/RCTRL/LALT/RALT`).
- **Two KG-unverified points → confirm in-game during build, then write back**: (a) that a plain Frame's `OnKeyDown` `arg1` is the string key name; (b) mouse-wheel binding key strings (`MOUSEWHEELUP/DOWN`). Build assuming the standard vanilla idiom; verify.
- Existing global button names: `TotemBarButtonFire/Earth/Water/Air`, `TotemBarButtonRecall`. New: `TotemBarButtonDropSet`.

## Component 1 — Drop-set button (`ui.lua`)

- New named `Button` `TotemBarButtonDropSet`, appended to the bar **after** the Recall button (bar width grows by one slot; `BuildUI`'s `totalButtons` = elements + Recall + DropSet).
- Icon: `"Interface\\Icons\\Spell_Nature_TremorTotem"` (same as the Totems macro; a stock totem icon). Same backdrop/inset treatment as the other buttons.
- `OnClick` (left) → `TotemBar.recallAndCastAll()` (the 2s double-press guard applies). Tooltip: "Drop all totems" + "Left-click: cast your whole set".
- Cooldown swipe / timers not needed on it (it's an action, not a slot).

## Component 2 — Key bindings (`Bindings.xml` + `bind.lua`)

**`Bindings.xml`** (new; TOC-listed before `bind.lua`), all under a `TotemBar` header, with per-element sub-headers for the totem list. Bindings (body calls a `TotemBar.*` entry point):

- `TOTEMBAR_DROPSET` → `TotemBar.recallAndCastAll()`
- `TOTEMBAR_RECALL` → `TotemBar.CastRecall()` (casts Totemic Recall + `clearActiveTotems`)
- `TOTEMBAR_TOGGLEBAR` → `TotemBar.ToggleBar()`
- `TOTEMBAR_TOGGLEOPTIONS` → `TotemBar.ToggleOptions()`
- `TOTEMBAR_TOGGLEBIND` → `TotemBar.ToggleBindMode()`
- `TOTEMBAR_CAST_FIRE` / `_EARTH` / `_WATER` / `_AIR` → `TotemBar.CastElement("Fire")` … (casts that element's currently-chosen totem)
- **Per totem** in `TotemBar.TOTEMS_BY_ELEMENT` (23 vanilla totems): `TOTEMBAR_TOTEM_<SANITIZED>` → `TotemBar.CastTotem("<Totem Name>")`. Sub-grouped with headers `TOTEMBAR_FIRE`/`_EARTH`/`_WATER`/`_AIR` ("TotemBar: Fire Totems", …).

`SANITIZED` = the totem name uppercased with every non-alphanumeric run replaced by `_` (e.g. "Searing Totem" → `SEARING_TOTEM`, "Grace of Air Totem" → `GRACE_OF_AIR_TOTEM`). This derivation is a **pure function** (`TotemBar.bindingSuffix(name)`) shared by the XML generation, the label globals, and the hover-bind action lookup — they MUST agree.

> The `Bindings.xml` content is generated once (offline) from `TOTEMS_BY_ELEMENT` using `bindingSuffix`, and checked in as a static file. `bind.lua` sets the `BINDING_HEADER_*`/`BINDING_NAME_*` globals in a loop over the same list, so labels never drift from the XML.

**`bind.lua`** provides: the label globals (fixed ones literal + the totem ones in a loop), and the binding entry points:
- `TotemBar.CastElement(element)` — `CastSpellByName(TotemBarDB.chosen[element])` if set (else a chat hint).
- `TotemBar.CastTotem(name)` — `CastSpellByName(name)` (no-op in-game if the shaman doesn't know it).
- `TotemBar.CastRecall()` — `CastSpellByName("Totemic Recall")` + `TotemBar.clearActiveTotems()`.
- (ToggleBar/ToggleOptions/recallAndCastAll/ToggleBindMode already exist elsewhere.)

## Component 3 — Hover-bind mode (`bind.lua`)

- **Toggle:** `TotemBar.ToggleBindMode()` — via `/tb bind`, a "Key bind mode" **button in the options panel**, and the `TOTEMBAR_TOGGLEBIND` binding.
- **On enter:** show a keyboard-capture frame `TotemBarBindCapture` (parented to UIParent, full-screen or a small always-on frame) with `EnableKeyboard(true)`; show a highlight + a key-label overlay on every bar button and (while a flyout is open) every visible flyout icon; a small on-screen hint ("Bind mode: hover a button/totem and press a key. ESC clears. /tb bind or click to exit."). Options-panel checkbox reflects the state.
- **On `OnKeyDown`** (in the capture frame): let `key = arg1`.
  - Ignore bare modifiers (`LSHIFT/RSHIFT/LCTRL/RCTRL/LALT/RALT`).
  - Assemble the full key string via `TotemBar.modifierPrefix()` + `key` (pure helper: `ALT-`/`CTRL-`/`SHIFT-` in order from the Is*KeyDown states).
  - `local focus = GetMouseFocus()` → map it to a **binding action** via `TotemBar.actionForFrame(focus)`:
    - element button (`TotemBarButton<Element>`) → `"CLICK TotemBarButton<Element>:LeftButton"`
    - recall button → `"CLICK TotemBarButtonRecall:LeftButton"`
    - drop-set button → `"CLICK TotemBarButtonDropSet:LeftButton"`
    - a flyout icon with a `totemName` → the **named totem binding** `"TOTEMBAR_TOTEM_" .. bindingSuffix(totemName)` (casts that specific totem; same action as the Esc-menu entry — one source of truth)
    - anything else → nil (ignore the keypress)
  - If `key == "ESCAPE"`: clear the hovered action's current binding(s) (`for each GetBindingKey(action) do SetBinding(k) end`), then save.
  - Else: `SetBinding(fullKey, action)` (first unbind whatever `fullKey` was on, to avoid stealing), then `SaveBindings(GetCurrentBindingSet())`.
  - Refresh overlays.
- **On exit:** `EnableKeyboard(false)`, hide capture frame + overlays.
- **Overlays:** a small `FontString` (top-right corner) on each bar button and flyout icon, text = `GetBindingText(GetBindingKey(actionForThatThing), "KEY_", 1)` (abbrev.), shown only in bind mode. Register `UPDATE_BINDINGS` to refresh them.
- **Flyout in bind mode:** hovering an element button still opens its flyout (existing behavior) so the player can move onto a flyout icon and press a key; the flyout's mouse-leave auto-hide keeps it open while the cursor is over it.

## SavedVariables

- **None new.** Key bindings are persisted by the **client** (`SaveBindings`), not addon SavedVariables. Bind mode is transient (off on load).

## Public interface (new)

- `TotemBar.ToggleBindMode()`, `TotemBar.CastElement(element)`, `TotemBar.CastTotem(name)`, `TotemBar.CastRecall()`.
- Pure helpers (offline-tested): `TotemBar.bindingSuffix(name) -> string`, `TotemBar.modifierPrefix(isAlt, isCtrl, isShift) -> string`, `TotemBar.actionForButton(frameName, totemName) -> actionString|nil` (the mapping logic factored so it's testable without live frames — takes the resolved frame identity, not the frame).

## Files

- **New** `Bindings.xml` — the static bindings (generated from `TOTEMS_BY_ELEMENT`).
- **New** `bind.lua` — binding label globals + entry points (`CastElement`/`CastTotem`/`CastRecall`) + hover-bind mode (capture frame, `ToggleBindMode`, overlays, `actionForFrame`). Depends on `core/optionslogic.lua`-style pure helpers.
- **Modify** `core/optionslogic.lua` (or a new `core/bindlogic.lua`) — pure `bindingSuffix`, `modifierPrefix`, `actionForButton`, offline-tested.
- **Modify** `ui.lua` — drop-set button; expose the bar buttons for overlays; bind-mode highlight/overlay hooks on element/recall/dropset buttons + flyout icons.
- **Modify** `options.lua` — a "Key bind mode" button/checkbox that calls `TotemBar.ToggleBindMode()`.
- **Modify** `TotemBar.toc` — add `Bindings.xml` (before the lua that sets globals) + `bind.lua`; ensure load order (core pure logic → ui → options → bind, with Bindings.xml early).
- **New** `tools/luatests/test_bindlogic.lua` — offline tests for `bindingSuffix`, `modifierPrefix`, `actionForButton`.
- ⚠️ New files (`Bindings.xml`, `bind.lua`) → **full client restart** required.

## Testing

- **Offline Lua 5.0**: `bindingSuffix` (spaces/punct → `_`, uppercase; e.g. "Grace of Air Totem" → `GRACE_OF_AIR_TOTEM`), `modifierPrefix` (all 8 combos → correct `ALT-CTRL-SHIFT-` ordering), `actionForButton` (element/recall/dropset/flyout-totem/unknown → correct action string / nil).
- **In-game** (ground truth; needs full restart): drop-set button casts the set (guard still holds on double-press); Esc → Key Bindings shows the TotemBar section with all actions incl. every totem, and assigning keys there works; `/tb bind` (and the options button) toggles bind mode; hovering an element/recall/dropset button + a key binds it (verify the cast fires on the key), hovering a **flyout totem** + a key binds THAT totem; the key overlay shows on buttons/flyout; ESC clears; bindings **survive a reload** (SaveBindings). **Verify the two KG-unknowns**: `OnKeyDown` `arg1` format, and whether mouse-wheel binds.
- On confirmation, KG write-back: the verified `OnKeyDown arg1` format + the working hover-bind/CLICK+SPELL pattern for 1.12 (`verification:"in-game-confirmed"`).

## Out of scope

- Rebinding via drag; profiles; per-spec bindings.
- Mouse-wheel binding (only if the in-game check confirms the key string; otherwise a follow-up).
- Localizing binding labels (English only).
