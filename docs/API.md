# TotemBar Integration API

TotemBar exposes a small, transport-agnostic seam — `core/assign.lua` — that
lets an external addon *suggest* a totem set to the player without TotemBar
knowing or caring how that suggestion arrived. A companion raid-assignment
addon (e.g. a "who casts which totem" coordinator) uses this seam to hand
TotemBar a proposed set of totems; TotemBar shows the player a pending
suggestion panel and lets them accept it with one click. TotemBar never
sends or receives addon messages itself — **all network transport
(`SendAddonMessage`, `CHAT_MSG_ADDON`, encoding, prefixes, etc.) is the
companion addon's responsibility.** Each client calls the API below
*locally*, after decoding whatever it received over its own channel.

This document describes the public interface only. Internal hook slots used
to wire `core/assign.lua` to `ui.lua` (`ShowAssignPanel`, `HideAssignPanel`,
`isTotemKnown`, `RefreshAll`) are implementation detail and not part of the
integration contract.

## Availability

TotemBar may not be installed, or may not have loaded yet. Always guard
calls:

```lua
if TotemBar and TotemBar.ReceiveAssignment then
    TotemBar.ReceiveAssignment(set, "Melee group")
end
```

## The totem set format

A **totem set** is a plain Lua table keyed by element name, mapping to the
totem's exact spell name as returned by `GetSpellName(i, BOOKTYPE_SPELL)`:

```lua
local set = {
    Fire = "Searing Totem",
    Air  = "Windfury Totem",
}
```

Any subset of the four elements is allowed — a missing element key simply
means "nothing suggested for that slot". The four valid element keys are
published as a constant:

```lua
TotemBar.TOTEM_ELEMENTS  -- { "Fire", "Earth", "Water", "Air" }
```

Any key not in `TotemBar.TOTEM_ELEMENTS` makes the whole set invalid (see
`ReceiveAssignment` below).

## API reference

### `TotemBar.ReceiveAssignment(set, label)`

The main entry point. An external assigner calls this to propose a totem
set to the local player.

- **Parameters:**
  - `set` (table, required) — a totem set as described above.
  - `label` (string, optional) — a short string shown as the heading on the
    suggestion panel (e.g. `"Melee group"`). May be `nil`.
- **Returns:**
  - `true` if the set was accepted and is now the pending suggestion.
  - `false, reason` (string) if `set` is malformed:
    - `set` is not a table
    - `set` is empty (no keys)
    - `set` contains a key that isn't one of `TotemBar.TOTEM_ELEMENTS`
    - a value in `set` is not a non-empty string
- **Behavior:** On success, stores a copy of the set as the pending
  suggestion (replacing any previously pending suggestion — there is only
  ever one pending suggestion at a time) and shows the suggestion panel to
  the player. **Does not apply or cast anything.** The player must
  explicitly accept it in-game.

### `TotemBar.GetChosenSet()`

Reads back the shaman's currently *chosen* totems (i.e. `TotemBarDB.chosen`,
the totems the bar's Fire/Earth/Water/Air buttons currently cast) — not the
pending suggestion.

- **Parameters:** none.
- **Returns:** a fresh table `{ element = name, ... }`, containing only the
  elements that currently have a chosen totem. Safe to mutate; it is a copy,
  not a reference into TotemBar's saved data.
- **Use case:** a companion addon can call this to show what each shaman in
  the raid currently has selected, e.g. after an assignment was applied or
  on request.

### `TotemBar.ClearAssignment()`

Drops any pending suggestion and hides the panel, without applying it.

- **Parameters:** none.
- **Returns:** nothing.
- **Use case:** a companion addon does not normally need to call this
  directly (the player's own Close button on the panel does it), but it's
  available if you want to programmatically retract a suggestion, e.g.
  after sending a corrected one is not desired and you'd rather cancel.

### `TotemBar.onAssignmentApplied`

An optional hook slot, `nil` by default. Not a function you call — a
function *you assign* to be notified when the player accepts a pending
suggestion.

- **Signature:** `function(appliedSet)`
  - `appliedSet` is a table `{ element = name, ... }` containing only the
    totems that were actually applied (totems the player doesn't know are
    skipped and are not included).
- **When it fires:** after the player accepts the pending suggestion (one
  click on the panel), after `TotemBarDB.chosen` has been updated and the
  bar refreshed, right before the panel is hidden.
- **Use case:** let the companion addon learn that the shaman accepted the
  assignment (e.g. to broadcast an acknowledgement to the raid).

## Example: a companion raid-assignment addon

Illustrative only — not shipped code. Assumes a raid leader's addon
broadcasts a simple `"Fire:Searing Totem;Air:Windfury Totem"` payload over
its own addon-message prefix, and every shaman's client decodes it locally
and hands it to TotemBar.

```lua
-- MyRaidAssign.lua (companion addon, NOT part of TotemBar)
local COMM_PREFIX = "MRA1"

local function DecodeSet(payload)
    -- "Fire:Searing Totem;Air:Windfury Totem" -> { Fire = "...", Air = "..." }
    local set = {}
    local pos = 1
    while pos <= string.len(payload) do
        local sep = string.find(payload, ";", pos, true)
        local chunk = string.sub(payload, pos, (sep or 0) - 1)
        if sep == nil then
            chunk = string.sub(payload, pos)
        end
        local colon = string.find(chunk, ":", 1, true)
        if colon then
            local element = string.sub(chunk, 1, colon - 1)
            local totem = string.sub(chunk, colon + 1)
            set[element] = totem
        end
        if sep == nil then break end
        pos = sep + 1
    end
    return set
end

local frame = CreateFrame("Frame", "MyRaidAssignCommFrame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function()
    if event ~= "CHAT_MSG_ADDON" or arg1 ~= COMM_PREFIX then
        return
    end
    local set = DecodeSet(arg2)
    if TotemBar and TotemBar.ReceiveAssignment then
        local ok, reason = TotemBar.ReceiveAssignment(set, "Melee group")
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("MyRaidAssign: bad set - " .. reason)
        end
    end
end)

-- Optional: get notified once the shaman accepts, to ack back to the raid.
if TotemBar then
    TotemBar.onAssignmentApplied = function(appliedSet)
        SendAddonMessage(COMM_PREFIX, "ACK", "RAID")
    end
end
```

## Notes / guarantees

- **No auto-cast.** `ReceiveAssignment` never casts a totem and never
  changes `TotemBarDB.chosen` by itself; it only stages a suggestion for
  the player to review.
- **Unknown totems are skipped, not rejected.** A set can name a totem the
  player hasn't learned yet; validation still succeeds, the panel greys out
  that slot, and applying the suggestion silently skips it (that element's
  chosen totem, if any, is left unchanged).
- **Pending state is in-memory only.** `TotemBar.pending` is not a
  SavedVariable. An un-accepted suggestion does not survive `/reload` or a
  logout — the companion addon should be prepared to resend if needed.
- **One pending suggestion at a time.** Calling `ReceiveAssignment` again
  before the player accepts or clears the previous one silently replaces
  it.
- **Transport is out of scope.** TotemBar has no knowledge of
  `SendAddonMessage`, prefixes, or serialization formats — that is entirely
  the companion addon's design choice.
