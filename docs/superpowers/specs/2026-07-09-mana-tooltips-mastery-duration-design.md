# TotemBar — Mana-cost / refund tooltips + Totemic Mastery duration fix (Design)

> Date: 2026-07-09 (Session 74 cont.) — tester/Phil feedback on v0.1.1.
> Status: scope approved (Phil, in-game chat) — pending spec sign-off.

## Purpose

Three related additions:
1. **Drop-set button tooltip** shows the total **mana cost** to drop the four chosen totems.
2. **Totemic Recall button tooltip** shows the **mana refunded** — computed from the totems
   *currently out* (excluding any that have already expired/disappeared), using the real refund
   percentage.
3. **Totemic Mastery duration fix** — on TurtleWoW the Totemic Mastery talent gives helpful totems
   **+20% duration** (and +15% recall refund; in-game-confirmed, unlike the vanilla range talent).
   When it's skilled, TotemBar's own duration timers must apply the +20% so they aren't short.

## Background (KG + in-game confirmed)

- **No `GetSpellManaCost` on 1.12.** Read a spell's mana cost via a hidden `GameTooltip`:
  `SetOwner(WorldFrame,"ANCHOR_NONE")`, `SetSpell(spellbookIndex, BOOKTYPE_SPELL)`, then read
  `getglobal(tipName.."TextLeft2")` (mana cost is *typically* line 2; verify per totem) and parse
  `"^(%d+) "` from the text. This **auto-reflects talent discounts** (Tidal Focus, Restorative
  Totems) — no need to model them. `SetSpell` takes a spellbook index (resolve via the existing
  `FindSpellIndexByName` scan). `SetHyperlink('spell:..')` is broken on 1.12 — don't use it.
- **Totemic Recall refund %** is not documented — treat as unknown; **learn it in-game** from the
  actual mana-gain message rather than hardcoding.
- **Totemic Mastery (TWoW)**: +20% duration to *helpful* totems, +15% recall refund. Detect via
  `GetTalentInfo(tab, i)` scanning for the talent named "Totemic Mastery" (rank > 0 = skilled).
  `GetTalentInfo` is stock 1.12 API (works on TWoW). Refresh on `CHARACTER_POINTS_CHANGED` /
  `PLAYER_ENTERING_WORLD`.

## Component 1 — Mana-cost reader (`core/manacost.lua` split pure/impl)

- Pure (offline-tested): `TotemBar.parseManaCost(text) -> number|nil` — from a tooltip line string
  like `"155 Mana"` (and `nil`/non-matching → nil). Uses `string.find(text, "^(%d+) ")`.
- WoW-API: `TotemBar.getTotemManaCost(name) -> number|nil` — resolves the spellbook slot
  (`FindSpellIndexByName`-style scan), sets a lazily-created hidden `GameTooltip`
  (`TotemBarScanTooltip`), scans lines 1..`NumLines()` for the first `parseManaCost` hit, and
  **caches** the result by totem name in a module table. Returns nil if the totem isn't known.
- **Cache invalidation:** clear the cache on `SPELLS_CHANGED` (fires on learning spells and on
  talent changes) so costs re-scan after a respec/rank change.

## Component 2 — Pure sum/refund/duration logic (`core/manacost.lua` or `core/bindlogic`-style)

All offline-tested, taking injected functions so no WoW API is needed:
- `TotemBar.sumChosenCost(chosen, elements, costFn) -> number` — sum `costFn(chosen[element])` over
  the elements that have a chosen totem (skip nil cost).
- `TotemBar.sumActiveCost(activeTotems, elements, now, costFn, remainingFn) -> number` — sum the
  cost of each element whose `activeTotems[element]` exists AND `remainingFn(rec.start, rec.duration,
  now) > 0` (so **expired/gone totems are excluded** — the "update as they disappear" requirement).
- `TotemBar.refundAmount(pct, activeCost) -> number` — `math.floor(pct * activeCost)`.
- `TotemBar.learnRefundPct(manaGained, activeCost) -> number|nil` — `manaGained/activeCost`, but only
  if `activeCost > 0` and the result is in a sane range (e.g. 0.05..1.0); else nil (don't learn from
  noise).
- `TotemBar.durationWithMastery(baseDuration, isHelpful, hasMastery) -> number` — `baseDuration * 1.2`
  when `hasMastery and isHelpful`, else `baseDuration`.
- `TotemBar.isHelpfulTotem(name) -> boolean` — from a set. **Default: all totems are helpful EXCEPT
  the pure fire-damage totems** `Searing Totem`, `Magma Totem`, `Fire Nova Totem`. ⚠️ Verify in-game
  which totems actually get the +20% and adjust the set.

## Component 3 — Totemic Mastery detection (in `cast.lua`/`manacost.lua`)

- `TotemBar.hasTotemicMastery() -> boolean` — reads a cached flag set by a scan:
  `for tab=1,GetNumTalentTabs() do for i=1,GetNumTalents(tab) do local name,_,_,_,rank =
  GetTalentInfo(tab,i); if name=="Totemic Mastery" and rank>0 then ... end end end`. Cache the
  boolean; a small event frame refreshes it on `PLAYER_ENTERING_WORLD` + `CHARACTER_POINTS_CHANGED`.

