# Changelog

All notable changes to TotemBar are documented here.

## v0.4.1 — 2026-08-31

### Fixed
- A totem destroyed by the enemy inside the ~0.4s window between a Totemic Recall wipe and its
  refusal being attributed now stays dead instead of having its countdown resurrected by the
  refused-recall restore (`core/cast.lua`).

## v0.4.0 — 2026-08-30

### Added
- **Destroyed totems can now be detected while SuperWoW is present (verified against captured
  event log 2026-08-20, live eviction pending retest).** A totem killed before its timer ran
  out used to keep counting down as if it were still standing — both TotemBar's own tracking
  and pfUI's libtotem are blind, duration-only timers, and neither ever checked whether the
  totem itself was still alive (pfUI's `GetTotemInfo` was previously assumed to cover this
  case; checked against its source — it does not). A live event tap against the real client
  (2026-08-20) captured totem spawn/pulse/death lines and found the original mechanism could
  never have fired at all: the spawn/pulse latch paths compared totem names for *exact*
  equality, but the live client hands back a *ranked* name ("Searing Totem VI"), never the bare
  book name; and the pulse-cast latch mapped through the pulse *spell's* name ("Searing Bolt"),
  which is not the totem's own name either. Both are now fixed, and a third, GUID-free signal
  was added as the primary path:
  1. **Primary — `CHAT_MSG_COMBAT_FRIENDLY_DEATH`** (native 1.12, needs no SuperWoW/nampower):
     TurtleWoW emits a totem's own death as `"<Name> (<Owner>) is destroyed."` verbatim; parsed
     and evicted once the owner resolves to the player and the name rank-tolerantly matches a
     tracked totem. The generic vanilla `"<Name> dies."` form is accepted as a second, stricter
     shape — since it carries no owner, it only evicts a candidate that already has a latched
     GUID, confirmed via a live `UnitExists`/`UnitHealth`/`UnitIsDeadOrGhost` read.
  2. **`UNIT_CASTEVENT`** (SuperWoW), for totems that periodically cast their own pulse — now
     keyed off `UnitName(casterGUID)` (the totem unit's own, rank-tolerant name) instead of the
     pulse spell's name; covers only pulsing totems (Searing/Magma/Fire Nova/Mana Spring/
     Healing Stream/Mana Tide/the Cleansing totems), gated on the caster's resolved owner
     matching the player.
  3. **`UNIT_MODEL_CHANGED`** (native 1.12), for totems that never cast anything visible — now
     rank-tolerant instead of an exact name compare.
  4. **`UNIT_DIED`** (nampower), extended with a GUID-free fallback: when no GUID was ever
     latched, a rank-tolerant name + owner match at the death instant (both resolve reliably
     there per the captured log) still evicts.

  A totem confirmed destroyed is evicted immediately and tombstoned for the remainder of its
  own natural duration, so pfUI's libtotem — itself just another blind timer — cannot
  resurrect the countdown/ring/pulse a moment later; a real re-cast on that element clears the
  tombstone right away. This clears the countdown, duration ring, pulse animation and
  out-of-range tint together, since all four already derive from the same tracking record. On
  a client without SuperWoW, only the primary `CHAT_MSG_COMBAT_FRIENDLY_DEATH` signal is
  active; without either SuperWoW or TurtleWoW's own death-line wording, behaviour is
  byte-for-byte unchanged from before this feature. The decision logic (name matching, line
  parsing, eviction gating) is fully offline-tested against the captured fixture lines (95
  assertions in `tools/luatests/test_destroy.lua`); a live totem-kill retest with the addon
  in the loop is still pending — `/tb tdump` prints each totem's latched `guid`, the raw
  `UnitExists`/`UnitHealth`/`UnitIsDeadOrGhost` reads, and (for an evicted slot) its tombstone
  status, for that verification.

