# Changelog

All notable changes to TotemBar are documented here.

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
