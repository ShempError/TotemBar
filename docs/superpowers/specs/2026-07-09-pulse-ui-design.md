# TotemBar Pulse UI — Design Spec (2026-07-09)

> Status: TEST BUILD ONLY — no commit, no release. Supersedes the external "TotemBar Pulse UI
> Blueprint" (ChatGPT draft) that motivated this work; deviations from that blueprint are
> deliberate and justified inline.

## 1. Goal

Each element slot on the bar shows **two separate time readings** at a glance:

1. **On-ground totem duration** — a depleting **ring/frame around the icon** (element-colored).
2. **Time to next pulse** — a **horizontal bar under the icon** that fills up toward the next
   pulse, then visibly resets.

Both visual styles are built and switchable at runtime for in-game comparison (Phil's call):

- **Round style**: circular duration ring; the ring asset's opaque corners visually round the
  icon (the button backdrop is already opaque black, so masked corners blend seamlessly).
- **Square style**: rectangular frame sweep around the unchanged square icon (pfUI-consistent).

Constraints: WoW 1.12.1 / Lua 5.0, TurtleWoW, zero per-tick allocation, compact bar unchanged
in footprint (6 buttons: Fire/Earth/Water/Air + Recall + DropSet), all user-facing strings in
English, existing features untouched (GCD swipe, out-of-range red tint, keybind overlays,
flyout, recall guard).

## 2. Non-goals

- **No pulse bar for aura totems** (Windfury, Grace of Air, Strength of Earth, Stoneskin,
  Flametongue, Mana Tide as buff). The KG models these as continuous auras; the blueprint's
  assumed "10s reapply pulse" is unverified. We do not display invented information.
- **No pulse bar for Searing Totem** (irregular attack cadence, not a fixed pulse) and
  **Grounding Totem** (event-consumed, not timed).
- **No radius/range display** (totem aura radius is not readable via Lua — KG in-game-confirmed).
- **No slot layout redesign** (blueprint §2 proposes 6 semantic slots; our bar already has an
  equivalent, working layout).
- **No detection of enemy-destroyed totems** in this test build (own-tracking limitation,
  see §8 Risks; pfUI libtotem covers it when present).
- No commit/release; deploy is a local test only.

## 3. Data: pulse model per totem

New pure module **`core/pulsedata.lua`** (follows `core/totemdata.lua` style):

```lua
-- TotemBar.PULSE_DATA[totemName] = {
--   interval  = seconds between pulses (type "tick"),
--   delay     = seconds from placement to detonation (type "oneshot"),
--   ptype     = "tick" | "oneshot",
--   anchor    = "selfgain" | nil,   -- which live event re-anchors the phase
--   verified  = false,              -- flips to true once measured on TurtleWoW
-- }
```

Initial (book-value) entries — **all `verified = false`**, to be calibrated in-game (§7):

| Totem | ptype | interval/delay | anchor | source confidence |
|---|---|---|---|---|
| Magma Totem | tick | 2.0 | nil (phase 2: damage events) | KG 0.6 (web) |
| Tremor Totem | tick | 3.0 | nil | KG 0.6 (web) |
| Earthbind Totem | tick | 3.0 | nil | book only |
| Poison Cleansing Totem | tick | 5.0 | nil | book only (KG empty) |
| Disease Cleansing Totem | tick | 5.0 | nil | book only (KG empty) |
| Healing Stream Totem | tick | 2.0 | "selfgain" | book only (KG empty) |
| Mana Spring Totem | tick | 2.0 | "selfgain" | book only (KG empty) |
| Fire Nova Totem | oneshot | 4.0 | nil | book only (KG has no delay value) |

Totems absent from this table get **no pulse bar** (blueprint edge case §14: "lieber Balken
ausblenden als falsche Information zeigen").

`anchor = "selfgain"` totems re-anchor their pulse phase on the actual periodic self-gain
combat message ("You gain N Mana from Mana Spring Totem." / health gain from Healing Stream),
so their bars show the **real** pulse phase, not dead reckoning. This is the main correctness
win over the blueprint. Magma/Tremor/Cleansing anchoring is deferred until `/tb pulsecal`
telemetry (§7) shows which events actually fire on TurtleWoW (Parsec history: totem damage
events were lossy ~50%, so damage-anchoring must be proven before use).

## 4. Pure logic modules (offline Lua 5.0 TDD)

**`core/pulse.lua`** — math only, no WoW API:

- `TotemBar.pulseRatio(placedAt, anchorAt, interval, now)` → 0..1. Phase origin is `anchorAt`
  when set (last observed pulse), else `placedAt`. Wrap via `math.mod` (Lua 5.0 — NOT `%`).
- `TotemBar.oneshotRatio(placedAt, delay, now)` → 0..1 clamped; 1 means detonation reached.
- `TotemBar.pulseImminent(ratio)` → true when `ratio >= 0.85` (blueprint state D).
- `TotemBar.ringFrameIndex(remaining, duration, frameCount)` → integer 0..frameCount-1
  (0 = empty, max = full), `math.floor(ratio * (frameCount-1) + 0.5)`.
- `TotemBar.buildRingTexCoords(frameCount, cols, cellUV)` → precomputed array of
  `{l, r, t, b}` per frame index, built once at load; per-tick lookup is table indexing only
  (zero allocation, zero math).

**`core/pulseparse.lua`** — pure string parsing, Lua 5.0 only (`string.find` with captures;
no `string.match`/`gmatch`, no `#`, no method-call syntax on strings):

- `TotemBar.parseSelfGain(msg)` → totemName or nil. Recognizes
  `"You gain %d+ [Mm]ana from (.-)%.$"` and health-gain variants; returns the source name
  only when it ends in `"Totem"` (plain-find guard first to stay cheap on every combat line).
  Exact accepted patterns are pinned by offline tests against literal 1.12 message strings.

Both modules get `tools/luatests/test_pulse.lua` + `test_pulseparse.lua` (harness `H.assert_eq`,
run with `lua50.exe` from repo root). Edge cases pinned: ratio wrap at exactly `interval`,
`now < anchorAt` (clock skew → clamp 0), remaining ≤ 0, frameCount boundaries, multi-digit
gains, mana vs. health wording, non-totem sources rejected.

## 5. Rendering

### 5.1 Ring (duration) — flipbook, not segments

Blueprint §9.2 recommends a 12-segment show/hide ring; rejected — chunky look, 12+ widgets per
slot. Also rejected: a second `CooldownFrameTemplate` Model (grey, uncolorable, direction
fixed, visually collides with the existing GCD swipe on the same icon — KG-verified 1.12
limits). Instead:

**One 512×512 32-bit TGA per style** (`textures/ring_round.tga`, `textures/ring_square.tga`),
laid out as an 8×8 grid of 64×64 cells:

- Cells 0..62: fill states (0 = empty, 62 = full). White arc, transparent elsewhere —
  runtime-tinted per element via `SetVertexColor`.
- Cell 63: static **track** (dim grey full ring/frame). In the round asset the track cell also
  carries the **opaque black corner mask** outside the ring's outer circle (rounds the icon
  for free against the opaque button backdrop).

TGA format is pinned to what pfUI ships and 1.12 provably renders: type 2 (uncompressed),
32 bpp, descriptor 0x08 (bottom-up, 8 alpha bits), power-of-2 dimensions.
Texture paths are passed to `SetTexture` **without extension** (client resolves .blp/.tga).

Per element button, two new textures (both `OVERLAY` layer, `SetAllPoints(btn)`):

- `btn.ringTrack` — `SetTexCoord` fixed to cell 63, shown while a totem is active.
- `btn.ringFill` — `SetTexCoord` from the precomputed frame table (§4), vertex-colored:
  Fire = orange, Earth = green, Water = blue, Air = violet (single shared color table,
  bright variants precomputed for the glow state — no per-tick table/string creation).

Style switch (round ↔ square) = two `SetTexture` calls per button at options-toggle time;
no reload needed. Fill arcs deplete clockwise from top (12 o'clock), matching the familiar
cooldown direction.

**Generator**: `tools/gen_ring_textures.js` (Node, zero deps) renders both files with 4×
supersampling; ring geometry (outer/inner radius, frame band width) is parameterized at the
top of the script for quick visual tuning. The generated TGAs live in `textures/` as regular
assets (small, ~1 MB scale — no binary-size concern for a later release commit); in this test
phase nothing is committed at all.

Fallback if the TGA path fails in-game against expectation: square style via four thin
StatusBar strips (stock textures, square-only); round style would then be dropped. Decision
point: first in-game look.

### 5.2 Pulse bar

Per element button: `btn.pulseBar = CreateFrame("StatusBar", name.."PulseBar", btn)` —
anchored `TOPLEFT`/`TOPRIGHT` to the button's `BOTTOMLEFT`/`BOTTOMRIGHT`, height 5, 1px dark
backdrop; fill texture = `pfUI.media` statusbar when pfUI is present, else
`Interface\TargetingFrame\UI-StatusBar`; `SetMinMaxValues(0, 1)`, element-colored.

- Fills 0→1 toward the next pulse, resets on wrap (blueprint §3.2 semantics).
- **Oneshot** (Fire Nova): single fill 0→1 over `delay`, bar hides at 1 (detonation).
- **Imminent glow** (state D): at ratio ≥ 0.85 the fill color switches to the precomputed
  bright variant. No extra glow textures in the test build (cheap, readable, reversible).
- Hidden when: slot has no active totem, totem has no `PULSE_DATA` entry, or the
  `showPulseBars` option is off.

`btn.timerText` (existing countdown text) re-anchors below the pulse bar when bars are
enabled; stays directly under the button otherwise. The bar hangs below the button exactly
like the timer text already does today (1.12 frames don't clip child regions — see the
existing comment at ui.lua:554-562), so the bar frame's size stays untouched. Recall/DropSet
buttons and flyout icons are untouched.

### 5.3 Update path & states

No new OnUpdate handler. The existing `OnBarUpdate` → `UpdateTimerDisplays` tick drives
everything; `TIMER_UPDATE_INTERVAL` drops **0.2s → 0.1s** (blueprint recommends 0.05–0.1;
0.1 is smooth enough for a 5px bar and halves nothing else — per tick we do ≤4 × (one
`SetValue`, one `SetTexCoord` from a lookup, conditional `SetStatusBarColor`), all
allocation-free).

Slot states map 1:1 to blueprint §4: A (no totem → ring+bar hidden), B (active, no pulse
entry → ring only), C (active pulse totem → ring+bar), D (imminent → bright fill),
E (expired/recalled → everything reset; existing eviction in `UpdateTimerDisplays` plus §5.4).

Ring input is the **already-merged** remaining/duration truth: own-tracking
(`TotemBar.activeTotems`, `core/cast.lua:162-186`) merged with pfUI libtotem via
`TotemBar.resolveRemaining` (`core/cast.lua:105-116`). No new tracking source.

### 5.4 Recall correctness (verified against the code — already handled)

Plan-time correction: the assumed gap does not exist. `TotemBar.clearActiveTotems()`
(core/cast.lua:246-250) is already called on every recall path TotemBar controls — the
recall button (ui.lua:747), `recallAndCastAll` (core/cast.lua:374), and the recall
keybinding (bind.lua:63-65). Ring and pulse bar therefore reset through the normal
eviction/resolve path with no new work. The remaining limitation is a recall cast entirely
outside TotemBar (spellbook/macro) without pfUI present — own-tracking then over-reports
until the stored duration expires; accepted for this test build (pfUI's libtotem covers it
when present, as today).

### 5.5 Event re-anchoring

`ui.lua` registers `CHAT_MSG_SPELL_PERIODIC_SELF_BUFF`; handler does a cheap
`string.find(arg1, "Totem", 1, true)` plain guard, then `TotemBar.parseSelfGain`, then stamps
`activeTotems[element].pulseAnchor = GetTime()` for the matching element. Parsing allocates
only on matching events (a few per second at worst while totems are down) — acceptable, and
the plain-find guard rejects everything else in O(1) practical cost.

## 6. Options & SavedVariables

New `TotemBarDB` defaults (in `core/config.lua` `ensureDefaults`):

- `showDurationRing = true`
- `ringStyle = "round"` (`"round" | "square"` — the comparison toggle)
- `showPulseBars = true`
- `pulseGlow = true`
- `showTimerText = true` (existing text becomes toggleable; default preserves today's look)

Options panel additions (`options.lua`, existing pfUI-skinned factories): checkboxes
"Show duration ring", "Round ring style", "Show pulse bars", "Pulse glow", "Show countdown
text". All take effect immediately (show/hide + SetTexture swap), no reload. All UI strings
English (house rule).

## 7. Calibration telemetry — `/tb pulsecal` (dev-only)

Purpose: replace every `verified = false` book value with a TurtleWoW-measured one, and learn
which combat events can anchor Magma/Tremor/Cleansing. Follows the established
dev-only-selftest-telemetry pattern (SuperWoW file channel).

New module `core/pulsecal.lua` + slash verbs on the existing `/tb` handler:

- `/tb pulsecal start` — registers a capture listener on: all `CHAT_MSG_SPELL_PERIODIC_*`
  variants, `CHAT_MSG_SPELL_SELF_DAMAGE`, `CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE`,
  `CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS`, plus SuperWoW `UNIT_CASTEVENT`, plus our own
  `recordCast` placements. Records `GetTime()`, event name, raw `arg1` into a fixed-size
  ring buffer (cap 2000, index-wrapped, entries reused — no growth) **only** when the message
  plain-contains "Totem" or the event is a placement.
- `/tb pulsecal dump` — `ExportFile("totembar_pulsecal", ...)` (SuperWoW; filename WITHOUT
  extension — the client appends `.txt`). One line per record: `t;event;msg`.
- `/tb pulsecal stop` / `status` — teardown / counters.

Workflow: Phil drops totems and plays; CC reads `C:\turtle\imports\totembar_pulsecal.txt`,
computes inter-event deltas per totem, updates `core/pulsedata.lua` (`verified = true`), and
writes the measured values to the KG (`domain=wow`, `created_by_engine:"addon-dev-cc"`,
`verification:"in-game-confirmed"`) — closing the exact gaps the KG audit found (Cleansing
intervals, Healing Stream/Mana Spring tick, Fire Nova delay, first-pulse offsets, whether
aura totems visibly pulse at all).

## 8. Risks & open questions

- **Unverified intervals ship in the first test build** (bars could be phase-shifted or
  wrong-period for non-anchored totems). Accepted for a local test; telemetry exists to fix
  it fast, and `anchor="selfgain"` totems self-correct from the first observed tick.
- **Magma/Tremor/Cleansing anchor events unknown on TurtleWoW**; damage-event anchoring has a
  known lossy precedent (Parsec ~50%). Until telemetry proves reliability, these stay
  dead-reckoned.
- **Enemy-destroyed totems** are not detected without pfUI (ring keeps running until timer
  end). Known limitation, noted in §2; a libbettertotem-style `UnitExists` tracker is a
  possible future phase, out of scope here.
- **TGA rendering**: format pinned to pfUI's proven header; residual risk covered by the
  StatusBar-strip fallback (§5.1).
- **First-pulse offset** (does a totem pulse at t=0 or t=interval?) is unknown for every
  totem; test build assumes t=interval (bar starts empty at placement). Telemetry decides.

## 9. Testing & acceptance

**Offline (must be green before deploy):**

1. `lua50.exe tools/luatests/test_pulse.lua` / `test_pulseparse.lua` — new pure logic.
2. Existing suite stays green (no regressions in cast/duration/options logic).
3. `lua50.exe -e 'assert(loadfile("..."))'` syntax check on every touched/new `.lua`.
4. Mechanical Lua 5.0 lint over all `.lua`: no `#`, no string method-call syntax, no
   `string.match`/`gmatch`, no `%` modulo on numbers where `math.mod` is meant.
5. Generator run produces both TGAs; header bytes verified (type 2, bpp 32, desc 0x08,
   512×512).

**In-game (client FULL RESTART required — new files + textures):**

6. Ring shows on active element slots and depletes with remaining duration; both styles
   switchable live in options; round style visually rounds the icon.
7. Pulse bars run for all table totems; Mana Spring / Healing Stream bars visibly re-anchor
   on real gain ticks; Fire Nova bar is a one-shot arming countdown.
8. Bar resets visibly on each pulse (state C→wrap), glow at ≥85% (state D), everything
   clears on expiry AND on recall (state E, incl. §5.4 fix without pfUI).
9. No ERROR #132, no visible FPS impact, existing features intact (GCD swipe, red
   out-of-range tint, keybind overlays, flyout, recall guard, DropSet).
10. `/tb pulsecal` capture + dump readable from `C:\turtle\imports`; at least Water-totem
    intervals measured and baked back as `verified = true` + KG atoms.

## Rev 2 (2026-07-10) — Phil's in-game feedback on the first test build

Verdict on Rev 1: "weder Fisch noch Fleisch" — the round icons sat inside visible square
button boxes (the corner mask only worked against the opaque backdrop), and the pulse bar
read as a loading bar, not a pulse. Rev 2 changes:

1. **Truly floating round icons, no backframe.** The square button/bar backdrops become
   fully transparent. Corner hiding no longer relies on the backdrop: the decorative ring
   band itself is thick enough to cover the icon's corners (band outer radius ≥ icon
   half-diagonal), and everything outside the band is transparent. One asset serves as
   frame + duration ring.
2. **The ring is the frame ("schicker Rahmen"):** always visible (dark beveled band);
   the element-colored duration arc depletes ON the band while a totem is active.
3. **Flyout icons, Recall and DropSet get the same round frame** (no duration arc for
   Recall/DropSet; flyout icons keep their cooldown swipe).
4. **Pulse = ripple, not bar.** The StatusBar is removed. At each pulse an expanding,
   fading ring wave in the element color emanates from the icon (water-ripple look),
   phase-locked to the same anchored pulse math. Fire Nova emits one wave at detonation.
   Wave animation runs per-frame (pure math + Set* calls, zero allocation — same class as
   the existing OnRecallUpdate); everything else stays on the 0.1s tick.
5. **Square style dropped** (Phil decided for round), so the "Round ring style" and
   "Pulse glow" checkboxes go away; "Show pulse bars" becomes "Show pulse waves"
   (SavedVars key `showPulseBars` kept to avoid migration churn).
6. Texture v2 (`textures/ring_round.tga`, same path): cells 0..61 duration-arc frames
   (62 states), cell 62 = wave ring (soft-edged, runtime-scaled), cell 63 = decorative
   frame band. `ring_square.tga` is no longer used or generated.

## 10. Blueprint deviations (summary)

| Blueprint says | We do | Why |
|---|---|---|
| Segmented 12/16-piece ring, "most robust" | 63-state flipbook from one TGA | smoother, 2 widgets/slot, zero-alloc; segments are the *less* robust 1.12 path |
| Dead-reckoned pulse timing | Event re-anchored where observable + telemetry-calibrated values | TWoW intervals are unmeasured; guessing violates the addon's own §14 principle |
| Pulse list: Tremor, Cleansing×2, Magma, Earthbind | + Healing Stream, Mana Spring, Fire Nova (oneshot) | the most observable pulses were missing; Fire Nova arming is a natural one-shot bar |
| Aura totems pulse every 10s (implied later) | No pulse bar for aura totems | unverified mechanic; KG models them as continuous |
| New 6-slot bar layout | Keep existing 6-button bar | already equivalent and shipped |
| 48px icons, 0.05s updates | Keep 36px buttons, 0.1s tick | bar must stay compact (Phil), 0.1s is visually smooth at 5px |
| Round icons via generic masking | Corner mask baked into ring track cell | 1.12 has no texture masking; opaque-backdrop trick is the verified path |