### Fixed
- **A totem's countdown no longer starts when the cast was refused for lack of mana.** The
  pre-cast mana gate stood down completely while Clearcasting (Elemental Focus) was up, on the
  assumption that it zeroes the next cast's price. Elemental Focus covers the shaman's damage
  spells, not totem summons -- so a totem costs full mana while Clearcasting is up, and since
  totems are the only thing this addon casts, that exemption disabled the mana gate outright.
  The client then refused the cast while the timer had already been recorded, leaving a
  countdown running for a totem that was never placed. The exemption is gone from the cast
  gate, the out-of-mana dim and the flyout tint alike; the unverified buff-icon constant it
  relied on went with it. The gate still accepts (and ignores) the old sixth argument, so no
  stale caller can quietly reinstate it.

- **A Totemic Recall the server refuses no longer wipes your totem timers.**
  Recall already checked whether the cast could go out *before* touching the
  tracking, but a press that passes that check can still be refused after the
  fact — moving at the wrong moment, a stun or silence landing first, or plain
  latency. The tracking was cleared unconditionally the instant the cast was
  issued, so a refused Recall left the addon believing nothing was out while a
  full set kept standing — the same phantom-state bug class the totem casts'
  own two-layer guard already closed, mirrored. The recall paths now remember
  what they cleared, and the same failure signals that take back a refused
  totem's countdown (the exact per-spell one with nampower, the error-message
  fallback without it) put the timers back. The restore follows the same
  narrow rules as the totem-cast revoke: only when the Recall itself was the
  last cast attempted, only within a short window afterward, and never over a
  slot a new cast has already refilled — when attribution is uncertain it
  stays silent, since here a *wrongly restored* timer would be the phantom.
  Covers the Recall button, its keybind, and the DropSet keybind's recall
  stroke alike.

## v0.3.0 — 2026-08-15

### Added
- **Totems you cannot afford are dimmed.** Element buttons and the hover flyout
  grey out while your mana is below the totem's cost, so the bar shows what is
  actually castable instead of only what is chosen. The cost is the real one for
  your highest known rank, including cost talents, and the dim composes with the
  out-of-range tint rather than replacing it — an out-of-range totem you also
  cannot afford still reads as red, just darker. Clearcasting suspends it, since
  the next spell is free while it is up.

### Fixed
- **A refused cast no longer starts a countdown, and one that already started
  can now be taken back.** Pressing a totem without the mana for it (or while
  it is genuinely on cooldown) used to start a full timer for a totem that was
  never placed — which also made Totemic Recall believe something was out and
  burn its 6s cooldown on an empty board. The cast's chances are now checked
  *before* it leaves, so an attempt that cannot have gone through is never
  tracked in the first place. A second layer catches what the pre-check
  cannot predict — movement, another action already in progress, a stun, or a
  server-side refusal — by watching the client's own "cast failed" signal
  (the exact one with nampower, an error-message fallback without it) and
  undoing the countdown after the fact. That revoke is filtered narrowly on
  purpose: it only fires for the totem cast just attempted, only within a
  short window afterward, and only for messages the client is known to use
  for a refused cast, so it stays silent whenever it cannot be sure — a
  refused *repeat* press restores the original timer rather than clearing it.
  In every case where attribution is uncertain, this fails **closed**: no
  revoke happens, and the existing timer is left standing, because a missing
  timer is worse than a phantom one.
- **Totemic Recall no longer wipes your totem timers on a press that could not
  have gone out.** Recall's own 6s cooldown or the global cooldown could
  refuse a manual Recall press while the button and keybind still cleared the
  addon's totem tracking as if it had fired — after which the addon believed
  nothing was out and refused every further Recall press until something
  re-armed it. Recall now checks whether the cast can actually go out before
  it touches the tracking, and a press that cannot keeps it intact.
- **Totemic Recall no longer wastes its cooldown on a no-op moments after your
  totems expire.** The check for "is anything even out" relied on the totem
  tracking table staying occupied, but that table is emptied the instant each
  totem's own timer runs out — so within a fraction of a second of the last
  totem expiring, Recall forgot it had ever cast anything and let a needless
  press through, burning the cooldown on an empty board. A separate flag now
  answers "did we cast this session", so the check survives normal timer
  expiry as intended.
