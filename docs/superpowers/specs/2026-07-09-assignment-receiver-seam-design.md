# TotemBar — Assignment Receiver Seam (Design)

> Date: 2026-07-09
> Status: approved (Phil, in-game chat) — ready for implementation plan
> Scope: build the *receiver* seam in TotemBar now; defer the assigner ("ShamiPower")
> and all transport (addon comms) to a later project.

## Purpose

Add an integration seam to TotemBar so that a future external assigner (working title
**ShamiPower** — a PallyPower-analog for shaman totem raid coordination) can hand TotemBar a
proposed totem set. TotemBar presents it as a **pending suggestion** which the player confirms
with **one click** to apply. The player stays in control — an assignment is a suggestion, never
an auto-cast (mirrors how PallyPower shows an assignment and the buffer chooses to cast).

**Now:** the Lua seam + the pending-suggestion UI + a dev command to test the whole flow without
any transport. **Deferred:** addon-comms transport (wire format, `SendAddonMessage`) and the
assigner grid/UI itself.

## Background (from KG, domain=wow)

- Totems only buff the caster's own 5-man subgroup within range (~20–30y, up to 40y with
  Totemic Mastery). *This exact party/subgroup-scope rule is NOT a confirmed KG atom* — it is the
  well-known vanilla mechanic and is the rationale for raid totem coordination, but it must be
  in-game-confirmed before any assigner logic hard-codes it. **It does not affect this seam**
  (the seam is per-shaman: it just receives a set for THIS shaman's own group).
- No native `GetTotemInfo`/`PLAYER_TOTEM_UPDATE` on 1.12 — TotemBar already handles totem state
  via pfUI libtotem (optional) + its own cast-tracking. Not needed for this seam.
- Addon comms (`SendAddonMessage`, prefix+text ≤254 bytes, RAID rate-limits, manual prefix
  filtering, no `RegisterAddonMessagePrefix`) are the future transport concern — **out of scope
  here**. TotemBar stays transport-agnostic; the assigner will call `TotemBar.ReceiveAssignment`.

## Data contract — an "assignment set"

```lua
-- set: element -> totem spell name. Any subset of elements; a nil/absent
-- element means "no change / nothing assigned for that element".
set = {
    Fire  = "Searing Totem",           -- or nil
    Earth = "Strength of Earth Totem", -- or nil
    Water = "Mana Spring Totem",       -- or nil
    Air   = "Grace of Air Totem",      -- or nil
}
-- label: optional short string shown in the pending panel; nil -> "Assigned set".
label = "Melee group"
```

- Keys are exactly the entries of `TotemBar.TOTEM_ELEMENTS` ("Fire"/"Earth"/"Water"/"Air").
- Totem names are matched against the spellbook via the same path chosen totems use
  (`FindSpellIndexByName`). This is the stable contract the future assigner must produce.
- A totem the shaman **does not know** is shown greyed in the panel and is **not** applied to
  that slot on accept (the other, known slots still apply).

## Public API (the seam)

All on the `TotemBar` table, English identifiers:

- `TotemBar.ReceiveAssignment(set, label)` — validates `set` is a non-empty table keyed by known
  elements; stores `{ set = <copy>, label = label }` as the **current pending assignment**
  (replacing any prior pending); shows/refreshes the pending panel. Returns `true` on accepted
  input, or `false, reason` if malformed. **Does not apply anything.** This is the seam ShamiPower
  will call.
- `TotemBar.GetChosenSet()` — returns a **fresh** table `{ Fire=name, Earth=name, ... }` (copy) of
  the currently chosen totems, restricted to known elements. For a future assigner to read/display
  a shaman's current setup. Never returns an internal table by reference.
- `TotemBar.ClearAssignment()` — drops any pending assignment and hides the panel (used by the
  decline action and internally right after an accept).
- `TotemBar.onAssignmentApplied` — optional hook slot (nil by default). If set to a function, it is
  called with the applied set table after an accept, so a future assigner can learn the shaman
  accepted. Cheap; included now.

## Pending-suggestion UI

- A named frame `TotemBarAssignFrame` (named per project convention, not anonymous), built **once**
  lazily (like the flyout), reused thereafter; hidden by default, shown only while a pending
  assignment exists. Anchored to the bar (above it; `SetClampedToScreen`).
- Contents:
  - the `label` (or "Assigned set") as a heading;
  - a row of up to 4 mini totem icons in element order, each resolved via the same
    `GetSpellTexture` path as the bar buttons; an icon for a totem the shaman does **not** know is
    desaturated/greyed with a small marker;
  - an **Accept** button.
- Interaction:
  - **Left-click Accept (one click) = apply:** for each element present in the set **and** known,
    set `TotemBarDB.chosen[element] = name`; then `RefreshButton` all elements; clear pending; hide
    the panel; fire `onAssignmentApplied` if set. **No auto-cast** — the player drops the totems
    themselves via the existing element-button click / "Totems" macro.
  - **Decline** (a small close "X" on the panel, and/or right-click the panel) = `ClearAssignment`
    (hide, no change to chosen totems).
- Icons resolve on show. If the spellbook is not ready (early login), the existing
  `SPELLS_CHANGED` refresh path already re-resolves bar icons; the panel is transient and re-shown
  fresh, so no extra wiring is needed beyond resolving on show.
- Allocation discipline (Lua 5.0 / shared-addon budget): build the panel + icon widgets once, reuse;
  no per-frame allocation; the panel has no `OnUpdate` (it is event-driven show/hide).
- All user-facing strings in **English**.

## Persistence

- The pending assignment is **in-memory only** (not a SavedVariable). A reload/login discards any
  un-accepted pending suggestion (an assignment is ephemeral coordination). The **applied** result
  is just `TotemBarDB.chosen[]`, which already persists. Keeps SavedVariables clean.

## Dev / self-test

- `/tb assign` slash subcommand: injects a hardcoded sample assignment (e.g.
  `Fire="Searing Totem", Earth="Strength of Earth Totem", Water="Mana Spring Totem",
  Air="Grace of Air Totem", label="TEST"`) via `TotemBar.ReceiveAssignment`, so the pending panel
  + accept/decline flow can be exercised **end-to-end without any transport or ShamiPower**. Add it
  to the `/tb` help/usage line.

## Out of scope (deferred to ShamiPower)

- Addon-comms transport: `SendAddonMessage`/`CHAT_MSG_ADDON` listener, wire format, ≤254-byte
  chunking, send-queue throttling, prefix conventions, version handshake.
- The assigner UI: raid grid, roster, per-group / per-shaman assignment, "who covers what".
- Live totem-state broadcast / coverage tracking.
- Persisting or queuing multiple pending assignments (only one pending at a time here).

## Testing

- **Offline Lua 5.0** (`tools/luatests/`, run with `lua50.exe`): the pure-logic units —
  - `validateAssignment(set)` → ok / (false, reason) for: non-table, empty, unknown element key,
    non-string totem name.
  - `GetChosenSet()` copy semantics (returns a copy; mutating the result must not touch
    `TotemBarDB.chosen`) — factor the copy into a pure helper if it eases testing.
  - the "applicable elements" filter (given a set + a known-totem predicate, which elements apply).
  Factor these as pure functions so they are testable without WoW API.
- **In-game** (ground truth): `/tb assign` → panel appears with the 4 correct icons + label →
  Accept → the 4 chosen totems update on the bar (icons + tooltips) → dropping via the existing
  click/macro works. Decline → panel hides, chosen totems unchanged. Assign a totem the character
  does not know → that slot shows greyed and is skipped on accept.

## Files touched

- **New** `core/assign.lua` — the non-UI seam: `validateAssignment`, `GetChosenSet`, the apply
  helper, pending-state holder, and the pure helpers the offline tests import. Keep it WoW-API-light
  so its logic is offline-testable; UI stays in `ui.lua`.
- `ui.lua` — the `TotemBarAssignFrame` pending panel (lazy build, icons, Accept/decline), the
  `/tb assign` dev command, and the updated help line.
- `TotemBar.toc` — add `core\assign.lua` **before** `ui.lua`.
  ⚠️ TOC change → **full client restart** required (not just `/reload`).
- `tools/luatests/test_assign.lua` — offline tests for the pure helpers, plus a tiny harness stub
  for `TotemBarDB` / element list.

## Verification envelope

- Offline unit tests green under real Lua 5.0.3 (`lua50.exe`).
- `lua50.exe -e 'assert(loadfile("..."))'` parse-check on the WoW-API files.
- In-game confirmation of the `/tb assign` → panel → accept/decline flow before claiming done.
- On in-game confirmation, write the seam contract (the `set` shape + `ReceiveAssignment` API) back
  to the KG (`domain=wow`, `created_by_engine:"addon-dev-cc"`, `verification:"in-game-confirmed"`)
  so ShamiPower can be built against a recorded contract.
