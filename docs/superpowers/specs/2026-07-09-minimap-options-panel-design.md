# TotemBar — Minimap Button + Options Panel (Design)

> Date: 2026-07-09
> Status: approved (Phil, in-game chat) — ready for implementation plan
> Depends on: existing TotemBar (bar, cast.lua, config.lua, assign.lua, ui.lua).

## Purpose

Give TotemBar a **minimap button** that opens a **standalone options panel**, so all settings
(currently only reachable via slash commands / button right-clicks) live in one place, plus two new
conveniences: a **UI-size slider** (scales the bar) and a **"Create macro"** button that generates
the "Totems" macro automatically.

## Background (KG, domain=wow — 1.12 / TurtleWoW verified patterns)

- **Minimap buttons are hand-rolled** on 1.12 (`CreateFrame("Button", name, Minimap)`). LibDBIcon/
  LibDataBroker are WotLK-era — not used here.
- **pfUI is the compat hazard on TurtleWoW.** To survive pfUI: parent MUST be `Minimap`; name MUST
  contain `"Minimap"`; size 26–33px; **`SetFrameStrata("HIGH")` + `SetFrameLevel(9)`** (MEDIUM gets
  hidden under pfUI's minimap overlays); the button must be visible for pfUI's `/abp add`. pfUI can
  reshape the minimap to a square (orbit math still works off `Minimap:GetWidth()`), and can
  reparent/hide the button — so **a slash command (`/tb options`) is the guaranteed access path.**
- Init the button on **`ADDON_LOADED`** (guarded `if self.button then return end`), never on
  `PLAYER_ENTERING_WORLD` (re-runs → texture leak). SavedVariables are already populated at
  `ADDON_LOADED` (TotemBar builds its bar there via `ensureDefaults` + `BuildUI`).
- Config widgets: **`UICheckButtonTemplate`** (label child `getglobal(name.."Text")`; frame name must
  be non-nil), **`OptionsSliderTemplate`** (children `$parentLow/$parentHigh/$parentText`;
  `SetMinMaxValues` BEFORE `SetValue`; never override the 16px height). `GetChecked()` returns **`1`
  or `nil`** in 1.12 (use `== 1`).
- Custom macro icons need a real `Interface\Icons\*` file; `CreateMacro`/`EditMacro` take a **bare
  icon name** (TWoW prepends `Interface\Icons\`). We use a stock totem icon.

## Component 1 — Minimap button (`minimap.lua`)

- `TotemBarMinimapButton`, parent `Minimap`, 31×31, `SetFrameStrata("HIGH")`, `SetFrameLevel(9)`.
  - Icon: 20×20, `ARTWORK` layer, a stock totem icon (default
    `"Interface\\Icons\\Spell_Nature_TremorTotem"` — verify it renders in-game; it is a real vanilla
    icon). A custom `.blp` can replace this later (Phil's separate icon plan).
  - Border: 53×53, `OVERLAY`, `"Interface\\Minimap\\MiniMap-TrackingBorder"`,
    `SetPoint("TOPLEFT", btn, "TOPLEFT", -5, 5)` (verify offset in-game; recorded recipes use −5/5 or
    −12/12 for a 56px border — pick and confirm).
  - Highlight: `"Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"`.
- **Orbit position** from a saved angle: `radius = Minimap:GetWidth()/2 + 5`; `x = cos(rad)*radius`,
  `y = sin(rad)*radius`; `SetPoint("CENTER", Minimap, "CENTER", x, y)`. Default angle 225°.
- **Draggable**: `RegisterForDrag("LeftButton")` would conflict with left-click-opens-panel, so use
  drag on a modifier or `RegisterForDrag("RightButton")`? — To keep left-click = open and
  right-click = toggle bar (Phil's mapping) clean, make the button **drag with the left button held**
  is ambiguous. **Decision:** drag while **holding SHIFT + left-drag** is over-engineered for 1.12;
  instead use plain `RegisterForDrag("LeftButton")` for repositioning and route the *open-panel*
  action to a click WITHOUT drag. In 1.12 `OnDragStart` only fires after the drag threshold, so a
  normal click still triggers `OnClick`. So: `RegisterForDrag("LeftButton")` → `OnDragStart` sets
  `isDragging=true` + `StartMoving`-style orbit-follow via `OnUpdate`; `OnDragStop` saves the angle;
  `OnClick` (left) opens the panel, (right) toggles the bar. This is the KG's verified pattern (drag
  and click coexist because drag needs the movement threshold).
  - `OnUpdate` (only while `isDragging`): `mx,my = GetCursorPosition()`, divide by
    `Minimap:GetEffectiveScale()`; `cx,cy = Minimap:GetCenter()`;
    `angle = deg(atan2(my-cy, mx-cx))`; reposition; store on the button.
  - `OnDragStop`: `TotemBarDB.minimapAngle = angle`.
- **Clicks**: `RegisterForClicks("LeftButtonUp","RightButtonUp")`; `OnClick`:
  `arg1=="LeftButton"` → `TotemBar.ToggleOptions()`; `arg1=="RightButton"` → `TotemBar.ToggleBar()`.
- **Tooltip** (`OnEnter`/`OnLeave`): "TotemBar" + "Left-click: Options" + "Right-click: Toggle bar".
- **Build** on `ADDON_LOADED` (guarded), positioned from `TotemBarDB.minimapAngle`.
- **Slash fallback**: `/tb options` opens the panel regardless of the button's pfUI state.

## Component 2 — Options panel (`options.lua`)

- `TotemBarOptionsFrame`: standalone, named, movable (drag by title), `UIPanelCloseButton`, hidden by
  default. `SetFrameStrata("DIALOG")`. Opened/closed by `TotemBar.ToggleOptions()` (minimap
  left-click and `/tb options`). Added to `UISpecialFrames` so ESC closes it.
- **On `OnShow`**: repopulate every widget from `TotemBarDB` (so it always reflects current state).
- Controls (top-to-bottom), all applied **live** on change and persisted to `TotemBarDB`:
  1. **Checkbox "Lock bar"** → `TotemBarDB.locked` (same flag `/tb lock` toggles; drag is gated on it).
  2. **Checkbox "Auto-recall before setting"** → `TotemBarDB.autoRecall`; also refresh the Recall
     button's "A" indicator (`TotemBar.RefreshRecallIndicator` — expose it if not already global).
  3. **Checkbox "Show bar"** → shows/hides `TotemBarFrame`, persisted as `TotemBarDB.hidden`
     (inverted). (Replaces the transient `/tb` toggle with a persisted one.)
  4. **Slider "Recall guard (sec)"** → `TotemBarDB.recallGuardSeconds`, range 0–5, step 0.5,
     default 2.
  5. **Slider "Cycle reset gap (sec)"** → `TotemBarDB.gapSeconds`, range 0.5–5, step 0.5, default 2.
  6. **Slider "UI size"** → `TotemBarDB.scale`, range 0.5–2.0, step 0.05, default 1.0; applies
     `TotemBarFrame:SetScale(scale)` live.
  7. **Button "Reset position"** → resets `TotemBarDB.point/relPoint/x/y` to the CENTER defaults and
     re-anchors `TotemBarFrame` (does NOT touch scale).
  8. **Button "Create macro"** → see Component 3.
- Slider live-text: show the current numeric value in the slider's `$parentText` (e.g. "UI size: 1.15").
- Widgets built once (lazy, on first `ToggleOptions`), reused. No `OnUpdate` on the panel.

## Component 3 — "Create macro" (in `options.lua`, logic in a testable helper)

- On click: ensure a general macro named **"Totems"** exists with body
  `"/script TotemBar.recallAndCastAll()"` and icon `"Spell_Nature_TremorTotem"` (bare name).
  - If `GetMacroIndexByName("Totems") > 0` → `EditMacro(index, "Totems", "Spell_Nature_TremorTotem",
    body, 1, nil)` (update in place). Else `CreateMacro("Totems", "Spell_Nature_TremorTotem", body,
    nil)` (general, not per-char).
  - **Macro cap**: 1.12 allows 18 general macros. If creating and the cap is reached
    (`GetNumMacros()` general count ≥ cap and no existing "Totems"), print a chat message ("macro
    slots full — free one and retry") and do nothing.
  - Print a confirmation ("TotemBar: 'Totems' macro created/updated — drag it to your action bar.").
  - Does NOT auto-place on the action bar (no 1.12 API; user drags it).

## SavedVariables (extend `config.lua` `ensureDefaults`)

Add, non-destructively (`or`/`== nil` guards):
- `TotemBarDB.scale` = 1.0
- `TotemBarDB.minimapAngle` = 225
- `TotemBarDB.hidden` = false
- `TotemBarDB.recallGuardSeconds` = `TotemBar.DEFAULT_RECALL_GUARD` (2) — so the slider has a stored
  value (recallAndCastAll already falls back to the constant, this just makes it explicit/tunable).
- On load (`BuildUI`), apply `TotemBarFrame:SetScale(TotemBarDB.scale)` and honor `TotemBarDB.hidden`.

## Public interface (new globals)

- `TotemBar.ToggleOptions()` — show/hide the options panel (builds it lazily).
- `TotemBar.ToggleBar()` — show/hide `TotemBarFrame`, persist `TotemBarDB.hidden`.
- `TotemBar.RefreshRecallIndicator` — already exists in ui.lua as a file-local; **promote to a
  `TotemBar.` function** (or add a thin `TotemBar.RefreshRecallIndicator` wrapper) so `options.lua`
  can refresh the "A" indicator after the auto-recall checkbox changes.
- `TotemBar.macroSpec()` (pure) — returns the fixed `name/body/icon` for the Totems macro, so the
  create/edit decision + values are unit-testable without WoW API.
- `TotemBar.angleToOffset(angleDeg, radius)` (pure) — returns `x, y` for the orbit position
  (cos/sin), unit-testable.
- `TotemBar.clampValue(v, min, max)` (pure) — slider value clamp, unit-testable.

## Files

- **New** `minimap.lua` — the minimap button (orbit math via `TotemBar.angleToOffset`, drag, clicks,
  tooltip, ADDON_LOADED build). WoW-API; parse-checked only.
- **New** `options.lua` — the options panel (checkboxes/sliders/buttons, `ToggleOptions`, macro
  create via `TotemBar.macroSpec`). WoW-API; parse-checked only. Pure helpers it relies on
  (`macroSpec`, `clampValue`) live here or in a small `optionslogic.lua`, offline-tested.
- **Modify** `config.lua` — new `ensureDefaults` fields; keep `TotemBar.angleToOffset`/`clampValue`/
  `macroSpec` pure helpers here if that keeps WoW-API out of the tested unit (cleanest: put the pure
  helpers in `config.lua` or a new `core/optionslogic.lua`, and keep `minimap.lua`/`options.lua`
  WoW-API-only).
- **Modify** `ui.lua` — `TotemBar.ToggleBar`, apply scale + hidden in `BuildUI`, promote
  `RefreshRecallIndicator`; expose a reposition helper for "Reset position" (or reuse the existing
  anchor code).
- **Modify** `TotemBar.toc` — add `core\optionslogic.lua` (if used), `minimap.lua`, `options.lua`
  in load order (after `ui.lua`, or pure-logic files under `core\` before `ui.lua`).
  ⚠️ New files → **full client restart** required.
- **New** `tools/luatests/test_optionslogic.lua` — offline tests for `angleToOffset`, `clampValue`,
  `macroSpec`.

## Testing

- **Offline Lua 5.0** (`lua50.exe`): `angleToOffset` (known angles → expected x/y within tolerance;
  0°→(r,0), 90°→(0,r), 180°→(−r,0)), `clampValue` (below/within/above), `macroSpec` (returns the
  exact name/body/icon strings).
- **In-game** (ground truth, needs full restart): minimap button appears at the saved angle,
  drag-repositions and persists across reload; left-click opens the panel, right-click toggles the
  bar; every control reads/writes correctly and applies live (esp. UI-size slider scaling the bar,
  recall-guard slider changing the double-press window, show-bar persisting); "Reset position"
  re-centers the bar; "Create macro" makes a usable "Totems" macro (drag to bar, it casts). Verify
  pfUI does not hide the button (and that `/tb options` works even if it does).

## Verification envelope

- Offline unit tests green under real Lua 5.0.3; parse-check on all new/changed WoW-API files.
- In-game confirmation of every control + the minimap button + macro before claiming done.
- On confirmation, write back to KG (`domain=wow`, in-game-confirmed): the pfUI-safe minimap-button
  recipe as actually verified on this client, and the working 1.12 options-panel widget wiring.

## Out of scope

- Custom `.blp` icon for the minimap button / macro (Phil's separate later task; stock icon for now).
- Blizzard `InterfaceOptionsFrame` integration (standalone frame instead — KG-backed).
- Auto-placing the macro on the action bar (no 1.12 API).
- Localizing strings (English only, per project rule).