- **The Recall button and its keybind can no longer sweep away a set you just
  redeployed.** Both issued a plain Totemic Recall cast, which nampower
  queues behind the global cooldown — so pressing Recall during a GCD could
  fire it *after* you had already placed your totems again, recalling the
  set you had just dropped. Both now share the same queue-safe cast the
  automatic recall paths already used, so a GCD-blocked press is skipped
  instead of firing late.
- **A totem you have not learned no longer starts a countdown.** The saved
  totem set is account-wide and not checked against the spellbook, so a set
  carried over from another character could land on one that never learned
  those totems. Casting it was a guaranteed no-op, but it still started a
  full phantom timer and made Totemic Recall think something was out.
- **Sentry Totem's timer no longer expires 180 seconds early.** It was
  missing its own duration entry and silently fell back to a generic
  120-second default, well short of the totem's real 5-minute duration.
- **The seventh Air totem is no longer dropped from the hover flyout.** The
  flyout's icon pool was sized for six totems, but Air offers seven — with
  the Air slot left empty, the last entry could neither be cast nor be set
  as the slot's new default from the bar.
- **Windwall Totem no longer reads permanently in-range once you are also
  carrying Strength of Earth Totem.** The range check matched buff icons by
  an unanchored substring, and Strength of Earth Totem's icon name happens to
  start with Windwall's, so carrying one made the other's out-of-range tint
  never trigger.
- **A totem pulse from another shaman can no longer drag your own pulse ring
  backward.** The periodic self-heal/self-mana messages TotemBar reads to
  time the pulse ring carry no caster information, so an identically worded
  tick from someone else's totem re-anchored the phase and made the ring
  visibly jump. Anchoring is now limited to at most once per pulse interval.
- **The out-of-range tint no longer skips most of a freshly-placed set when
  pfUI is loaded.** pfUI's own totem tracking commits at most one totem per
  cast, so dropping a full four-totem set left three slots with no
  information from it at all — and those slots were treated as "known to be
  in range" instead of falling back to TotemBar's own tracking, so most of
  the set never turned red out of range or pulsed the Recall button.
- **The duration ring no longer counts down, jumps back up, and counts down
  again with Totemic Mastery talented.** TotemBar's own tracking stores the
  Mastery-inflated duration while pfUI's totem data reports the shorter flat
  spellbook value; the display preferred pfUI's number until it ran out, then
  jumped back up to the correct remaining time. Both sources now agree on the
  same, Mastery-scaled endpoint.

## v0.2.5 — 2026-07-25

### Added
- **New option: "Show drop-all button".** The drop-all-totems button can now be
  hidden from the bar, for anyone who drives it purely from a keybind or a macro
  and would rather not spend the slot on it. On by default, so nothing changes
  unless you turn it off.
  - **The keybind keeps working while the button is hidden.** It is bound to the
    cast function, not to the frame, and the entry stays listed in the Esc key
    bindings menu — otherwise you could never assign it again.
  - **The bar resizes instead of leaving a gap.** In the 1×6 layout it shrinks by
    one slot. In 2×3 and 3×2 the frame keeps its size on purpose: Recall still
    needs the last column, and shrinking there would break up the 2×2 block of
    the four element totems. What remains is one empty grid cell in the trailing
    corner — invisible, and it simply adds drag area.

## v0.2.4 — 2026-07-14