## Component 4 — Apply the duration fix (in `core/cast.lua` `recordCast`)

- Where `recordCast` computes `duration = TotemBar.totemDuration(name, highestRank)`, wrap it:
  `duration = TotemBar.durationWithMastery(TotemBar.totemDuration(name, highestRank),
  TotemBar.isHelpfulTotem(name), TotemBar.hasTotemicMastery())`. So own-tracking timers get the +20%.
- Scope note: the timer display prefers pfUI libtotem's `GetTotemInfo` when present (see
  `UpdateTimerDisplays`); libtotem may not know about Totemic Mastery, so with libtotem the shown
  time follows libtotem. This fix corrects the **own-tracking** path (the base case). Note for
  in-game check; a libtotem correction is a possible follow-up.

## Component 5 — Recall refund auto-learn (new small piece in `cast.lua`)

- On `TotemBar.CastRecall()` / the Recall button left-click, snapshot the summed cost of the
  currently-active totems into `TotemBar.recallPendingCost` just before casting, and set a short
  "expecting refund" window (timestamp).
- An event frame on `CHAT_MSG_SPELL_SELF_BUFF` (the message pfUI's TWoW fork already keys off for
  recall): when a "you gain N mana from Totemic Recall"-style message arrives within the window,
  parse `N`, compute `learnRefundPct(N, recallPendingCost)`, and if non-nil store it in
  `TotemBarDB.recallRefundPct`. (Parse the mana number with `string.find`; the exact message text is
  locale/format dependent — verify the pattern in-game.)
- Default `TotemBarDB.recallRefundPct = 0.25` (via `ensureDefaults`) until learned.

## Component 6 — The tooltips (`ui.lua`)

- **Drop-set button `OnEnter`** (recompute each hover): after the existing lines, add
  `Mana: <sumChosenCost(TotemBarDB.chosen, elements, getTotemManaCost)>` (omit the line if the sum
  is 0 / costs unavailable).
- **Recall button `OnEnter`** (recompute each hover): add
  `Refund: ~<refundAmount(TotemBarDB.recallRefundPct, sumActiveCost(activeTotems, elements, GetTime(),
  getTotemManaCost, TotemBar.remaining))> mana` — 0/omit if nothing is out. The `~` signals it's an
  estimate (the % is learned). Because it's computed live from `activeTotems` filtered by
  `remaining>0`, it already excludes disappeared totems.

## SavedVariables

- `TotemBarDB.recallRefundPct` (default 0.25, auto-learned). No other new SVs.

## Files

- **New** `core/manacost.lua` — pure helpers (`parseManaCost`, `sumChosenCost`, `sumActiveCost`,
  `refundAmount`, `learnRefundPct`, `durationWithMastery`, `isHelpfulTotem`) + WoW-API
  `getTotemManaCost` (hidden-tooltip scan + cache) + `hasTotemicMastery` (talent scan + cache + event
  refresh) + the CHAT_MSG_SPELL_SELF_BUFF refund-learner. (Split: the pure fns are what the tests
  import; the WoW-API pieces are guarded so `loadfile`/tests don't execute them.)
- **Modify** `core/config.lua` — `recallRefundPct` default.
- **Modify** `core/cast.lua` — `recordCast` applies `durationWithMastery`; expose/snapshot
  `recallPendingCost` for the learner (or keep that in manacost.lua reading `TotemBar.activeTotems`).
- **Modify** `ui.lua` — the two tooltip additions (drop-set + recall `OnEnter`).
- **Modify** `TotemBar.toc` — add `core\manacost.lua` (after totemdata/cast, before ui.lua).
- **New** `tools/luatests/test_manacost.lua` — offline tests for the pure helpers.
- ⚠️ New file `core\manacost.lua` → **full client restart** for the in-game task.

## Testing

- **Offline Lua 5.0**: `parseManaCost` ("155 Mana"→155, "Instant"→nil, nil→nil), `sumChosenCost`
  (skips nil), `sumActiveCost` (excludes expired via a stub remainingFn), `refundAmount` (floor),
  `learnRefundPct` (in-range vs out-of-range→nil, zero cost→nil), `durationWithMastery` (helpful+mastery
  →×1.2, else unchanged), `isHelpfulTotem` (Searing/Magma/Fire Nova false, others true).
- **In-game** (full restart): drop-set tooltip shows the correct summed mana (matches spellbook
  tooltips, incl. talent discounts); Recall tooltip shows a refund that tracks the totems currently
  out and drops as they expire; recall a set and confirm the learned % settles to a stable value;
  with Totemic Mastery skilled, helpful-totem timers are ~20% longer (and verify WHICH totems get it
  — adjust `isHelpfulTotem`); confirm the mana-cost tooltip line index (Left2) is right per totem.
- On confirmation, KG write-back: the verified totem mana-cost tooltip-scan line index, the learned
  recall refund %, and which totems the +20% applies to.

## Out of scope

- Correcting libtotem-sourced timers for Totemic Mastery (follow-up if needed).
- Modelling every talent's effect numbers (the scan handles costs; effects aren't shown).