### Fixed
- **Totemic Recall no longer refuses to fire after a /reload.** The "no totems
  out — not recalling" guard could block a legitimate recall: TotemBar tracks
  which totems you've dropped in memory only, and a `/reload` wipes that memory.
  On 1.12 there is no `GetTotemInfo` / totem unit-id to re-detect a totem that
  was placed before the reload, so the addon wrongly concluded nothing was out
  and refused to recall. The guard now blocks **only** when it is certain nothing
  is out (it tracked totems this session and they've all expired); after a
  /reload the state is unknown, so it fails open and lets the recall through.
  Worst case is one needless recall right after a reload — far better than a
  blocked one.

## v0.2.3 — 2026-07-13

### Fixed
- **Totemic Recall no longer sweeps away a freshly-placed set (nampower).**
  With nampower installed, dropping your set while the global cooldown was
  active could make the new totems appear and then instantly vanish: nampower
  queued Totemic Recall behind the GCD, so it fired *after* the (off-GCD)
  totems were placed and pulled them right back down. TotemBar now casts
  Recall via `CastSpellByNameNoQueue` when nampower provides it, so a
  GCD-blocked Recall is skipped for that press instead of firing late. No
  effect for setups without nampower.

### Changed
- **The drop-set keybind now recalls on key-down and places on key-release.**
  This keeps the recall and the totem placements as separate hardware events;
  for a normal tap the difference is imperceptible.

## v0.2.2 — 2026-07-10

### Added
- **"Button spacing" slider** in the options panel (10–30 px) — adjusts the
  gap between bar buttons live, including the flyout and assignment panel.

### Fixed
- **Keybind casts now start TotemBar's own duration/pulse timers.**
  Per-totem and element key bindings call the same tracking as click-casts.
  Previously, setups without pfUI got no timer/ring/pulse feedback for
  keybind-cast totems, and even with pfUI the spawn ripple and out-of-range
  tint were missing for them.

### Removed
- **Dead `pulseGlow` setting** — the anticipation glow is part of "Show
  pulse waves"; stale saved values are cleaned up automatically.

## v0.2.1 — 2026-07-10

### Fixed
- **Tooltips showed rank 1 instead of your highest rank.** Both totem
  tooltips (element buttons and the flyout) resolved the spell by its first
  spellbook match — which is rank 1 — so mana cost, damage and duration read
  far too low. Display-only: the actual cast is name-based and always used
  your highest rank. Tooltips now resolve to the highest known rank **and
  show the rank** next to the spell name (vanilla's tooltip omits it).

## v0.2.0 — 2026-07-10

**The Pulse UI release** — a complete visual rework of the bar around one idea:
you should see at a glance *how long* each totem still stands and *when* it
pulses next.

### Added
- **Round floating slots.** Buttons are free-floating round icons in a subtle
  shadow-rim frame — the square boxes and backdrops are gone. Flyout, Recall
  and drop-set share the round look (round hover/pressed states included).
- **Duration ring (time traffic light).** The outer ring drains with the
  totem's remaining lifetime and blends green → yellow → orange → red as time
  runs out.
- **Pulse ring.** A thin inner arc in the totem's element color fills toward
  the next pulse and resets when it fires — animated per frame, no stutter.
- **Server-accurate pulse timing.** Intervals and first-tick behavior come
  from TurtleWoW server data, not guesswork: e.g. Tremor pulses every **4s**
  (not the commonly cited 3s) and ticks **immediately** on placement, while
  Magma/Healing Stream/Mana Spring first pulse one full interval after
  placement. Water totems additionally re-anchor on the real observed
  mana/heal ticks.
- **Pulse waves & anticipation glow.** An expanding ripple in the element
  color marks each pulse; a soft halo builds around the ring during the last
  stretch before it. A spawn ripple confirms every placement.
- **Bar layouts.** Cycle between 1×6, 2×3 (elements grouped as a 2×2 block)
  and 3×2 in the options panel.
- **Custom art set.** Element glyphs for empty slots (no more question
  marks), a four-element drop-set icon, a minimap glyph, a custom options
  panel skin with rounded corners, and grounding shadow plates under the
  slots. All art is generated by scripts in `tools/` — reproducible, no
  binary-only assets.
- **New options:** Show duration ring · Show pulse ring · Show pulse waves ·
  Show countdown text · Layout.
- **`/tb pulsecal` (dev aid):** captures pulse-timing telemetry to
  `imports\totembar_pulsecal.txt` (SuperWoW) for verifying timings in-game.

### Changed
- Button spacing widened (4 → 10 px) to give the ring frames air; multi-row
  layouts use the same tight pitch vertically.
- Options panel restyled with the custom skin and section dividers.
- The remaining-time countdown text is now optional (on by default).

## v0.1.3 — 2026-07-09

### Fixed
- **Totemic Recall no longer wastes its 6-second cooldown.** Recall — via the
  button, its keybinding, or the "Totems" macro's auto-recall — now only fires
  when you actually have totems out. Casting it with nothing down put Recall on
  its 6s cooldown, so a set placed right after couldn't be recalled for 6
  seconds. With nothing out, TotemBar now skips the cast (with a brief note).

## v0.1.2 — 2026-07-09

### Added
- **Mana cost on the drop-set tooltip** — hovering the drop-set button (and the
  "Totems" macro action) shows the total mana to drop your four chosen totems.
- **Refund on the Totemic Recall tooltip** — shows the mana you'll get back,
  computed live from the totems currently out (expired ones are excluded) and a
  refund percentage that is learned from your real recall mana-gain (defaults to
  25% until learned).
- **Totemic Mastery duration** — when the talent is skilled, helpful totems'
  own-tracked timers get the +20% duration so they no longer read short.
- `/tb manadump` dev aid — writes the raw mana-cost scan (resolved rank, tooltip
  lines, parsed cost) to `imports\totembar_manadump.txt`.

### Fixed
- Totem mana costs were read from **rank 1** instead of the highest rank you
  actually cast, so the displayed mana was far too low. The scan now resolves
  the highest known rank.

## v0.1.1 — 2026-07-09

### Added
- **Drop-set button** on the bar (right of the Totemic Recall button): one
  left-click casts all four chosen totems (the same action as the "Totems"
  macro, with the 2-second double-press guard).
- **Key bindings** — a **TotemBar** section in the Esc → Key Bindings menu:
  Drop all totems, Totemic Recall, Toggle bar, Toggle options, Toggle key-bind
  mode, Cast *element* totem (chosen, one per element), and — under per-element
  sub-sections — a binding to cast **every individual totem** (Cast Searing
  Totem, Cast Windfury Totem, …).
- **Hover-bind mode** (`/tb bind`, or the options panel's "Key bind mode"
  button): hover any bar button or a flyout totem and press a key to bind it
  (a button binds its action; a flyout totem binds that specific totem). ESC
  over a button clears its key; ESC over empty space (or the options button)
  exits. A "Key-Bind Mode ACTIVE" box is shown while active. The
  currently-bound key is displayed on each button at all times (abbreviated,
  e.g. `N7` for Num Pad 7). Bindings are saved by the game and persist.

### Notes
- Totemic Recall cast **deliberately** (the Recall button, or its keybinding)
  is never guarded — only the Totems macro's built-in recall respects the 2s
  double-press guard.

## v0.1.0 — 2026-07-09

Initial public release.

### Added
- Totem bar: four element buttons + a Totemic Recall button. Left-click an
  element casts its chosen totem; right-click clears the slot. Hover an element
  for a flyout of the element's other known totems (left-click to cast once,
  right-click to set as the new default).
- One-press "Totems" macro (`TotemBar.recallAndCastAll()`) with a 2-second
  double-press recall guard (a rapid second press won't recall the totems you
  just dropped).
- Native cooldown swipes + OmniCC-style duration timers; out-of-range red tint
  (buff-presence based); the Recall button pulses when a totem is out of range.
- Real in-game spell tooltips on the element buttons and the flyout.
- Minimap button (orbit-draggable; left-click = options, right-click = toggle
  bar); pfUI-safe, with `/tb options` as a fallback.
- Options panel: lock bar, auto-recall, show bar, recall guard, cycle-reset
  gap, UI size (scales the bar, anchored top-left), reset position, create
  "Totems" macro, and per-setting tooltips. Adopts pfUI's look when pfUI is
  installed, a clean Blizzard look otherwise.
- Assignment-receiver API (`TotemBar.ReceiveAssignment`) for a future raid
  totem-assignment addon — see [`docs/API.md`](docs/API.md).
